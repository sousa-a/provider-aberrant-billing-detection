-- =============================================================================
-- P3 — Provider Aberrant Billing Pattern Detection
-- 02_copy_into_staging.sql
--
-- Purpose : Load DE-SynPUF CSV files from the internal stage into RAW tables.
--
-- HOW TO UPLOAD FILES TO THE STAGE:
--
--   Option A — Snowsight UI (easiest, recommended for first time):
--     1. Go to Data → Databases → MEDICARE_FWA → RAW → Stages → DESYNPUF_STAGE
--     2. Click "+ Files" button
--     3. Drag and drop CSV files (max 50MB per file in UI)
--     4. For files > 50MB, use Option B
--
--   Option B — SnowSQL CLI:
--     $ snowsql -a <account_id> -u <username>
--     PUT file:///path/to/DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv
--         @MEDICARE_FWA.RAW.DESYNPUF_STAGE/beneficiary/ AUTO_COMPRESS=TRUE;
--
--   Option C — Python snowflake-connector:
--     cursor.execute("PUT file:///path/to/file.csv @DESYNPUF_STAGE/beneficiary/")
--
-- FILE ORGANIZATION ON STAGE (recommended subdirectories):
--   @DESYNPUF_STAGE/beneficiary/   — all beneficiary summary CSVs
--   @DESYNPUF_STAGE/inpatient/     — all inpatient claims CSVs
--   @DESYNPUF_STAGE/outpatient/    — all outpatient claims CSVs
--   @DESYNPUF_STAGE/carrier/       — all carrier claims CSVs (both A and B segments)
--   @DESYNPUF_STAGE/pde/           — all prescription drug event CSVs
--
-- SAMPLE DECISION:
--   Start with Sample 1 only (~116K beneficiaries, ~5% of Medicare).
--   If peer groups are too small, add Samples 2-5 by repeating the PUT/COPY
--   commands for additional files. Document the decision in the README.
-- =============================================================================

USE DATABASE MEDICARE_FWA;
USE SCHEMA RAW;
USE WAREHOUSE FWA_WH;

-- -------------------------------------------------------
-- 1. Load Beneficiary Summary files
--    3 files per sample: 2008, 2009, 2010
-- -------------------------------------------------------
COPY INTO STG_BENEFICIARY_SUMMARY (
    DESYNPUF_ID, BENE_BIRTH_DT, BENE_DEATH_DT, BENE_SEX_IDENT_CD,
    BENE_RACE_CD, BENE_ESRD_IND, SP_STATE_CODE, BENE_COUNTY_CD,
    BENE_HI_CVRAGE_TOT_MONS, BENE_SMI_CVRAGE_TOT_MONS,
    BENE_HMO_CVRAGE_TOT_MONS, PLAN_CVRG_MOS_NUM,
    SP_ALZHDMTA, SP_CHF, SP_CHRNKIDN, SP_CNCR, SP_COPD,
    SP_DEPRESSN, SP_DIABETES, SP_ISCHMCHT, SP_OSTEOPRS,
    SP_RA_OA, SP_STRKETIA,
    MEDREIMB_IP, BENRES_IP, PPPYMT_IP,
    MEDREIMB_OP, BENRES_OP, PPPYMT_OP,
    MEDREIMB_CAR, BENRES_CAR, PPPYMT_CAR,
    _SOURCE_FILE
)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
        $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
        $31, $32,
        METADATA$FILENAME
    FROM @DESYNPUF_STAGE/beneficiary/
)
FILE_FORMAT = CSV_DESYNPUF
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- Verify load
SELECT
    'STG_BENEFICIARY_SUMMARY' AS table_name,
    COUNT(*)                  AS total_rows,
    COUNT(DISTINCT DESYNPUF_ID) AS distinct_beneficiaries,
    COUNT(DISTINCT _SOURCE_FILE) AS files_loaded
FROM STG_BENEFICIARY_SUMMARY;

