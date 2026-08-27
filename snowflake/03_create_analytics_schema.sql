-- =============================================================================
-- P3 — Provider Aberrant Billing Pattern Detection
-- 03_create_analytics_schema.sql
--
-- Purpose : Transform RAW staging data into a dimensional model (ANALYTICS).
--           This is where type casting, date parsing, and the critical
--           carrier claims wide-to-long unpivot happen.
--
-- Design decisions documented inline:
--   - Carrier claims: unpivot from 13 line items per row to 1 row per line
--   - FACT_CLAIMS: line-level granularity across all claim types
--   - Provider ID: PRF_PHYSN_NPI from carrier, AT_PHYSN_NPI from IP/OP
--   - Dates: parsed from YYYYMMDD VARCHAR to DATE type
-- =============================================================================

USE DATABASE MEDICARE_FWA;
USE SCHEMA ANALYTICS;
USE WAREHOUSE FWA_WH;

-- -------------------------------------------------------
-- 1. DIM_BENEFICIARY
--    One row per beneficiary per year
--    Chronic condition flags: 1=Yes, 2=No → converted to boolean
-- -------------------------------------------------------
CREATE OR REPLACE TABLE DIM_BENEFICIARY AS
SELECT
    DESYNPUF_ID,
    TRY_TO_DATE(BENE_BIRTH_DT, 'YYYYMMDD')             AS birth_date,
    TRY_TO_DATE(BENE_DEATH_DT, 'YYYYMMDD')             AS death_date,
    CASE WHEN BENE_DEATH_DT IS NOT NULL THEN TRUE ELSE FALSE END AS is_deceased,
    DATEDIFF('year',
        TRY_TO_DATE(BENE_BIRTH_DT, 'YYYYMMDD'),
        COALESCE(TRY_TO_DATE(BENE_DEATH_DT, 'YYYYMMDD'), '2010-12-31')
    )                                                    AS age_at_end,
    CASE WHEN TRY_CAST(BENE_SEX_IDENT_CD AS INTEGER) = 1 THEN 'Male'
         WHEN TRY_CAST(BENE_SEX_IDENT_CD AS INTEGER) = 2 THEN 'Female'
         ELSE 'Unknown' END                              AS sex,
    CASE WHEN BENE_RACE_CD = '1' THEN 'White'
         WHEN BENE_RACE_CD = '2' THEN 'Black'
         WHEN BENE_RACE_CD = '3' THEN 'Others'
         WHEN BENE_RACE_CD = '5' THEN 'Hispanic'
         ELSE 'Unknown' END                              AS race,
    CASE WHEN BENE_ESRD_IND = 'Y' THEN TRUE ELSE FALSE END AS has_esrd,
    LPAD(SP_STATE_CODE, 2, '0')                          AS state_code,
    BENE_COUNTY_CD                                       AS county_code,
    TRY_CAST(BENE_HI_CVRAGE_TOT_MONS AS INTEGER)        AS part_a_coverage_months,
    TRY_CAST(BENE_SMI_CVRAGE_TOT_MONS AS INTEGER)       AS part_b_coverage_months,
    TRY_CAST(BENE_HMO_CVRAGE_TOT_MONS AS INTEGER)       AS hmo_coverage_months,
    TRY_CAST(PLAN_CVRG_MOS_NUM AS INTEGER)               AS part_d_coverage_months,
    -- Chronic conditions: 1=Yes, 2=No → boolean
    (SP_ALZHDMTA = '1')::BOOLEAN                         AS cc_alzheimer,
    (SP_CHF      = '1')::BOOLEAN                         AS cc_heart_failure,
    (SP_CHRNKIDN = '1')::BOOLEAN                         AS cc_chronic_kidney,
    (SP_CNCR     = '1')::BOOLEAN                         AS cc_cancer,
    (SP_COPD     = '1')::BOOLEAN                         AS cc_copd,
    (SP_DEPRESSN = '1')::BOOLEAN                         AS cc_depression,
    (SP_DIABETES = '1')::BOOLEAN                         AS cc_diabetes,
    (SP_ISCHMCHT = '1')::BOOLEAN                         AS cc_ischemic_heart,
    (SP_OSTEOPRS = '1')::BOOLEAN                         AS cc_osteoporosis,
    (SP_RA_OA    = '1')::BOOLEAN                         AS cc_ra_oa,
    (SP_STRKETIA = '1')::BOOLEAN                         AS cc_stroke_tia,
    -- Derived: count of chronic conditions (useful for patient complexity)
    ( (SP_ALZHDMTA = '1')::INT + (SP_CHF = '1')::INT +
      (SP_CHRNKIDN = '1')::INT + (SP_CNCR = '1')::INT +
      (SP_COPD = '1')::INT + (SP_DEPRESSN = '1')::INT +
      (SP_DIABETES = '1')::INT + (SP_ISCHMCHT = '1')::INT +
      (SP_OSTEOPRS = '1')::INT + (SP_RA_OA = '1')::INT +
      (SP_STRKETIA = '1')::INT
    )                                                    AS chronic_condition_count,
    -- Annual reimbursement amounts
    TRY_CAST(MEDREIMB_IP  AS NUMBER(12,2))               AS annual_ip_medicare_reimb,
    TRY_CAST(BENRES_IP    AS NUMBER(12,2))               AS annual_ip_bene_responsibility,
    TRY_CAST(MEDREIMB_OP  AS NUMBER(12,2))               AS annual_op_medicare_reimb,
    TRY_CAST(BENRES_OP    AS NUMBER(12,2))               AS annual_op_bene_responsibility,
    TRY_CAST(MEDREIMB_CAR AS NUMBER(12,2))               AS annual_car_medicare_reimb,
    TRY_CAST(BENRES_CAR   AS NUMBER(12,2))               AS annual_car_bene_responsibility,
    -- Source year derived from source file name
    CASE
        WHEN _SOURCE_FILE ILIKE '%2008%' THEN 2008
        WHEN _SOURCE_FILE ILIKE '%2009%' THEN 2009
        WHEN _SOURCE_FILE ILIKE '%2010%' THEN 2010
        ELSE NULL
    END                                                  AS summary_year
