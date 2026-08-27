-- =============================================================================
-- P3 — Provider Aberrant Billing Pattern Detection
-- 01_create_raw_schema.sql
--
-- Purpose : Create raw staging tables in the RAW schema.
--           All columns are VARCHAR — this is a landing zone pattern.
--           Type casting happens in the ANALYTICS schema transformation.
--
-- Source  : CMS DE-SynPUF Codebook (de-10-codebook.pdf)
--           Column names match the CSV headers exactly.
--
-- Design decision: VARCHAR landing zone
--   Rationale: DE-SynPUF CSVs contain edge cases (empty strings for nulls,
--   mixed-type columns where procedure codes may appear in diagnosis fields).
--   Loading everything as VARCHAR first avoids COPY INTO failures and lets
--   us handle type issues explicitly in the transformation step.
-- =============================================================================

USE DATABASE MEDICARE_FWA;
USE SCHEMA RAW;

-- -------------------------------------------------------
-- 1. Beneficiary Summary (32 columns)
--    One row per beneficiary per year (2008, 2009, 2010)
--    Source files: DE1_0_2008_Beneficiary_Summary_File_Sample_*.csv
--                  DE1_0_2009_Beneficiary_Summary_File_Sample_*.csv
--                  DE1_0_2010_Beneficiary_Summary_File_Sample_*.csv
-- -------------------------------------------------------
CREATE OR REPLACE TABLE STG_BENEFICIARY_SUMMARY (
    DESYNPUF_ID                    VARCHAR,
    BENE_BIRTH_DT                  VARCHAR,
    BENE_DEATH_DT                  VARCHAR,
    BENE_SEX_IDENT_CD              VARCHAR,
    BENE_RACE_CD                   VARCHAR,
    BENE_ESRD_IND                  VARCHAR,
    SP_STATE_CODE                  VARCHAR,
    BENE_COUNTY_CD                 VARCHAR,
    BENE_HI_CVRAGE_TOT_MONS       VARCHAR,
    BENE_SMI_CVRAGE_TOT_MONS      VARCHAR,
    BENE_HMO_CVRAGE_TOT_MONS      VARCHAR,
    PLAN_CVRG_MOS_NUM              VARCHAR,
    SP_ALZHDMTA                    VARCHAR,
    SP_CHF                         VARCHAR,
    SP_CHRNKIDN                    VARCHAR,
    SP_CNCR                        VARCHAR,
    SP_COPD                        VARCHAR,
    SP_DEPRESSN                    VARCHAR,
    SP_DIABETES                    VARCHAR,
    SP_ISCHMCHT                    VARCHAR,
    SP_OSTEOPRS                    VARCHAR,
    SP_RA_OA                       VARCHAR,
    SP_STRKETIA                    VARCHAR,
    MEDREIMB_IP                    VARCHAR,
    BENRES_IP                      VARCHAR,
    PPPYMT_IP                      VARCHAR,
    MEDREIMB_OP                    VARCHAR,
    BENRES_OP                      VARCHAR,
    PPPYMT_OP                      VARCHAR,
    MEDREIMB_CAR                   VARCHAR,
    BENRES_CAR                     VARCHAR,
    PPPYMT_CAR                     VARCHAR,
    -- Metadata columns added at load time
    _SOURCE_FILE                   VARCHAR,
    _LOAD_TIMESTAMP                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------------------------------------
-- 2. Inpatient Claims (81 columns)
--    One row per inpatient claim (may have up to 2 segments)
--    Source files: DE1_0_2008_to_2010_Inpatient_Claims_Sample_*.csv
-- -------------------------------------------------------
CREATE OR REPLACE TABLE STG_INPATIENT_CLAIMS (
    DESYNPUF_ID                    VARCHAR,
    CLM_ID                         VARCHAR,
    SEGMENT                        VARCHAR,
    CLM_FROM_DT                    VARCHAR,
    CLM_THRU_DT                    VARCHAR,
    PRVDR_NUM                      VARCHAR,
    CLM_PMT_AMT                    VARCHAR,
    NCH_PRMRY_PYR_CLM_PD_AMT      VARCHAR,
    AT_PHYSN_NPI                   VARCHAR,
    OP_PHYSN_NPI                   VARCHAR,
    OT_PHYSN_NPI                   VARCHAR,
    CLM_ADMSN_DT                   VARCHAR,
    ADMTNG_ICD9_DGNS_CD            VARCHAR,
    CLM_PASS_THRU_PER_DIEM_AMT     VARCHAR,
    NCH_BENE_IP_DDCTBL_AMT         VARCHAR,
    NCH_BENE_PTA_COINSRNC_LBLTY_AM VARCHAR,
    NCH_BENE_BLOOD_DDCTBL_LBLTY_AM VARCHAR,
    CLM_UTLZTN_DAY_CNT             VARCHAR,
    NCH_BENE_DSCHRG_DT             VARCHAR,
    CLM_DRG_CD                     VARCHAR,
    -- Diagnosis codes 1-10
    ICD9_DGNS_CD_1                 VARCHAR,
    ICD9_DGNS_CD_2                 VARCHAR,
    ICD9_DGNS_CD_3                 VARCHAR,
    ICD9_DGNS_CD_4                 VARCHAR,
    ICD9_DGNS_CD_5                 VARCHAR,
    ICD9_DGNS_CD_6                 VARCHAR,
    ICD9_DGNS_CD_7                 VARCHAR,
    ICD9_DGNS_CD_8                 VARCHAR,
    ICD9_DGNS_CD_9                 VARCHAR,
    ICD9_DGNS_CD_10                VARCHAR,
    -- Procedure codes 1-6
    ICD9_PRCDR_CD_1                VARCHAR,
    ICD9_PRCDR_CD_2                VARCHAR,
    ICD9_PRCDR_CD_3                VARCHAR,
    ICD9_PRCDR_CD_4                VARCHAR,
    ICD9_PRCDR_CD_5                VARCHAR,
    ICD9_PRCDR_CD_6                VARCHAR,
    -- HCPCS codes 1-45 (mostly empty for inpatient — DRG-based payment)
    HCPCS_CD_1  VARCHAR, HCPCS_CD_2  VARCHAR, HCPCS_CD_3  VARCHAR,
    HCPCS_CD_4  VARCHAR, HCPCS_CD_5  VARCHAR, HCPCS_CD_6  VARCHAR,
    HCPCS_CD_7  VARCHAR, HCPCS_CD_8  VARCHAR, HCPCS_CD_9  VARCHAR,
    HCPCS_CD_10 VARCHAR, HCPCS_CD_11 VARCHAR, HCPCS_CD_12 VARCHAR,
    HCPCS_CD_13 VARCHAR, HCPCS_CD_14 VARCHAR, HCPCS_CD_15 VARCHAR,
    HCPCS_CD_16 VARCHAR, HCPCS_CD_17 VARCHAR, HCPCS_CD_18 VARCHAR,
    HCPCS_CD_19 VARCHAR, HCPCS_CD_20 VARCHAR, HCPCS_CD_21 VARCHAR,
    HCPCS_CD_22 VARCHAR, HCPCS_CD_23 VARCHAR, HCPCS_CD_24 VARCHAR,
    HCPCS_CD_25 VARCHAR, HCPCS_CD_26 VARCHAR, HCPCS_CD_27 VARCHAR,
    HCPCS_CD_28 VARCHAR, HCPCS_CD_29 VARCHAR, HCPCS_CD_30 VARCHAR,
    HCPCS_CD_31 VARCHAR, HCPCS_CD_32 VARCHAR, HCPCS_CD_33 VARCHAR,
    HCPCS_CD_34 VARCHAR, HCPCS_CD_35 VARCHAR, HCPCS_CD_36 VARCHAR,
    HCPCS_CD_37 VARCHAR, HCPCS_CD_38 VARCHAR, HCPCS_CD_39 VARCHAR,
    HCPCS_CD_40 VARCHAR, HCPCS_CD_41 VARCHAR, HCPCS_CD_42 VARCHAR,
    HCPCS_CD_43 VARCHAR, HCPCS_CD_44 VARCHAR, HCPCS_CD_45 VARCHAR,
    -- Metadata
    _SOURCE_FILE                   VARCHAR,
    _LOAD_TIMESTAMP                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------------------------------------
-- 3. Outpatient Claims (76 columns)
--    One row per outpatient claim
--    Source files: DE1_0_2008_to_2010_Outpatient_Claims_Sample_*.csv
-- -------------------------------------------------------
CREATE OR REPLACE TABLE STG_OUTPATIENT_CLAIMS (
    DESYNPUF_ID                    VARCHAR,
    CLM_ID                         VARCHAR,
    SEGMENT                        VARCHAR,
    CLM_FROM_DT                    VARCHAR,
    CLM_THRU_DT                    VARCHAR,
    PRVDR_NUM                      VARCHAR,
    CLM_PMT_AMT                    VARCHAR,
    NCH_PRMRY_PYR_CLM_PD_AMT      VARCHAR,
    AT_PHYSN_NPI                   VARCHAR,
    OP_PHYSN_NPI                   VARCHAR,
    OT_PHYSN_NPI                   VARCHAR,
    NCH_BENE_BLOOD_DDCTBL_LBLTY_AM VARCHAR,
    -- Diagnosis codes 1-10
    ICD9_DGNS_CD_1                 VARCHAR,
    ICD9_DGNS_CD_2                 VARCHAR,
    ICD9_DGNS_CD_3                 VARCHAR,
    ICD9_DGNS_CD_4                 VARCHAR,
    ICD9_DGNS_CD_5                 VARCHAR,
    ICD9_DGNS_CD_6                 VARCHAR,
    ICD9_DGNS_CD_7                 VARCHAR,
    ICD9_DGNS_CD_8                 VARCHAR,
    ICD9_DGNS_CD_9                 VARCHAR,
    ICD9_DGNS_CD_10                VARCHAR,
    -- Procedure codes 1-6
    ICD9_PRCDR_CD_1                VARCHAR,
    ICD9_PRCDR_CD_2                VARCHAR,
    ICD9_PRCDR_CD_3                VARCHAR,
    ICD9_PRCDR_CD_4                VARCHAR,
    ICD9_PRCDR_CD_5                VARCHAR,
    ICD9_PRCDR_CD_6                VARCHAR,
    -- Part B cost sharing
    NCH_BENE_PTB_DDCTBL_AMT        VARCHAR,
    NCH_BENE_PTB_COINSRNC_AMT      VARCHAR,
    ADMTNG_ICD9_DGNS_CD            VARCHAR,
    -- HCPCS codes 1-45
    HCPCS_CD_1  VARCHAR, HCPCS_CD_2  VARCHAR, HCPCS_CD_3  VARCHAR,
    HCPCS_CD_4  VARCHAR, HCPCS_CD_5  VARCHAR, HCPCS_CD_6  VARCHAR,
    HCPCS_CD_7  VARCHAR, HCPCS_CD_8  VARCHAR, HCPCS_CD_9  VARCHAR,
    HCPCS_CD_10 VARCHAR, HCPCS_CD_11 VARCHAR, HCPCS_CD_12 VARCHAR,
    HCPCS_CD_13 VARCHAR, HCPCS_CD_14 VARCHAR, HCPCS_CD_15 VARCHAR,
    HCPCS_CD_16 VARCHAR, HCPCS_CD_17 VARCHAR, HCPCS_CD_18 VARCHAR,
    HCPCS_CD_19 VARCHAR, HCPCS_CD_20 VARCHAR, HCPCS_CD_21 VARCHAR,
    HCPCS_CD_22 VARCHAR, HCPCS_CD_23 VARCHAR, HCPCS_CD_24 VARCHAR,
    HCPCS_CD_25 VARCHAR, HCPCS_CD_26 VARCHAR, HCPCS_CD_27 VARCHAR,
    HCPCS_CD_28 VARCHAR, HCPCS_CD_29 VARCHAR, HCPCS_CD_30 VARCHAR,
    HCPCS_CD_31 VARCHAR, HCPCS_CD_32 VARCHAR, HCPCS_CD_33 VARCHAR,
    HCPCS_CD_34 VARCHAR, HCPCS_CD_35 VARCHAR, HCPCS_CD_36 VARCHAR,
    HCPCS_CD_37 VARCHAR, HCPCS_CD_38 VARCHAR, HCPCS_CD_39 VARCHAR,
    HCPCS_CD_40 VARCHAR, HCPCS_CD_41 VARCHAR, HCPCS_CD_42 VARCHAR,
    HCPCS_CD_43 VARCHAR, HCPCS_CD_44 VARCHAR, HCPCS_CD_45 VARCHAR,
    -- Metadata
    _SOURCE_FILE                   VARCHAR,
    _LOAD_TIMESTAMP                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------------------------------------
-- 4. Carrier Claims (142 columns)
--    Wide format: up to 13 line items per claim row
--    This is the CORE table for P3 — physician/supplier claims
--    Source files: DE1_0_2008_to_2010_Carrier_Claims_Sample_*a.csv
--                  DE1_0_2008_to_2010_Carrier_Claims_Sample_*b.csv
--
--    CRITICAL: Each sample is split into segment A and B files.
--    Both must be loaded.
-- -------------------------------------------------------
CREATE OR REPLACE TABLE STG_CARRIER_CLAIMS (
    DESYNPUF_ID                    VARCHAR,
    CLM_ID                         VARCHAR,
    CLM_FROM_DT                    VARCHAR,
    CLM_THRU_DT                    VARCHAR,
    -- Claim-level diagnosis codes 1-8
    ICD9_DGNS_CD_1                 VARCHAR,
    ICD9_DGNS_CD_2                 VARCHAR,
    ICD9_DGNS_CD_3                 VARCHAR,
    ICD9_DGNS_CD_4                 VARCHAR,
    ICD9_DGNS_CD_5                 VARCHAR,
    ICD9_DGNS_CD_6                 VARCHAR,
    ICD9_DGNS_CD_7                 VARCHAR,
    ICD9_DGNS_CD_8                 VARCHAR,
    -- Line-level: Performing Physician NPI (1-13)
    PRF_PHYSN_NPI_1  VARCHAR, PRF_PHYSN_NPI_2  VARCHAR, PRF_PHYSN_NPI_3  VARCHAR,
    PRF_PHYSN_NPI_4  VARCHAR, PRF_PHYSN_NPI_5  VARCHAR, PRF_PHYSN_NPI_6  VARCHAR,
    PRF_PHYSN_NPI_7  VARCHAR, PRF_PHYSN_NPI_8  VARCHAR, PRF_PHYSN_NPI_9  VARCHAR,
    PRF_PHYSN_NPI_10 VARCHAR, PRF_PHYSN_NPI_11 VARCHAR, PRF_PHYSN_NPI_12 VARCHAR,
    PRF_PHYSN_NPI_13 VARCHAR,
    -- Line-level: Tax Number (1-13)
    TAX_NUM_1  VARCHAR, TAX_NUM_2  VARCHAR, TAX_NUM_3  VARCHAR,
    TAX_NUM_4  VARCHAR, TAX_NUM_5  VARCHAR, TAX_NUM_6  VARCHAR,
    TAX_NUM_7  VARCHAR, TAX_NUM_8  VARCHAR, TAX_NUM_9  VARCHAR,
    TAX_NUM_10 VARCHAR, TAX_NUM_11 VARCHAR, TAX_NUM_12 VARCHAR,
    TAX_NUM_13 VARCHAR,
    -- Line-level: HCPCS code (1-13)
    HCPCS_CD_1  VARCHAR, HCPCS_CD_2  VARCHAR, HCPCS_CD_3  VARCHAR,
    HCPCS_CD_4  VARCHAR, HCPCS_CD_5  VARCHAR, HCPCS_CD_6  VARCHAR,
    HCPCS_CD_7  VARCHAR, HCPCS_CD_8  VARCHAR, HCPCS_CD_9  VARCHAR,
    HCPCS_CD_10 VARCHAR, HCPCS_CD_11 VARCHAR, HCPCS_CD_12 VARCHAR,
    HCPCS_CD_13 VARCHAR,
    -- Line-level: Payment amount (1-13)
    LINE_NCH_PMT_AMT_1  VARCHAR, LINE_NCH_PMT_AMT_2  VARCHAR, LINE_NCH_PMT_AMT_3  VARCHAR,
    LINE_NCH_PMT_AMT_4  VARCHAR, LINE_NCH_PMT_AMT_5  VARCHAR, LINE_NCH_PMT_AMT_6  VARCHAR,
    LINE_NCH_PMT_AMT_7  VARCHAR, LINE_NCH_PMT_AMT_8  VARCHAR, LINE_NCH_PMT_AMT_9  VARCHAR,
    LINE_NCH_PMT_AMT_10 VARCHAR, LINE_NCH_PMT_AMT_11 VARCHAR, LINE_NCH_PMT_AMT_12 VARCHAR,
    LINE_NCH_PMT_AMT_13 VARCHAR,
    -- Line-level: Part B Deductible (1-13)
    LINE_BENE_PTB_DDCTBL_AMT_1  VARCHAR, LINE_BENE_PTB_DDCTBL_AMT_2  VARCHAR,
    LINE_BENE_PTB_DDCTBL_AMT_3  VARCHAR, LINE_BENE_PTB_DDCTBL_AMT_4  VARCHAR,
    LINE_BENE_PTB_DDCTBL_AMT_5  VARCHAR, LINE_BENE_PTB_DDCTBL_AMT_6  VARCHAR,
    LINE_BENE_PTB_DDCTBL_AMT_7  VARCHAR, LINE_BENE_PTB_DDCTBL_AMT_8  VARCHAR,
    LINE_BENE_PTB_DDCTBL_AMT_9  VARCHAR, LINE_BENE_PTB_DDCTBL_AMT_10 VARCHAR,
    LINE_BENE_PTB_DDCTBL_AMT_11 VARCHAR, LINE_BENE_PTB_DDCTBL_AMT_12 VARCHAR,
    LINE_BENE_PTB_DDCTBL_AMT_13 VARCHAR,
    -- Line-level: Primary Payer Paid (1-13)
    LINE_BENE_PRMRY_PYR_PD_AMT_1  VARCHAR, LINE_BENE_PRMRY_PYR_PD_AMT_2  VARCHAR,
    LINE_BENE_PRMRY_PYR_PD_AMT_3  VARCHAR, LINE_BENE_PRMRY_PYR_PD_AMT_4  VARCHAR,
    LINE_BENE_PRMRY_PYR_PD_AMT_5  VARCHAR, LINE_BENE_PRMRY_PYR_PD_AMT_6  VARCHAR,
    LINE_BENE_PRMRY_PYR_PD_AMT_7  VARCHAR, LINE_BENE_PRMRY_PYR_PD_AMT_8  VARCHAR,
    LINE_BENE_PRMRY_PYR_PD_AMT_9  VARCHAR, LINE_BENE_PRMRY_PYR_PD_AMT_10 VARCHAR,
    LINE_BENE_PRMRY_PYR_PD_AMT_11 VARCHAR, LINE_BENE_PRMRY_PYR_PD_AMT_12 VARCHAR,
    LINE_BENE_PRMRY_PYR_PD_AMT_13 VARCHAR,
    -- Line-level: Coinsurance (1-13)
    LINE_COINSRNC_AMT_1  VARCHAR, LINE_COINSRNC_AMT_2  VARCHAR,
    LINE_COINSRNC_AMT_3  VARCHAR, LINE_COINSRNC_AMT_4  VARCHAR,
    LINE_COINSRNC_AMT_5  VARCHAR, LINE_COINSRNC_AMT_6  VARCHAR,
    LINE_COINSRNC_AMT_7  VARCHAR, LINE_COINSRNC_AMT_8  VARCHAR,
    LINE_COINSRNC_AMT_9  VARCHAR, LINE_COINSRNC_AMT_10 VARCHAR,
    LINE_COINSRNC_AMT_11 VARCHAR, LINE_COINSRNC_AMT_12 VARCHAR,
    LINE_COINSRNC_AMT_13 VARCHAR,
    -- Line-level: Allowed Charge (1-13)
    LINE_ALOWD_CHRG_AMT_1  VARCHAR, LINE_ALOWD_CHRG_AMT_2  VARCHAR,
    LINE_ALOWD_CHRG_AMT_3  VARCHAR, LINE_ALOWD_CHRG_AMT_4  VARCHAR,
    LINE_ALOWD_CHRG_AMT_5  VARCHAR, LINE_ALOWD_CHRG_AMT_6  VARCHAR,
    LINE_ALOWD_CHRG_AMT_7  VARCHAR, LINE_ALOWD_CHRG_AMT_8  VARCHAR,
    LINE_ALOWD_CHRG_AMT_9  VARCHAR, LINE_ALOWD_CHRG_AMT_10 VARCHAR,
    LINE_ALOWD_CHRG_AMT_11 VARCHAR, LINE_ALOWD_CHRG_AMT_12 VARCHAR,
    LINE_ALOWD_CHRG_AMT_13 VARCHAR,
    -- Line-level: Processing Indicator Code (1-13)
    LINE_PRCSG_IND_CD_1  VARCHAR, LINE_PRCSG_IND_CD_2  VARCHAR,
    LINE_PRCSG_IND_CD_3  VARCHAR, LINE_PRCSG_IND_CD_4  VARCHAR,
    LINE_PRCSG_IND_CD_5  VARCHAR, LINE_PRCSG_IND_CD_6  VARCHAR,
    LINE_PRCSG_IND_CD_7  VARCHAR, LINE_PRCSG_IND_CD_8  VARCHAR,
    LINE_PRCSG_IND_CD_9  VARCHAR, LINE_PRCSG_IND_CD_10 VARCHAR,
    LINE_PRCSG_IND_CD_11 VARCHAR, LINE_PRCSG_IND_CD_12 VARCHAR,
    LINE_PRCSG_IND_CD_13 VARCHAR,
    -- Line-level: Line Diagnosis Code (1-13)
    LINE_ICD9_DGNS_CD_1  VARCHAR, LINE_ICD9_DGNS_CD_2  VARCHAR,
    LINE_ICD9_DGNS_CD_3  VARCHAR, LINE_ICD9_DGNS_CD_4  VARCHAR,
    LINE_ICD9_DGNS_CD_5  VARCHAR, LINE_ICD9_DGNS_CD_6  VARCHAR,
    LINE_ICD9_DGNS_CD_7  VARCHAR, LINE_ICD9_DGNS_CD_8  VARCHAR,
    LINE_ICD9_DGNS_CD_9  VARCHAR, LINE_ICD9_DGNS_CD_10 VARCHAR,
    LINE_ICD9_DGNS_CD_11 VARCHAR, LINE_ICD9_DGNS_CD_12 VARCHAR,
    LINE_ICD9_DGNS_CD_13 VARCHAR,
    -- Metadata
    _SOURCE_FILE                   VARCHAR,
    _LOAD_TIMESTAMP                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------------------------------------
-- 5. Prescription Drug Events (8 columns)
--    Source files: DE1_0_2008_to_2010_Prescription_Drug_Events_Sample_*.csv
-- -------------------------------------------------------
CREATE OR REPLACE TABLE STG_PDE (
    DESYNPUF_ID                    VARCHAR,
    PDE_ID                         VARCHAR,
    SRVC_DT                        VARCHAR,
    PROD_SRVC_ID                   VARCHAR,
    QTY_DSPNSD_NUM                 VARCHAR,
    DAYS_SUPLY_NUM                 VARCHAR,
    PTNT_PAY_AMT                   VARCHAR,
    TOT_RX_CST_AMT                VARCHAR,
    -- Metadata
    _SOURCE_FILE                   VARCHAR,
    _LOAD_TIMESTAMP                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- -------------------------------------------------------
-- Verify table creation
-- -------------------------------------------------------
SELECT TABLE_NAME, COLUMN_COUNT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
ORDER BY TABLE_NAME;