-- -------------------------------------------------------
-- 2. Load Inpatient Claims
-- -------------------------------------------------------
COPY INTO STG_INPATIENT_CLAIMS (
    DESYNPUF_ID, CLM_ID, SEGMENT, CLM_FROM_DT, CLM_THRU_DT,
    PRVDR_NUM, CLM_PMT_AMT, NCH_PRMRY_PYR_CLM_PD_AMT,
    AT_PHYSN_NPI, OP_PHYSN_NPI, OT_PHYSN_NPI,
    CLM_ADMSN_DT, ADMTNG_ICD9_DGNS_CD,
    CLM_PASS_THRU_PER_DIEM_AMT, NCH_BENE_IP_DDCTBL_AMT,
    NCH_BENE_PTA_COINSRNC_LBLTY_AM, NCH_BENE_BLOOD_DDCTBL_LBLTY_AM,
    CLM_UTLZTN_DAY_CNT, NCH_BENE_DSCHRG_DT, CLM_DRG_CD,
    ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
    ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
    ICD9_DGNS_CD_9, ICD9_DGNS_CD_10,
    ICD9_PRCDR_CD_1, ICD9_PRCDR_CD_2, ICD9_PRCDR_CD_3,
    ICD9_PRCDR_CD_4, ICD9_PRCDR_CD_5, ICD9_PRCDR_CD_6,
    HCPCS_CD_1,  HCPCS_CD_2,  HCPCS_CD_3,  HCPCS_CD_4,  HCPCS_CD_5,
    HCPCS_CD_6,  HCPCS_CD_7,  HCPCS_CD_8,  HCPCS_CD_9,  HCPCS_CD_10,
    HCPCS_CD_11, HCPCS_CD_12, HCPCS_CD_13, HCPCS_CD_14, HCPCS_CD_15,
    HCPCS_CD_16, HCPCS_CD_17, HCPCS_CD_18, HCPCS_CD_19, HCPCS_CD_20,
    HCPCS_CD_21, HCPCS_CD_22, HCPCS_CD_23, HCPCS_CD_24, HCPCS_CD_25,
    HCPCS_CD_26, HCPCS_CD_27, HCPCS_CD_28, HCPCS_CD_29, HCPCS_CD_30,
    HCPCS_CD_31, HCPCS_CD_32, HCPCS_CD_33, HCPCS_CD_34, HCPCS_CD_35,
    HCPCS_CD_36, HCPCS_CD_37, HCPCS_CD_38, HCPCS_CD_39, HCPCS_CD_40,
    HCPCS_CD_41, HCPCS_CD_42, HCPCS_CD_43, HCPCS_CD_44, HCPCS_CD_45,
    _SOURCE_FILE
)
FROM (
    SELECT
        $1,  $2,  $3,  $4,  $5,  $6,  $7,  $8,  $9,  $10,
        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
        $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
        $31, $32, $33, $34, $35, $36,
        $37, $38, $39, $40, $41, $42, $43, $44, $45, $46,
        $47, $48, $49, $50, $51, $52, $53, $54, $55, $56,
        $57, $58, $59, $60, $61, $62, $63, $64, $65, $66,
        $67, $68, $69, $70, $71, $72, $73, $74, $75, $76,
        $77, $78, $79, $80, $81,
        METADATA$FILENAME
    FROM @DESYNPUF_STAGE/inpatient/
)
FILE_FORMAT = CSV_DESYNPUF
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- Verify load
SELECT
    'STG_INPATIENT_CLAIMS' AS table_name,
    COUNT(*)               AS total_rows,
    COUNT(DISTINCT CLM_ID) AS distinct_claims,
    COUNT(DISTINCT DESYNPUF_ID) AS distinct_beneficiaries
FROM STG_INPATIENT_CLAIMS;