FROM RAW.STG_BENEFICIARY_SUMMARY;

-- -------------------------------------------------------
-- 2. FACT_CARRIER_CLAIMS_LINES (the critical unpivot)
--
--    The carrier claims file stores up to 13 line items per claim
--    in a wide format. We unpivot to one row per line item.
--
--    This is the most important transformation in the project:
--    it produces the line-level detail needed for provider profiling.
--
--    Strategy: UNION ALL of 13 SELECT statements, each extracting
--    line item N. Filter out lines where HCPCS_CD is NULL (empty slot).
-- -------------------------------------------------------
CREATE OR REPLACE TABLE FACT_CARRIER_CLAIM_LINES AS
WITH line_unpivot AS (
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           1 AS line_number,
           PRF_PHYSN_NPI_1      AS provider_npi,
           TAX_NUM_1            AS tax_number,
           HCPCS_CD_1           AS hcpcs_code,
           LINE_NCH_PMT_AMT_1   AS payment_amount,
           LINE_BENE_PTB_DDCTBL_AMT_1   AS deductible_amount,
           LINE_BENE_PRMRY_PYR_PD_AMT_1 AS primary_payer_paid,
           LINE_COINSRNC_AMT_1  AS coinsurance_amount,
           LINE_ALOWD_CHRG_AMT_1 AS allowed_charge_amount,
           LINE_PRCSG_IND_CD_1  AS processing_indicator,
           LINE_ICD9_DGNS_CD_1  AS line_diagnosis_code
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           2, PRF_PHYSN_NPI_2, TAX_NUM_2, HCPCS_CD_2,
           LINE_NCH_PMT_AMT_2, LINE_BENE_PTB_DDCTBL_AMT_2,
           LINE_BENE_PRMRY_PYR_PD_AMT_2, LINE_COINSRNC_AMT_2,
           LINE_ALOWD_CHRG_AMT_2, LINE_PRCSG_IND_CD_2, LINE_ICD9_DGNS_CD_2
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           3, PRF_PHYSN_NPI_3, TAX_NUM_3, HCPCS_CD_3,
           LINE_NCH_PMT_AMT_3, LINE_BENE_PTB_DDCTBL_AMT_3,
           LINE_BENE_PRMRY_PYR_PD_AMT_3, LINE_COINSRNC_AMT_3,
           LINE_ALOWD_CHRG_AMT_3, LINE_PRCSG_IND_CD_3, LINE_ICD9_DGNS_CD_3
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           4, PRF_PHYSN_NPI_4, TAX_NUM_4, HCPCS_CD_4,
           LINE_NCH_PMT_AMT_4, LINE_BENE_PTB_DDCTBL_AMT_4,
           LINE_BENE_PRMRY_PYR_PD_AMT_4, LINE_COINSRNC_AMT_4,
           LINE_ALOWD_CHRG_AMT_4, LINE_PRCSG_IND_CD_4, LINE_ICD9_DGNS_CD_4
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           5, PRF_PHYSN_NPI_5, TAX_NUM_5, HCPCS_CD_5,
           LINE_NCH_PMT_AMT_5, LINE_BENE_PTB_DDCTBL_AMT_5,
           LINE_BENE_PRMRY_PYR_PD_AMT_5, LINE_COINSRNC_AMT_5,
           LINE_ALOWD_CHRG_AMT_5, LINE_PRCSG_IND_CD_5, LINE_ICD9_DGNS_CD_5
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           6, PRF_PHYSN_NPI_6, TAX_NUM_6, HCPCS_CD_6,
           LINE_NCH_PMT_AMT_6, LINE_BENE_PTB_DDCTBL_AMT_6,
           LINE_BENE_PRMRY_PYR_PD_AMT_6, LINE_COINSRNC_AMT_6,
           LINE_ALOWD_CHRG_AMT_6, LINE_PRCSG_IND_CD_6, LINE_ICD9_DGNS_CD_6
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           7, PRF_PHYSN_NPI_7, TAX_NUM_7, HCPCS_CD_7,
           LINE_NCH_PMT_AMT_7, LINE_BENE_PTB_DDCTBL_AMT_7,
           LINE_BENE_PRMRY_PYR_PD_AMT_7, LINE_COINSRNC_AMT_7,
           LINE_ALOWD_CHRG_AMT_7, LINE_PRCSG_IND_CD_7, LINE_ICD9_DGNS_CD_7
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           8, PRF_PHYSN_NPI_8, TAX_NUM_8, HCPCS_CD_8,
           LINE_NCH_PMT_AMT_8, LINE_BENE_PTB_DDCTBL_AMT_8,
           LINE_BENE_PRMRY_PYR_PD_AMT_8, LINE_COINSRNC_AMT_8,
           LINE_ALOWD_CHRG_AMT_8, LINE_PRCSG_IND_CD_8, LINE_ICD9_DGNS_CD_8
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           9, PRF_PHYSN_NPI_9, TAX_NUM_9, HCPCS_CD_9,
           LINE_NCH_PMT_AMT_9, LINE_BENE_PTB_DDCTBL_AMT_9,
           LINE_BENE_PRMRY_PYR_PD_AMT_9, LINE_COINSRNC_AMT_9,
           LINE_ALOWD_CHRG_AMT_9, LINE_PRCSG_IND_CD_9, LINE_ICD9_DGNS_CD_9
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           10, PRF_PHYSN_NPI_10, TAX_NUM_10, HCPCS_CD_10,
           LINE_NCH_PMT_AMT_10, LINE_BENE_PTB_DDCTBL_AMT_10,
           LINE_BENE_PRMRY_PYR_PD_AMT_10, LINE_COINSRNC_AMT_10,
           LINE_ALOWD_CHRG_AMT_10, LINE_PRCSG_IND_CD_10, LINE_ICD9_DGNS_CD_10
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           11, PRF_PHYSN_NPI_11, TAX_NUM_11, HCPCS_CD_11,
           LINE_NCH_PMT_AMT_11, LINE_BENE_PTB_DDCTBL_AMT_11,
           LINE_BENE_PRMRY_PYR_PD_AMT_11, LINE_COINSRNC_AMT_11,
           LINE_ALOWD_CHRG_AMT_11, LINE_PRCSG_IND_CD_11, LINE_ICD9_DGNS_CD_11
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           12, PRF_PHYSN_NPI_12, TAX_NUM_12, HCPCS_CD_12,
           LINE_NCH_PMT_AMT_12, LINE_BENE_PTB_DDCTBL_AMT_12,
           LINE_BENE_PRMRY_PYR_PD_AMT_12, LINE_COINSRNC_AMT_12,
           LINE_ALOWD_CHRG_AMT_12, LINE_PRCSG_IND_CD_12, LINE_ICD9_DGNS_CD_12
    FROM RAW.STG_CARRIER_CLAIMS
    UNION ALL
    SELECT CLM_ID, DESYNPUF_ID, CLM_FROM_DT, CLM_THRU_DT,
           ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
           ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
           13, PRF_PHYSN_NPI_13, TAX_NUM_13, HCPCS_CD_13,
           LINE_NCH_PMT_AMT_13, LINE_BENE_PTB_DDCTBL_AMT_13,
           LINE_BENE_PRMRY_PYR_PD_AMT_13, LINE_COINSRNC_AMT_13,
           LINE_ALOWD_CHRG_AMT_13, LINE_PRCSG_IND_CD_13, LINE_ICD9_DGNS_CD_13
    FROM RAW.STG_CARRIER_CLAIMS
)
SELECT
    CLM_ID,
    DESYNPUF_ID                                          AS beneficiary_id,
    TRY_TO_DATE(CLM_FROM_DT, 'YYYYMMDD')                AS service_from_date,
    TRY_TO_DATE(CLM_THRU_DT, 'YYYYMMDD')                AS service_thru_date,
    'CARRIER'                                            AS claim_type,
    line_number,
    provider_npi,
    tax_number,
    hcpcs_code,
    TRY_CAST(payment_amount       AS NUMBER(12,2))       AS payment_amount,
    TRY_CAST(deductible_amount    AS NUMBER(12,2))       AS deductible_amount,
    TRY_CAST(primary_payer_paid   AS NUMBER(12,2))       AS primary_payer_paid,
    TRY_CAST(coinsurance_amount   AS NUMBER(12,2))       AS coinsurance_amount,
    TRY_CAST(allowed_charge_amount AS NUMBER(12,2))      AS allowed_charge_amount,
    processing_indicator,
    line_diagnosis_code,
    -- Carry forward claim-level diagnosis codes for downstream analysis
    ICD9_DGNS_CD_1 AS clm_dgns_cd_1,
    ICD9_DGNS_CD_2 AS clm_dgns_cd_2,
    ICD9_DGNS_CD_3 AS clm_dgns_cd_3,
    ICD9_DGNS_CD_4 AS clm_dgns_cd_4,
    ICD9_DGNS_CD_5 AS clm_dgns_cd_5,
    ICD9_DGNS_CD_6 AS clm_dgns_cd_6,
    ICD9_DGNS_CD_7 AS clm_dgns_cd_7,
    ICD9_DGNS_CD_8 AS clm_dgns_cd_8
