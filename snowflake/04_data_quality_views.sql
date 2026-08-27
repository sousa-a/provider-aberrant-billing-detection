-- =============================================================================
-- P3 — Provider Aberrant Billing Pattern Detection
-- 04_data_quality_views.sql
--
-- Purpose : Data quality assessment views in the DATA_QUALITY schema.
--           These views must be executed and documented BEFORE any
--           analytical work begins. They form the "quality contract"
--           that justifies downstream decisions (column exclusions,
--           minimum volume thresholds, distribution assumptions).
--
-- Four assessment dimensions:
--   1. Completeness — % of non-null values per column
--   2. Referential integrity — orphaned keys between tables
--   3. Temporal consistency — date logic violations
--   4. Cardinality profile — distribution of key counts
-- =============================================================================

USE DATABASE MEDICARE_FWA;
USE SCHEMA DATA_QUALITY;
USE WAREHOUSE FWA_WH;

-- -------------------------------------------------------
-- 1. COMPLETENESS REPORT
--    % NOT NULL per column, per key table
-- -------------------------------------------------------

-- 1a. Carrier claim lines (core table for P3)
CREATE OR REPLACE VIEW VW_COMPLETENESS_CARRIER_LINES AS
SELECT
    'FACT_CARRIER_CLAIM_LINES'               AS table_name,
    COUNT(*)                                 AS total_rows,
    ROUND(COUNT(CLM_ID)              * 100.0 / COUNT(*), 2) AS pct_clm_id,
    ROUND(COUNT(beneficiary_id)      * 100.0 / COUNT(*), 2) AS pct_beneficiary_id,
    ROUND(COUNT(service_from_date)   * 100.0 / COUNT(*), 2) AS pct_service_from_date,
    ROUND(COUNT(service_thru_date)   * 100.0 / COUNT(*), 2) AS pct_service_thru_date,
    ROUND(COUNT(provider_npi)        * 100.0 / COUNT(*), 2) AS pct_provider_npi,
    ROUND(COUNT(hcpcs_code)          * 100.0 / COUNT(*), 2) AS pct_hcpcs_code,
    ROUND(COUNT(payment_amount)      * 100.0 / COUNT(*), 2) AS pct_payment_amount,
    ROUND(COUNT(allowed_charge_amount) * 100.0 / COUNT(*), 2) AS pct_allowed_charge,
    ROUND(COUNT(deductible_amount)   * 100.0 / COUNT(*), 2) AS pct_deductible,
    ROUND(COUNT(coinsurance_amount)  * 100.0 / COUNT(*), 2) AS pct_coinsurance,
    ROUND(COUNT(line_diagnosis_code) * 100.0 / COUNT(*), 2) AS pct_line_diagnosis,
    ROUND(COUNT(clm_dgns_cd_1)       * 100.0 / COUNT(*), 2) AS pct_clm_dgns_cd_1,
    ROUND(COUNT(processing_indicator) * 100.0 / COUNT(*), 2) AS pct_processing_ind
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES;

-- 1b. Beneficiary dimension
CREATE OR REPLACE VIEW VW_COMPLETENESS_BENEFICIARY AS
SELECT
    'DIM_BENEFICIARY'                        AS table_name,
    COUNT(*)                                 AS total_rows,
    ROUND(COUNT(DESYNPUF_ID)         * 100.0 / COUNT(*), 2) AS pct_desynpuf_id,
    ROUND(COUNT(birth_date)          * 100.0 / COUNT(*), 2) AS pct_birth_date,
    ROUND(COUNT(death_date)          * 100.0 / COUNT(*), 2) AS pct_death_date,
    ROUND(COUNT(sex)                 * 100.0 / COUNT(*), 2) AS pct_sex,
    ROUND(COUNT(race)                * 100.0 / COUNT(*), 2) AS pct_race,
    ROUND(COUNT(state_code)          * 100.0 / COUNT(*), 2) AS pct_state_code,
    ROUND(COUNT(county_code)         * 100.0 / COUNT(*), 2) AS pct_county_code,
    ROUND(COUNT(part_a_coverage_months) * 100.0 / COUNT(*), 2) AS pct_part_a_months,
    ROUND(COUNT(part_b_coverage_months) * 100.0 / COUNT(*), 2) AS pct_part_b_months,
    ROUND(COUNT(chronic_condition_count) * 100.0 / COUNT(*), 2) AS pct_cc_count,
    ROUND(COUNT(summary_year)        * 100.0 / COUNT(*), 2) AS pct_summary_year