-- -------------------------------------------------------
-- 3. Load Outpatient Claims
-- -------------------------------------------------------
COPY INTO STG_OUTPATIENT_CLAIMS (
    DESYNPUF_ID, CLM_ID, SEGMENT, CLM_FROM_DT, CLM_THRU_DT,
    PRVDR_NUM, CLM_PMT_AMT, NCH_PRMRY_PYR_CLM_PD_AMT,
    AT_PHYSN_NPI, OP_PHYSN_NPI, OT_PHYSN_NPI,
    NCH_BENE_BLOOD_DDCTBL_LBLTY_AM,
    ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
    ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
    ICD9_DGNS_CD_9, ICD9_DGNS_CD_10,
    ICD9_PRCDR_CD_1, ICD9_PRCDR_CD_2, ICD9_PRCDR_CD_3,
    ICD9_PRCDR_CD_4, ICD9_PRCDR_CD_5, ICD9_PRCDR_CD_6,
    NCH_BENE_PTB_DDCTBL_AMT, NCH_BENE_PTB_COINSRNC_AMT,
    ADMTNG_ICD9_DGNS_CD,
    HCPCS_CD_1,  HCPCS_CD_2,  HCPCS_CD_3,  HCPCS_CD_4,  HCPCS_CD_5,
    HCPCS_CD_6,  HCPCS_CD_7,  HCPCS_CD_8,  HCPCS_CD_9,  HCPCS_CD_10,
    HCPCS_CD_11, HCPCS_CD_12, HCPCS_CD_13, HCPCS_CD_14, HCPCS_CD_15,
    HCPCS_CD_16, HCPCS_CD_17, HCPCS_CD_18, HCPCS_CD_19, HCPCS_CD_20,
    HCPCS_CD_21, HCPCS_CD_22, HCPCS_CD_23, HCPCS_CD_24, HCPCS_CD_25,
    HCPCS_CD_26, HCPCS_CD_27, HCPCS_CD_28, HCPCS_CD_29, HCPCS_CD_30,
    HCPCS_CD_31, HCPCS_CD_32, HCPCS_CD_33, HCPCS_CD_34, HCPCS_CD_35,
    HCPCS_CD_36, HCPCS_CD_37, HCPCS_CD_38, HCPCS_CD_39, HCPCS_CD_40,
    HCPCS_CD_41, HCPCS_CD_42, HCPCS_CD_43, HCPCS_CD_44, HCPCS_CD_45,
    _SOURCE_FILE
)
FROM (
    SELECT
        $1,  $2,  $3,  $4,  $5,  $6,  $7,  $8,  $9,  $10,
        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
        $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
        $31, $32, $33, $34, $35, $36, $37, $38, $39, $40,
        $41, $42, $43, $44, $45, $46, $47, $48, $49, $50,
        $51, $52, $53, $54, $55, $56, $57, $58, $59, $60,
        $61, $62, $63, $64, $65, $66, $67, $68, $69, $70,
        $71, $72, $73, $74, $75, $76,
        METADATA$FILENAME
    FROM @DESYNPUF_STAGE/outpatient/
)
FILE_FORMAT = CSV_DESYNPUF
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- Verify load
SELECT
    'STG_OUTPATIENT_CLAIMS' AS table_name,
    COUNT(*)                AS total_rows,
    COUNT(DISTINCT CLM_ID)  AS distinct_claims
FROM STG_OUTPATIENT_CLAIMS;