FROM line_unpivot
WHERE hcpcs_code IS NOT NULL;  -- Filter out empty line item slots

-- -------------------------------------------------------
-- 3. DIM_PROVIDER (derived from carrier claim lines)
--
--    Since DE-SynPUF has no specialty field, we derive it from
--    the most frequent HCPCS code billed by each provider.
--    This is a proxy — documented as a limitation.
-- -------------------------------------------------------
CREATE OR REPLACE TABLE DIM_PROVIDER AS
WITH provider_hcpcs_freq AS (
    SELECT
        provider_npi,
        hcpcs_code,
        COUNT(*) AS line_count,
        ROW_NUMBER() OVER (
            PARTITION BY provider_npi
            ORDER BY COUNT(*) DESC
        ) AS rn
    FROM FACT_CARRIER_CLAIM_LINES
    WHERE provider_npi IS NOT NULL
    GROUP BY provider_npi, hcpcs_code
),
provider_top_hcpcs AS (
    SELECT provider_npi, hcpcs_code AS top_hcpcs_code
    FROM provider_hcpcs_freq
    WHERE rn = 1
),
provider_stats AS (
    SELECT
        f.provider_npi,
        COUNT(*)                          AS total_claim_lines,
        COUNT(DISTINCT f.CLM_ID)          AS total_claims,
        COUNT(DISTINCT f.beneficiary_id)  AS distinct_beneficiaries,
        SUM(f.payment_amount)             AS total_paid,
        SUM(f.allowed_charge_amount)      AS total_allowed_charges,
        MIN(f.service_from_date)          AS first_service_date,
        MAX(f.service_from_date)          AS last_service_date,
        COUNT(DISTINCT f.hcpcs_code)      AS distinct_hcpcs_codes
    FROM FACT_CARRIER_CLAIM_LINES f
    WHERE f.provider_npi IS NOT NULL
    GROUP BY f.provider_npi
)
SELECT
    s.provider_npi,
    h.top_hcpcs_code,
    -- Derived specialty based on HCPCS code ranges (simplified BETOS-like mapping)
    -- NOTE: This is a proxy. In production, NPPES taxonomy would be used.
    CASE
        WHEN h.top_hcpcs_code BETWEEN '99201' AND '99499' THEN 'Evaluation & Management'
        WHEN h.top_hcpcs_code BETWEEN '10021' AND '69990' THEN 'Surgery'
        WHEN h.top_hcpcs_code BETWEEN '70010' AND '79999' THEN 'Radiology'
        WHEN h.top_hcpcs_code BETWEEN '80047' AND '89398' THEN 'Pathology & Lab'
        WHEN h.top_hcpcs_code BETWEEN '90281' AND '99199' THEN 'Medicine'
        WHEN h.top_hcpcs_code BETWEEN '00100' AND '01999' THEN 'Anesthesiology'
        WHEN h.top_hcpcs_code LIKE 'A%' OR h.top_hcpcs_code LIKE 'B%'
             OR h.top_hcpcs_code LIKE 'C%' OR h.top_hcpcs_code LIKE 'E%'
             OR h.top_hcpcs_code LIKE 'J%' OR h.top_hcpcs_code LIKE 'L%' THEN 'HCPCS Level II'
        ELSE 'Other'
    END                                   AS derived_specialty,
    s.total_claim_lines,
    s.total_claims,
    s.distinct_beneficiaries,
    s.total_paid,
    s.total_allowed_charges,
    s.first_service_date,
    s.last_service_date,
    s.distinct_hcpcs_codes