FROM ANALYTICS.DIM_BENEFICIARY;

-- 1c. Provider dimension
CREATE OR REPLACE VIEW VW_COMPLETENESS_PROVIDER AS
SELECT
    'DIM_PROVIDER'                           AS table_name,
    COUNT(*)                                 AS total_rows,
    ROUND(COUNT(provider_npi)        * 100.0 / COUNT(*), 2) AS pct_provider_npi,
    ROUND(COUNT(top_hcpcs_code)      * 100.0 / COUNT(*), 2) AS pct_top_hcpcs,
    ROUND(COUNT(derived_specialty)   * 100.0 / COUNT(*), 2) AS pct_derived_specialty,
    ROUND(COUNT(total_paid)          * 100.0 / COUNT(*), 2) AS pct_total_paid,
    ROUND(COUNT(first_service_date)  * 100.0 / COUNT(*), 2) AS pct_first_svc_date,
    ROUND(COUNT(last_service_date)   * 100.0 / COUNT(*), 2) AS pct_last_svc_date
FROM ANALYTICS.DIM_PROVIDER;

-- -------------------------------------------------------
-- 2. REFERENTIAL INTEGRITY
--    Orphaned keys between fact and dimension tables
-- -------------------------------------------------------
CREATE OR REPLACE VIEW VW_REFERENTIAL_INTEGRITY AS
-- Claim lines with no matching beneficiary
SELECT
    'carrier_lines_no_beneficiary' AS check_name,
    COUNT(DISTINCT f.beneficiary_id) AS orphan_count,
    (SELECT COUNT(DISTINCT DESYNPUF_ID) FROM ANALYTICS.DIM_BENEFICIARY) AS dim_count,
    'Carrier claim lines where beneficiary_id not in DIM_BENEFICIARY' AS description
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES f
LEFT JOIN ANALYTICS.DIM_BENEFICIARY b
    ON f.beneficiary_id = b.DESYNPUF_ID
WHERE b.DESYNPUF_ID IS NULL

UNION ALL

-- Claim lines with no matching provider
SELECT
    'carrier_lines_no_provider',
    COUNT(DISTINCT f.provider_npi),
    (SELECT COUNT(DISTINCT provider_npi) FROM ANALYTICS.DIM_PROVIDER),
    'Carrier claim lines where provider_npi not in DIM_PROVIDER'
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES f
LEFT JOIN ANALYTICS.DIM_PROVIDER p
    ON f.provider_npi = p.provider_npi
WHERE p.provider_npi IS NULL
  AND f.provider_npi IS NOT NULL

UNION ALL

-- Providers with zero claim lines (should be 0 by construction)
SELECT
    'providers_no_claims',
    COUNT(DISTINCT p.provider_npi),
    (SELECT COUNT(*) FROM ANALYTICS.DIM_PROVIDER),
    'Providers in DIM_PROVIDER with no lines in FACT_CARRIER_CLAIM_LINES'
FROM ANALYTICS.DIM_PROVIDER p
LEFT JOIN ANALYTICS.FACT_CARRIER_CLAIM_LINES f
    ON p.provider_npi = f.provider_npi
WHERE f.provider_npi IS NULL;

-- -------------------------------------------------------
-- 3. TEMPORAL CONSISTENCY
--    Date logic violations that may indicate data quality issues
-- -------------------------------------------------------
CREATE OR REPLACE VIEW VW_TEMPORAL_CONSISTENCY AS
-- Service dates outside expected range (2008-01-01 to 2010-12-31)
SELECT
    'service_date_out_of_range' AS check_name,
    COUNT(*) AS violation_count,
    (SELECT COUNT(*) FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES) AS total_rows,
    ROUND(COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES), 4
    ) AS pct_violations,
    'service_from_date outside 2008-01-01 to 2010-12-31' AS description
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES
WHERE service_from_date < '2008-01-01'
   OR service_from_date > '2010-12-31'

UNION ALL