-- -------------------------------------------------------
-- 4. Load Carrier Claims
--    IMPORTANT: Each sample has TWO files (segment A + B).
--    Both must be uploaded to the stage.
-- -------------------------------------------------------
COPY INTO STG_CARRIER_CLAIMS (
    DESYNPUF_ID, CLM_ID, CLM_FROM_DT, CLM_THRU_DT,
    ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
    ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
    PRF_PHYSN_NPI_1,  PRF_PHYSN_NPI_2,  PRF_PHYSN_NPI_3,
    PRF_PHYSN_NPI_4,  PRF_PHYSN_NPI_5,  PRF_PHYSN_NPI_6,
    PRF_PHYSN_NPI_7,  PRF_PHYSN_NPI_8,  PRF_PHYSN_NPI_9,
    PRF_PHYSN_NPI_10, PRF_PHYSN_NPI_11, PRF_PHYSN_NPI_12,
    PRF_PHYSN_NPI_13,
    TAX_NUM_1,  TAX_NUM_2,  TAX_NUM_3,  TAX_NUM_4,
    TAX_NUM_5,  TAX_NUM_6,  TAX_NUM_7,  TAX_NUM_8,
    TAX_NUM_9,  TAX_NUM_10, TAX_NUM_11, TAX_NUM_12, TAX_NUM_13,
    HCPCS_CD_1,  HCPCS_CD_2,  HCPCS_CD_3,  HCPCS_CD_4,
    HCPCS_CD_5,  HCPCS_CD_6,  HCPCS_CD_7,  HCPCS_CD_8,
    HCPCS_CD_9,  HCPCS_CD_10, HCPCS_CD_11, HCPCS_CD_12, HCPCS_CD_13,
    LINE_NCH_PMT_AMT_1,  LINE_NCH_PMT_AMT_2,  LINE_NCH_PMT_AMT_3,
    LINE_NCH_PMT_AMT_4,  LINE_NCH_PMT_AMT_5,  LINE_NCH_PMT_AMT_6,
    LINE_NCH_PMT_AMT_7,  LINE_NCH_PMT_AMT_8,  LINE_NCH_PMT_AMT_9,
    LINE_NCH_PMT_AMT_10, LINE_NCH_PMT_AMT_11, LINE_NCH_PMT_AMT_12,
    LINE_NCH_PMT_AMT_13,
    LINE_BENE_PTB_DDCTBL_AMT_1,  LINE_BENE_PTB_DDCTBL_AMT_2,
    LINE_BENE_PTB_DDCTBL_AMT_3,  LINE_BENE_PTB_DDCTBL_AMT_4,
    LINE_BENE_PTB_DDCTBL_AMT_5,  LINE_BENE_PTB_DDCTBL_AMT_6,
    LINE_BENE_PTB_DDCTBL_AMT_7,  LINE_BENE_PTB_DDCTBL_AMT_8,
    LINE_BENE_PTB_DDCTBL_AMT_9,  LINE_BENE_PTB_DDCTBL_AMT_10,
    LINE_BENE_PTB_DDCTBL_AMT_11, LINE_BENE_PTB_DDCTBL_AMT_12,
    LINE_BENE_PTB_DDCTBL_AMT_13,
    LINE_BENE_PRMRY_PYR_PD_AMT_1,  LINE_BENE_PRMRY_PYR_PD_AMT_2,
    LINE_BENE_PRMRY_PYR_PD_AMT_3,  LINE_BENE_PRMRY_PYR_PD_AMT_4,
    LINE_BENE_PRMRY_PYR_PD_AMT_5,  LINE_BENE_PRMRY_PYR_PD_AMT_6,
    LINE_BENE_PRMRY_PYR_PD_AMT_7,  LINE_BENE_PRMRY_PYR_PD_AMT_8,
    LINE_BENE_PRMRY_PYR_PD_AMT_9,  LINE_BENE_PRMRY_PYR_PD_AMT_10,
    LINE_BENE_PRMRY_PYR_PD_AMT_11, LINE_BENE_PRMRY_PYR_PD_AMT_12,
    LINE_BENE_PRMRY_PYR_PD_AMT_13,
    LINE_COINSRNC_AMT_1,  LINE_COINSRNC_AMT_2,  LINE_COINSRNC_AMT_3,
    LINE_COINSRNC_AMT_4,  LINE_COINSRNC_AMT_5,  LINE_COINSRNC_AMT_6,
    LINE_COINSRNC_AMT_7,  LINE_COINSRNC_AMT_8,  LINE_COINSRNC_AMT_9,
    LINE_COINSRNC_AMT_10, LINE_COINSRNC_AMT_11, LINE_COINSRNC_AMT_12,
    LINE_COINSRNC_AMT_13,
    LINE_ALOWD_CHRG_AMT_1,  LINE_ALOWD_CHRG_AMT_2,  LINE_ALOWD_CHRG_AMT_3,
    LINE_ALOWD_CHRG_AMT_4,  LINE_ALOWD_CHRG_AMT_5,  LINE_ALOWD_CHRG_AMT_6,
    LINE_ALOWD_CHRG_AMT_7,  LINE_ALOWD_CHRG_AMT_8,  LINE_ALOWD_CHRG_AMT_9,
    LINE_ALOWD_CHRG_AMT_10, LINE_ALOWD_CHRG_AMT_11, LINE_ALOWD_CHRG_AMT_12,
    LINE_ALOWD_CHRG_AMT_13,
    LINE_PRCSG_IND_CD_1,  LINE_PRCSG_IND_CD_2,  LINE_PRCSG_IND_CD_3,
    LINE_PRCSG_IND_CD_4,  LINE_PRCSG_IND_CD_5,  LINE_PRCSG_IND_CD_6,
    LINE_PRCSG_IND_CD_7,  LINE_PRCSG_IND_CD_8,  LINE_PRCSG_IND_CD_9,
    LINE_PRCSG_IND_CD_10, LINE_PRCSG_IND_CD_11, LINE_PRCSG_IND_CD_12,
    LINE_PRCSG_IND_CD_13,
    LINE_ICD9_DGNS_CD_1,  LINE_ICD9_DGNS_CD_2,  LINE_ICD9_DGNS_CD_3,
    LINE_ICD9_DGNS_CD_4,  LINE_ICD9_DGNS_CD_5,  LINE_ICD9_DGNS_CD_6,
    LINE_ICD9_DGNS_CD_7,  LINE_ICD9_DGNS_CD_8,  LINE_ICD9_DGNS_CD_9,
    LINE_ICD9_DGNS_CD_10, LINE_ICD9_DGNS_CD_11, LINE_ICD9_DGNS_CD_12,
    LINE_ICD9_DGNS_CD_13,
    _SOURCE_FILE
)
FROM (
    SELECT
        $1,   $2,   $3,   $4,   $5,   $6,   $7,   $8,   $9,   $10,
        $11,  $12,  $13,  $14,  $15,  $16,  $17,  $18,  $19,  $20,
        $21,  $22,  $23,  $24,  $25,  $26,  $27,  $28,  $29,  $30,
        $31,  $32,  $33,  $34,  $35,  $36,  $37,  $38,  $39,  $40,
        $41,  $42,  $43,  $44,  $45,  $46,  $47,  $48,  $49,  $50,
        $51,  $52,  $53,  $54,  $55,  $56,  $57,  $58,  $59,  $60,
        $61,  $62,  $63,  $64,  $65,  $66,  $67,  $68,  $69,  $70,
        $71,  $72,  $73,  $74,  $75,  $76,  $77,  $78,  $79,  $80,
        $81,  $82,  $83,  $84,  $85,  $86,  $87,  $88,  $89,  $90,
        $91,  $92,  $93,  $94,  $95,  $96,  $97,  $98,  $99,  $100,
        $101, $102, $103, $104, $105, $106, $107, $108, $109, $110,
        $111, $112, $113, $114, $115, $116, $117, $118, $119, $120,
        $121, $122, $123, $124, $125, $126, $127, $128, $129, $130,
        $131, $132, $133, $134, $135, $136, $137, $138, $139, $140,
        $141, $142,
        METADATA$FILENAME
    FROM @DESYNPUF_STAGE/carrier/
)
FILE_FORMAT = CSV_DESYNPUF
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- Verify load
SELECT
    'STG_CARRIER_CLAIMS' AS table_name,
    COUNT(*)             AS total_rows,
    COUNT(DISTINCT CLM_ID) AS distinct_claims,
    COUNT(DISTINCT DESYNPUF_ID) AS distinct_beneficiaries,
    COUNT(DISTINCT _SOURCE_FILE) AS files_loaded