FROM provider_stats s
JOIN provider_top_hcpcs h ON s.provider_npi = h.provider_npi;

-- -------------------------------------------------------
-- Verification queries
-- -------------------------------------------------------

-- Unpivot result: how many claim lines vs original claim rows?
SELECT
    'FACT_CARRIER_CLAIM_LINES' AS table_name,
    COUNT(*)                   AS total_lines,
    COUNT(DISTINCT CLM_ID)     AS distinct_claims,
    COUNT(DISTINCT provider_npi) AS distinct_providers,
    COUNT(DISTINCT beneficiary_id) AS distinct_beneficiaries,
    SUM(payment_amount)        AS total_payment,
    SUM(allowed_charge_amount) AS total_allowed_charges
FROM FACT_CARRIER_CLAIM_LINES;

-- Provider dimension summary
SELECT
    derived_specialty,
    COUNT(*)                   AS provider_count,
    SUM(total_claim_lines)     AS total_lines,
    ROUND(AVG(total_paid), 2)  AS avg_total_paid,
    ROUND(AVG(distinct_beneficiaries), 1) AS avg_distinct_benes
FROM DIM_PROVIDER
GROUP BY derived_specialty
ORDER BY provider_count DESC;

-- Beneficiary dimension summary
SELECT
    summary_year,
    COUNT(*)                               AS total_rows,
    COUNT(DISTINCT DESYNPUF_ID)            AS distinct_beneficiaries,
    ROUND(AVG(age_at_end), 1)              AS avg_age,
    ROUND(AVG(chronic_condition_count), 2) AS avg_chronic_conditions,
    SUM(CASE WHEN is_deceased THEN 1 ELSE 0 END) AS deceased_count
FROM DIM_BENEFICIARY
GROUP BY summary_year
ORDER BY summary_year;
