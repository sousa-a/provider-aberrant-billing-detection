-- =============================================================================
-- P3 — Provider Aberrant Billing Pattern Detection
-- 05_provider_peer_views.sql
--
-- Purpose : Provider-level billing metrics, peer group assignment, and
--           z-score computation — the core analytical views for P3.
--
-- These views produce the dataset that feeds both the SAS statistical
-- analysis (PROC STDIZE, PROC RANK) and the Python anomaly detection
-- (Isolation Forest, SHAP).
--
-- Peer group definition: (derived_specialty, volume_tier)
--   - Volume tier: Low (<P25), Medium (P25-P75), High (>P75)
--   - Minimum peer group size: 10 providers
--   - State is NOT included in peer group key here.
-- =============================================================================

USE DATABASE MEDICARE_FWA;
USE SCHEMA ANALYTICS;
USE WAREHOUSE FWA_WH;

-- -------------------------------------------------------
-- 1. VW_PROVIDER_BILLING_METRICS
--    One row per provider with all billing features
--    for the profiling model
-- -------------------------------------------------------
CREATE OR REPLACE VIEW VW_PROVIDER_BILLING_METRICS AS
WITH claim_line_stats AS (
    SELECT
        f.provider_npi,
        -- Volume metrics
        COUNT(*)                                    AS total_lines,
        COUNT(DISTINCT f.CLM_ID)                    AS total_claims,
        COUNT(DISTINCT f.beneficiary_id)            AS distinct_beneficiaries,
        -- Financial metrics
        SUM(f.payment_amount)                       AS total_paid,
        SUM(f.allowed_charge_amount)                AS total_allowed_charges,
        AVG(f.payment_amount)                       AS avg_paid_per_line,
        AVG(f.allowed_charge_amount)                AS avg_allowed_per_line,
        MEDIAN(f.payment_amount)                    AS median_paid_per_line,
        -- Utilization intensity
        COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT f.beneficiary_id), 0)
                                                    AS lines_per_beneficiary,
        COUNT(DISTINCT f.CLM_ID) * 1.0 / NULLIF(COUNT(DISTINCT f.beneficiary_id), 0)
                                                    AS claims_per_beneficiary,
        -- Code diversity
        COUNT(DISTINCT f.hcpcs_code)                AS distinct_hcpcs_codes,
        -- HCPCS concentration: fraction of lines on the single most-used code
        MAX(hcpcs_freq) * 1.0 / COUNT(*)            AS hcpcs_concentration,
        -- Diagnosis complexity: avg distinct claim-level diagnosis codes per claim
        AVG(dgns_count)                             AS avg_diagnoses_per_claim,
        -- High complexity E&M: % of lines with codes 99214-99215
        SUM(CASE WHEN f.hcpcs_code IN ('99214','99215') THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*)                      AS pct_high_complexity_em,
        -- Temporal span
        DATEDIFF('day', MIN(f.service_from_date), MAX(f.service_from_date))
                                                    AS service_span_days
    FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES f
    LEFT JOIN (
        -- Subquery: most frequent HCPCS per provider
        SELECT provider_npi, MAX(cnt) AS hcpcs_freq
        FROM (
            SELECT provider_npi, hcpcs_code, COUNT(*) AS cnt
            FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES
            GROUP BY provider_npi, hcpcs_code
        )
        GROUP BY provider_npi
    ) hf ON f.provider_npi = hf.provider_npi
    LEFT JOIN (
        -- Subquery: distinct diagnosis codes per claim
        SELECT CLM_ID,
            ( (clm_dgns_cd_1 IS NOT NULL)::INT +
              (clm_dgns_cd_2 IS NOT NULL)::INT +
              (clm_dgns_cd_3 IS NOT NULL)::INT +
              (clm_dgns_cd_4 IS NOT NULL)::INT +
              (clm_dgns_cd_5 IS NOT NULL)::INT +
              (clm_dgns_cd_6 IS NOT NULL)::INT +
              (clm_dgns_cd_7 IS NOT NULL)::INT +
              (clm_dgns_cd_8 IS NOT NULL)::INT
            ) AS dgns_count
        FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES
        GROUP BY CLM_ID,
                 clm_dgns_cd_1, clm_dgns_cd_2, clm_dgns_cd_3, clm_dgns_cd_4,
                 clm_dgns_cd_5, clm_dgns_cd_6, clm_dgns_cd_7, clm_dgns_cd_8
    ) dc ON f.CLM_ID = dc.CLM_ID
    WHERE f.provider_npi IS NOT NULL
    GROUP BY f.provider_npi
),
-- Join with beneficiary data for patient complexity metrics
bene_complexity AS (
    SELECT
        f.provider_npi,
        AVG(b.age_at_end)                           AS avg_beneficiary_age,
        AVG(b.chronic_condition_count)               AS avg_beneficiary_cc_count,
        SUM(CASE WHEN b.chronic_condition_count >= 3 THEN 1 ELSE 0 END)
            * 100.0 / NULLIF(COUNT(DISTINCT f.beneficiary_id), 0)
                                                    AS pct_complex_beneficiaries
    FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES f
    JOIN ANALYTICS.DIM_BENEFICIARY b
        ON f.beneficiary_id = b.DESYNPUF_ID
    WHERE f.provider_npi IS NOT NULL
    GROUP BY f.provider_npi
)
SELECT
    c.provider_npi,
    p.derived_specialty,
    -- Volume
    c.total_lines,
    c.total_claims,
    c.distinct_beneficiaries,
    -- Financial
    c.total_paid,
    c.total_allowed_charges,
    c.avg_paid_per_line,
    c.avg_allowed_per_line,
    c.median_paid_per_line,
    -- Intensity
    c.lines_per_beneficiary,
    c.claims_per_beneficiary,
    -- Code patterns
    c.distinct_hcpcs_codes,
    c.hcpcs_concentration,
    c.avg_diagnoses_per_claim,
    c.pct_high_complexity_em,
    -- Patient complexity
    bc.avg_beneficiary_age,
    bc.avg_beneficiary_cc_count,
    bc.pct_complex_beneficiaries,
    -- Temporal
    c.service_span_days