-- Service end date before start date
SELECT
    'service_end_before_start',
    COUNT(*),
    (SELECT COUNT(*) FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES),
    ROUND(COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES), 4),
    'service_thru_date < service_from_date'
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES
WHERE service_thru_date < service_from_date

UNION ALL

-- Beneficiaries with claims after death date
SELECT
    'claims_after_death',
    COUNT(DISTINCT f.beneficiary_id),
    (SELECT COUNT(DISTINCT beneficiary_id) FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES),
    ROUND(COUNT(DISTINCT f.beneficiary_id) * 100.0 /
        (SELECT COUNT(DISTINCT beneficiary_id) FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES), 4),
    'Beneficiaries with service_from_date > death_date'
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES f
JOIN ANALYTICS.DIM_BENEFICIARY b
    ON f.beneficiary_id = b.DESYNPUF_ID
WHERE b.death_date IS NOT NULL
  AND f.service_from_date > b.death_date;

-- -------------------------------------------------------
-- 4. CARDINALITY PROFILE
--    Distribution of key counts to understand data shape
-- -------------------------------------------------------

-- 4a. Claims per provider distribution
CREATE OR REPLACE VIEW VW_CARDINALITY_CLAIMS_PER_PROVIDER AS
SELECT
    'claims_per_provider' AS metric,
    COUNT(DISTINCT provider_npi) AS total_providers,
    ROUND(AVG(line_count), 1) AS mean_lines,
    MEDIAN(line_count) AS median_lines,
    MIN(line_count) AS min_lines,
    MAX(line_count) AS max_lines,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY line_count) AS p25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY line_count) AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY line_count) AS p90,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY line_count) AS p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY line_count) AS p99,
    COUNT(CASE WHEN line_count < 5 THEN 1 END) AS providers_under_5_lines,
    COUNT(CASE WHEN line_count < 10 THEN 1 END) AS providers_under_10_lines
FROM (
    SELECT provider_npi, COUNT(*) AS line_count
    FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES
    WHERE provider_npi IS NOT NULL
    GROUP BY provider_npi
);

-- 4b. Beneficiaries per provider distribution
CREATE OR REPLACE VIEW VW_CARDINALITY_BENES_PER_PROVIDER AS
SELECT
    'beneficiaries_per_provider' AS metric,
    COUNT(DISTINCT provider_npi) AS total_providers,
    ROUND(AVG(bene_count), 1) AS mean_benes,
    MEDIAN(bene_count) AS median_benes,
    MIN(bene_count) AS min_benes,
    MAX(bene_count) AS max_benes,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY bene_count) AS p95
FROM (
    SELECT provider_npi, COUNT(DISTINCT beneficiary_id) AS bene_count
    FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES
    WHERE provider_npi IS NOT NULL
    GROUP BY provider_npi
);

-- 4c. Payment amount distribution
CREATE OR REPLACE VIEW VW_CARDINALITY_PAYMENT_DIST AS
SELECT
    'payment_amount' AS metric,
    COUNT(*) AS total_lines,
    ROUND(AVG(payment_amount), 2) AS mean_payment,
    MEDIAN(payment_amount) AS median_payment,
    MIN(payment_amount) AS min_payment,
    MAX(payment_amount) AS max_payment,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY payment_amount) AS p25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY payment_amount) AS p75,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY payment_amount) AS p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY payment_amount) AS p99,
    COUNT(CASE WHEN payment_amount = 0 THEN 1 END) AS zero_payment_count,
    COUNT(CASE WHEN payment_amount < 0 THEN 1 END) AS negative_payment_count
FROM ANALYTICS.FACT_CARRIER_CLAIM_LINES;

-- 4d. Provider count by derived specialty
CREATE OR REPLACE VIEW VW_CARDINALITY_BY_SPECIALTY AS
SELECT
    derived_specialty,
    COUNT(*) AS provider_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    SUM(total_claim_lines) AS total_lines,
    ROUND(AVG(total_paid), 2) AS avg_total_paid,
    ROUND(MEDIAN(total_paid), 2) AS median_total_paid,
    ROUND(AVG(distinct_beneficiaries), 1) AS avg_distinct_benes
FROM ANALYTICS.DIM_PROVIDER
GROUP BY derived_specialty
ORDER BY provider_count DESC;