FROM STG_CARRIER_CLAIMS;

-- -------------------------------------------------------
-- 5. Load Prescription Drug Events
-- -------------------------------------------------------
COPY INTO STG_PDE (
    DESYNPUF_ID, PDE_ID, SRVC_DT, PROD_SRVC_ID,
    QTY_DSPNSD_NUM, DAYS_SUPLY_NUM, PTNT_PAY_AMT, TOT_RX_CST_AMT,
    _SOURCE_FILE
)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, METADATA$FILENAME
    FROM @DESYNPUF_STAGE/pde/
)
FILE_FORMAT = CSV_DESYNPUF
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- Verify load
SELECT
    'STG_PDE' AS table_name,
    COUNT(*)  AS total_rows,
    COUNT(DISTINCT PDE_ID) AS distinct_events
FROM STG_PDE;

-- -------------------------------------------------------
-- FINAL VERIFICATION: Row counts across all staging tables
-- -------------------------------------------------------
SELECT 'STG_BENEFICIARY_SUMMARY' AS tbl, COUNT(*) AS rows FROM STG_BENEFICIARY_SUMMARY
UNION ALL
SELECT 'STG_INPATIENT_CLAIMS',    COUNT(*) FROM STG_INPATIENT_CLAIMS
UNION ALL
SELECT 'STG_OUTPATIENT_CLAIMS',   COUNT(*) FROM STG_OUTPATIENT_CLAIMS
UNION ALL
SELECT 'STG_CARRIER_CLAIMS',      COUNT(*) FROM STG_CARRIER_CLAIMS
UNION ALL
SELECT 'STG_PDE',                 COUNT(*) FROM STG_PDE
ORDER BY tbl;

-- -------------------------------------------------------
-- IMPORTANT: Screenshot the verification output.
-- Expected approximate counts for Sample 1 (all years combined):
--   Beneficiary Summary : ~116K × 3 years = ~348K rows
--   Inpatient Claims    : ~66K
--   Outpatient Claims   : ~790K
--   Carrier Claims      : ~1.8M (across both A and B segments)
--   PDE                 : ~1.1M
-- -------------------------------------------------------