FROM claim_line_stats c
JOIN ANALYTICS.DIM_PROVIDER p ON c.provider_npi = p.provider_npi
LEFT JOIN bene_complexity bc ON c.provider_npi = bc.provider_npi;

-- -------------------------------------------------------
-- 2. VW_PROVIDER_PEER_GROUPS
--    Assign each provider to a peer group based on
--    derived_specialty and volume_tier
-- -------------------------------------------------------
CREATE OR REPLACE VIEW VW_PROVIDER_PEER_GROUPS AS
WITH volume_percentiles AS (
    SELECT
        derived_specialty,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_lines) AS p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_lines) AS p75
    FROM VW_PROVIDER_BILLING_METRICS
    GROUP BY derived_specialty
)
SELECT
    m.*,
    CASE
        WHEN m.total_lines < vp.p25 THEN 'Low'
        WHEN m.total_lines > vp.p75 THEN 'High'
        ELSE 'Medium'
    END AS volume_tier,
    m.derived_specialty || '_' ||
    CASE
        WHEN m.total_lines < vp.p25 THEN 'Low'
        WHEN m.total_lines > vp.p75 THEN 'High'
        ELSE 'Medium'
    END AS peer_group_key
FROM VW_PROVIDER_BILLING_METRICS m
JOIN volume_percentiles vp ON m.derived_specialty = vp.derived_specialty;

-- -------------------------------------------------------
-- 3. VW_PEER_STATISTICS
--    Per-peer-group mean and stddev for z-score computation
--    Only for peer groups with >= 10 providers
-- -------------------------------------------------------
CREATE OR REPLACE VIEW VW_PEER_STATISTICS AS
SELECT
    peer_group_key,
    derived_specialty,
    volume_tier,
    COUNT(*) AS peer_group_size,
    -- Mean and stddev for each metric used in z-score calculation
    AVG(avg_paid_per_line)          AS mean_avg_paid,
    STDDEV(avg_paid_per_line)       AS sd_avg_paid,
    AVG(lines_per_beneficiary)      AS mean_lines_per_bene,
    STDDEV(lines_per_beneficiary)   AS sd_lines_per_bene,
    AVG(claims_per_beneficiary)     AS mean_claims_per_bene,
    STDDEV(claims_per_beneficiary)  AS sd_claims_per_bene,
    AVG(hcpcs_concentration)        AS mean_hcpcs_conc,
    STDDEV(hcpcs_concentration)     AS sd_hcpcs_conc,
    AVG(pct_high_complexity_em)     AS mean_pct_high_em,
    STDDEV(pct_high_complexity_em)  AS sd_pct_high_em,
    AVG(avg_diagnoses_per_claim)    AS mean_avg_dgns,
    STDDEV(avg_diagnoses_per_claim) AS sd_avg_dgns,
    AVG(total_paid)                 AS mean_total_paid,
    STDDEV(total_paid)              AS sd_total_paid
FROM VW_PROVIDER_PEER_GROUPS
GROUP BY peer_group_key, derived_specialty, volume_tier
HAVING COUNT(*) >= 10;  -- Minimum peer group size threshold

-- -------------------------------------------------------
-- 4. VW_PROVIDER_ZSCORE_FLAGS
--    Z-scores per provider per metric, within peer group
--    Flags providers with |z| > 2.0 or |z| > 3.0
-- -------------------------------------------------------
CREATE OR REPLACE VIEW VW_PROVIDER_ZSCORE_FLAGS AS
SELECT
    pg.provider_npi,
    pg.derived_specialty,
    pg.peer_group_key,
    pg.volume_tier,
    ps.peer_group_size,
    -- Raw metrics
    pg.total_paid,
    pg.avg_paid_per_line,
    pg.lines_per_beneficiary,
    pg.claims_per_beneficiary,
    pg.hcpcs_concentration,
    pg.pct_high_complexity_em,
    pg.avg_diagnoses_per_claim,
    pg.distinct_beneficiaries,
    pg.total_lines,
    -- Patient complexity
    pg.avg_beneficiary_age,
    pg.avg_beneficiary_cc_count,
    pg.pct_complex_beneficiaries,
    -- Peer group means (for reference / excess billing calculation)
    ps.mean_avg_paid,
    ps.mean_total_paid,
    -- Z-scores (guarded against zero stddev)
    CASE WHEN ps.sd_avg_paid > 0
         THEN (pg.avg_paid_per_line - ps.mean_avg_paid) / ps.sd_avg_paid
         ELSE NULL END                               AS z_avg_paid,
    CASE WHEN ps.sd_lines_per_bene > 0
         THEN (pg.lines_per_beneficiary - ps.mean_lines_per_bene) / ps.sd_lines_per_bene
         ELSE NULL END                               AS z_lines_per_bene,
    CASE WHEN ps.sd_claims_per_bene > 0
         THEN (pg.claims_per_beneficiary - ps.mean_claims_per_bene) / ps.sd_claims_per_bene
         ELSE NULL END                               AS z_claims_per_bene,
    CASE WHEN ps.sd_hcpcs_conc > 0
         THEN (pg.hcpcs_concentration - ps.mean_hcpcs_conc) / ps.sd_hcpcs_conc
         ELSE NULL END                               AS z_hcpcs_conc,
    CASE WHEN ps.sd_pct_high_em > 0
         THEN (pg.pct_high_complexity_em - ps.mean_pct_high_em) / ps.sd_pct_high_em
         ELSE NULL END                               AS z_pct_high_em,
    CASE WHEN ps.sd_avg_dgns > 0
         THEN (pg.avg_diagnoses_per_claim - ps.mean_avg_dgns) / ps.sd_avg_dgns
         ELSE NULL END                               AS z_avg_dgns,
    CASE WHEN ps.sd_total_paid > 0
         THEN (pg.total_paid - ps.mean_total_paid) / ps.sd_total_paid
         ELSE NULL END                               AS z_total_paid,
    -- Maximum absolute z-score across all metrics (composite signal)
    GREATEST(
        ABS(COALESCE(CASE WHEN ps.sd_avg_paid > 0 THEN (pg.avg_paid_per_line - ps.mean_avg_paid) / ps.sd_avg_paid END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_lines_per_bene > 0 THEN (pg.lines_per_beneficiary - ps.mean_lines_per_bene) / ps.sd_lines_per_bene END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_claims_per_bene > 0 THEN (pg.claims_per_beneficiary - ps.mean_claims_per_bene) / ps.sd_claims_per_bene END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_hcpcs_conc > 0 THEN (pg.hcpcs_concentration - ps.mean_hcpcs_conc) / ps.sd_hcpcs_conc END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_pct_high_em > 0 THEN (pg.pct_high_complexity_em - ps.mean_pct_high_em) / ps.sd_pct_high_em END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_avg_dgns > 0 THEN (pg.avg_diagnoses_per_claim - ps.mean_avg_dgns) / ps.sd_avg_dgns END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_total_paid > 0 THEN (pg.total_paid - ps.mean_total_paid) / ps.sd_total_paid END, 0))
    )                                                AS z_max_abs,
    -- Flag columns
    CASE WHEN GREATEST(
        ABS(COALESCE(CASE WHEN ps.sd_avg_paid > 0 THEN (pg.avg_paid_per_line - ps.mean_avg_paid) / ps.sd_avg_paid END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_lines_per_bene > 0 THEN (pg.lines_per_beneficiary - ps.mean_lines_per_bene) / ps.sd_lines_per_bene END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_claims_per_bene > 0 THEN (pg.claims_per_beneficiary - ps.mean_claims_per_bene) / ps.sd_claims_per_bene END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_hcpcs_conc > 0 THEN (pg.hcpcs_concentration - ps.mean_hcpcs_conc) / ps.sd_hcpcs_conc END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_pct_high_em > 0 THEN (pg.pct_high_complexity_em - ps.mean_pct_high_em) / ps.sd_pct_high_em END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_avg_dgns > 0 THEN (pg.avg_diagnoses_per_claim - ps.mean_avg_dgns) / ps.sd_avg_dgns END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_total_paid > 0 THEN (pg.total_paid - ps.mean_total_paid) / ps.sd_total_paid END, 0))
    ) > 2.0 THEN TRUE ELSE FALSE END                AS flag_zscore_2,
    CASE WHEN GREATEST(
        ABS(COALESCE(CASE WHEN ps.sd_avg_paid > 0 THEN (pg.avg_paid_per_line - ps.mean_avg_paid) / ps.sd_avg_paid END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_lines_per_bene > 0 THEN (pg.lines_per_beneficiary - ps.mean_lines_per_bene) / ps.sd_lines_per_bene END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_claims_per_bene > 0 THEN (pg.claims_per_beneficiary - ps.mean_claims_per_bene) / ps.sd_claims_per_bene END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_hcpcs_conc > 0 THEN (pg.hcpcs_concentration - ps.mean_hcpcs_conc) / ps.sd_hcpcs_conc END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_pct_high_em > 0 THEN (pg.pct_high_complexity_em - ps.mean_pct_high_em) / ps.sd_pct_high_em END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_avg_dgns > 0 THEN (pg.avg_diagnoses_per_claim - ps.mean_avg_dgns) / ps.sd_avg_dgns END, 0)),
        ABS(COALESCE(CASE WHEN ps.sd_total_paid > 0 THEN (pg.total_paid - ps.mean_total_paid) / ps.sd_total_paid END, 0))
    ) > 3.0 THEN TRUE ELSE FALSE END                AS flag_zscore_3,
    -- Excess billing estimate (provider total - peer mean × provider volume)
    pg.total_paid - (ps.mean_avg_paid * pg.total_lines) AS excess_billing_vs_mean
FROM VW_PROVIDER_PEER_GROUPS pg
JOIN VW_PEER_STATISTICS ps ON pg.peer_group_key = ps.peer_group_key;

-- -------------------------------------------------------
-- SUMMARY QUERIES — Run after creating all views
-- -------------------------------------------------------

-- How many providers flagged at each threshold?
SELECT
    COUNT(*) AS total_providers_in_valid_peer_groups,
    SUM(flag_zscore_2::INT) AS flagged_z2,
    ROUND(SUM(flag_zscore_2::INT) * 100.0 / COUNT(*), 2) AS pct_flagged_z2,
    SUM(flag_zscore_3::INT) AS flagged_z3,
    ROUND(SUM(flag_zscore_3::INT) * 100.0 / COUNT(*), 2) AS pct_flagged_z3,
    SUM(CASE WHEN excess_billing_vs_mean > 0 THEN excess_billing_vs_mean ELSE 0 END) AS total_excess_billing_flagged
FROM VW_PROVIDER_ZSCORE_FLAGS
WHERE flag_zscore_2 = TRUE;

-- Peer group size distribution
SELECT
    peer_group_key,
    peer_group_size,
    derived_specialty,
    volume_tier
FROM VW_PEER_STATISTICS
ORDER BY peer_group_size DESC;

-- Top 20 flagged providers by excess billing
SELECT
    provider_npi,
    derived_specialty,
    peer_group_key,
    peer_group_size,
    total_paid,
    mean_total_paid AS peer_mean_total_paid,
    excess_billing_vs_mean,
    z_max_abs,
    z_avg_paid,
    z_lines_per_bene,
    z_pct_high_em,
    distinct_beneficiaries,
    total_lines,
    flag_zscore_2,
    flag_zscore_3
FROM VW_PROVIDER_ZSCORE_FLAGS
WHERE flag_zscore_2 = TRUE
ORDER BY excess_billing_vs_mean DESC
LIMIT 20;

-- -------------------------------------------------------
-- EXPORT FOR PYTHON AND SAS:
-- The VW_PROVIDER_ZSCORE_FLAGS view is the primary export target.
-- Export to CSV for downstream analysis:
--
--   -- In Snowsight: click the download button on query results
--   -- Or via SnowSQL:
--   --   !set output_format=csv
--   --   !set output_file=provider_zscore_flags.csv
--   --   SELECT * FROM VW_PROVIDER_ZSCORE_FLAGS;
--
-- This CSV feeds:
--   - SAS (02_peer_comparison.sas) for PROC RANK and PROC SGPLOT
--   - Python Notebook 03 (anomaly_detection) for Isolation Forest
--   - Python Notebook 04 (cross_method_validation) for concordance
-- -------------------------------------------------------
