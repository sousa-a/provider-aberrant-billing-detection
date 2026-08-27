# Data Dictionary

**Project:** Provider Aberrant Billing Pattern Detection (P3)  
**Source:** CMS DE-SynPUF (2008–2010), all 20 samples  
**Last updated:** August 2026

---

## 1. Snowflake - RAW Schema (`MEDICARE_FWA.RAW`)

Landing zone tables. All columns are VARCHAR (type casting occurs in ANALYTICS).

### STG_BENEFICIARY_SUMMARY

One row per beneficiary per year (2008, 2009, 2010). Source: `DE1_0_YYYY_Beneficiary_Summary_File_Sample_N.csv`

| Column | Description | Values/Range |
|---|---|---|
| DESYNPUF_ID | Synthetic beneficiary identifier | 10-char alphanumeric |
| BENE_BIRTH_DT | Date of birth | YYYYMMDD |
| BENE_DEATH_DT | Date of death (NULL if alive) | YYYYMMDD or NULL |
| BENE_SEX_IDENT_CD | Sex | 1=Male, 2=Female |
| BENE_RACE_CD | Race | 1=White, 2=Black, 3=Others, 5=Hispanic |
| BENE_ESRD_IND | End-stage renal disease indicator | Y or 0 |
| SP_STATE_CODE | SSA state code | Numeric (01–56) |
| BENE_COUNTY_CD | SSA county code | Numeric |
| BENE_HI_CVRAGE_TOT_MONS | Part A coverage months | 0–12 |
| BENE_SMI_CVRAGE_TOT_MONS | Part B coverage months | 0–12 |
| BENE_HMO_CVRAGE_TOT_MONS | HMO coverage months | 0–12 |
| PLAN_CVRG_MOS_NUM | Part D coverage months | 0–12 |
| SP_ALZHDMTA | Alzheimer's/dementia | 1=Yes, 2=No |
| SP_CHF | Congestive heart failure | 1=Yes, 2=No |
| SP_CHRNKIDN | Chronic kidney disease | 1=Yes, 2=No |
| SP_CNCR | Cancer | 1=Yes, 2=No |
| SP_COPD | COPD | 1=Yes, 2=No |
| SP_DEPRESSN | Depression | 1=Yes, 2=No |
| SP_DIABETES | Diabetes | 1=Yes, 2=No |
| SP_ISCHMCHT | Ischemic heart disease | 1=Yes, 2=No |
| SP_OSTEOPRS | Osteoporosis | 1=Yes, 2=No |
| SP_RA_OA | Rheumatoid arthritis / osteoarthritis | 1=Yes, 2=No |
| SP_STRKETIA | Stroke / TIA | 1=Yes, 2=No |
| MEDREIMB_IP | Inpatient Medicare reimbursement (annual) | Dollars |
| BENRES_IP | Inpatient beneficiary responsibility (annual) | Dollars |
| PPPYMT_IP | Inpatient primary payer reimbursement (annual) | Dollars |
| MEDREIMB_OP | Outpatient Medicare reimbursement (annual) | Dollars |
| BENRES_OP | Outpatient beneficiary responsibility (annual) | Dollars |
| PPPYMT_OP | Outpatient primary payer reimbursement (annual) | Dollars |
| MEDREIMB_CAR | Carrier Medicare reimbursement (annual) | Dollars |
| BENRES_CAR | Carrier beneficiary responsibility (annual) | Dollars |
| PPPYMT_CAR | Carrier primary payer reimbursement (annual) | Dollars |

### STG_CARRIER_CLAIMS

Wide format: up to 13 line items per claim row. Source: `DE1_0_2008_to_2010_Carrier_Claims_Sample_NA.csv` and `NB.csv`

| Column Pattern | Count | Description |
|---|---|---|
| DESYNPUF_ID | 1 | Beneficiary identifier |
| CLM_ID | 1 | Claim identifier |
| CLM_FROM_DT / CLM_THRU_DT | 2 | Claim date range (YYYYMMDD) |
| ICD9_DGNS_CD_1 through _8 | 8 | Claim-level ICD-9 diagnosis codes |
| PRF_PHYSN_NPI_1 through _13 | 13 | Performing physician NPI per line |
| TAX_NUM_1 through _13 | 13 | Provider tax number per line |
| HCPCS_CD_1 through _13 | 13 | HCPCS/CPT procedure code per line |
| LINE_NCH_PMT_AMT_1 through _13 | 13 | Medicare payment amount per line |
| LINE_BENE_PTB_DDCTBL_AMT_1–_13 | 13 | Part B deductible per line |
| LINE_BENE_PRMRY_PYR_PD_AMT_1–_13 | 13 | Primary payer paid per line |
| LINE_COINSRNC_AMT_1 through _13 | 13 | Coinsurance amount per line |
| LINE_ALOWD_CHRG_AMT_1 through _13 | 13 | Allowed charge amount per line |
| LINE_PRCSG_IND_CD_1 through _13 | 13 | Processing indicator code per line |
| LINE_ICD9_DGNS_CD_1 through _13 | 13 | Line-level ICD-9 diagnosis per line |

**Total: 142 columns** (plus 2 metadata columns added at load)

### STG_INPATIENT_CLAIMS

| Key Columns | Description |
|---|---|
| DESYNPUF_ID, CLM_ID | Beneficiary and claim identifiers |
| PRVDR_NUM | Facility provider number |
| AT_PHYSN_NPI / OP_PHYSN_NPI / OT_PHYSN_NPI | Attending, operating, other physician |
| CLM_PMT_AMT | Total claim payment |
| CLM_DRG_CD | Diagnosis Related Group code |
| ICD9_DGNS_CD_1–_10 | Up to 10 diagnosis codes |
| ICD9_PRCDR_CD_1–_6 | Up to 6 procedure codes |

### STG_OUTPATIENT_CLAIMS

Same structure as inpatient, without DRG. Includes Part B cost sharing columns.

### STG_PDE (Prescription Drug Events)

| Column | Description |
|---|---|
| DESYNPUF_ID | Beneficiary identifier |
| PDE_ID | Prescription event identifier |
| SRVC_DT | Service date (YYYYMMDD) |
| PROD_SRVC_ID | NDC code (drug product) |
| QTY_DSPNSD_NUM | Quantity dispensed |
| DAYS_SUPLY_NUM | Days supply |
| PTNT_PAY_AMT | Patient pay amount |
| TOT_RX_CST_AMT | Total drug cost |

---

## 2. Snowflake - ANALYTICS Schema (`MEDICARE_FWA.ANALYTICS`)

Dimensional model with typed columns. Created by `03_create_analytics_schema.sql`.

### DIM_BENEFICIARY

| Column | Type | Source | Description |
|---|---|---|---|
| DESYNPUF_ID | VARCHAR | STG_BENEFICIARY_SUMMARY | Beneficiary identifier |
| birth_date | DATE | Parsed from BENE_BIRTH_DT | Date of birth |
| death_date | DATE | Parsed from BENE_DEATH_DT | Date of death (NULL if alive) |
| is_deceased | BOOLEAN | Derived | TRUE if death_date IS NOT NULL |
| age_at_end | INTEGER | Derived | Age at death or at 2010-12-31 |
| sex | VARCHAR | Mapped from BENE_SEX_IDENT_CD | 'Male', 'Female', 'Unknown' |
| race | VARCHAR | Mapped from BENE_RACE_CD | 'White', 'Black', 'Others', 'Hispanic', 'Unknown' |
| has_esrd | BOOLEAN | Mapped from BENE_ESRD_IND | End-stage renal disease |
| state_code | VARCHAR(2) | Zero-padded SP_STATE_CODE | SSA state code |
| county_code | VARCHAR | BENE_COUNTY_CD | SSA county code |
| part_a_coverage_months | INTEGER | BENE_HI_CVRAGE_TOT_MONS | Part A months |
| part_b_coverage_months | INTEGER | BENE_SMI_CVRAGE_TOT_MONS | Part B months |
| cc_alzheimer through cc_stroke_tia | BOOLEAN (×11) | Mapped 1/2 → TRUE/FALSE | Chronic condition flags |
| chronic_condition_count | INTEGER | Derived | Sum of 11 CC flags (0–11) |
| annual_ip_medicare_reimb | NUMBER(12,2) | MEDREIMB_IP | Annual inpatient reimbursement |
| summary_year | INTEGER | Derived from filename | 2008, 2009, or 2010 |

### FACT_CARRIER_CLAIM_LINES

Unpivoted from STG_CARRIER_CLAIMS: one row per line item (positions 1–13). Created by `03_create_analytics_schema.sql`.

| Column | Type | Description |
|---|---|---|
| CLM_ID | VARCHAR | Claim identifier |
| beneficiary_id | VARCHAR | DESYNPUF_ID |
| service_from_date | DATE | Parsed CLM_FROM_DT |
| service_thru_date | DATE | Parsed CLM_THRU_DT |
| claim_type | VARCHAR | Always 'CARRIER' |
| line_number | INTEGER | Line item position (1–13) |
| provider_npi | VARCHAR | Performing physician NPI for this line |
| tax_number | VARCHAR | Provider tax number |
| hcpcs_code | VARCHAR | HCPCS/CPT procedure code |
| payment_amount | NUMBER(12,2) | Medicare payment |
| deductible_amount | NUMBER(12,2) | Part B deductible |
| primary_payer_paid | NUMBER(12,2) | Primary payer paid |
| coinsurance_amount | NUMBER(12,2) | Coinsurance |
| allowed_charge_amount | NUMBER(12,2) | Allowed charge (billing benchmark) |
| processing_indicator | VARCHAR | Processing indicator code |
| line_diagnosis_code | VARCHAR | Line-level ICD-9 diagnosis |
| clm_dgns_cd_1 through _8 | VARCHAR (×8) | Claim-level diagnosis codes carried forward |

### DIM_PROVIDER

Derived from FACT_CARRIER_CLAIM_LINES. One row per provider NPI.

| Column | Type | Description |
|---|---|---|
| provider_npi | VARCHAR | Performing physician NPI |
| top_hcpcs_code | VARCHAR | Most frequently billed HCPCS code |
| derived_specialty | VARCHAR | Mapped from HCPCS ranges (proxy - see note) |
| total_claim_lines | INTEGER | Total line items billed |
| total_claims | INTEGER | Distinct claim count |
| distinct_beneficiaries | INTEGER | Unique patients served |
| total_paid | NUMBER(12,2) | Total Medicare payments received |
| total_allowed_charges | NUMBER(12,2) | Total allowed charges |
| first_service_date | DATE | Earliest service date |
| last_service_date | DATE | Latest service date |
| distinct_hcpcs_codes | INTEGER | Number of unique procedure codes billed |

**Note:** `derived_specialty` is a proxy based on the provider's most frequent HCPCS code range. In production, NPPES NPI taxonomy codes would be used for accurate specialty classification.

---

## 3. Snowflake - DATA_QUALITY Schema (`MEDICARE_FWA.DATA_QUALITY`)

Views for data quality assessment. Created by `04_data_quality_views.sql`.

| View | Purpose |
|---|---|
| VW_COMPLETENESS_CARRIER_LINES | % NOT NULL per column in FACT_CARRIER_CLAIM_LINES |
| VW_COMPLETENESS_BENEFICIARY | % NOT NULL per column in DIM_BENEFICIARY |
| VW_COMPLETENESS_PROVIDER | % NOT NULL per column in DIM_PROVIDER |
| VW_REFERENTIAL_INTEGRITY | Orphan key counts between fact and dimension tables |
| VW_TEMPORAL_CONSISTENCY | Date logic violations (out of range, end < start, post-mortem) |
| VW_CARDINALITY_CLAIMS_PER_PROVIDER | Distribution of claim lines per provider |
| VW_CARDINALITY_BENES_PER_PROVIDER | Distribution of beneficiaries per provider |
| VW_CARDINALITY_PAYMENT_DIST | Payment amount distribution (percentiles, zero/negative counts) |
| VW_CARDINALITY_BY_SPECIALTY | Provider count and billing stats by derived specialty |

---

## 4. Snowflake - ANALYTICS Views (Provider Profiling)

Created by `05_provider_peer_views.sql`.

### VW_PROVIDER_BILLING_METRICS

One row per provider with 20 billing features.

| Column | Description |
|---|---|
| provider_npi | Provider identifier |
| derived_specialty | HCPCS-based specialty proxy |
| total_lines | Total claim line items |
| total_claims | Distinct claim count |
| distinct_beneficiaries | Unique patients |
| total_paid | Total Medicare payments |
| total_allowed_charges | Total allowed charges |
| avg_paid_per_line | Mean payment per line item |
| avg_allowed_per_line | Mean allowed charge per line |
| median_paid_per_line | Median payment per line |
| lines_per_beneficiary | Utilization intensity |
| claims_per_beneficiary | Claims intensity |
| distinct_hcpcs_codes | Code diversity |
| hcpcs_concentration | Fraction of lines on top HCPCS code |
| avg_diagnoses_per_claim | Diagnostic complexity |
| pct_high_complexity_em | % lines with E&M 99214–99215 |
| avg_beneficiary_age | Mean patient age |
| avg_beneficiary_cc_count | Mean patient chronic condition count |
| pct_complex_beneficiaries | % patients with ≥3 chronic conditions |
| service_span_days | Days between first and last service |

### VW_PROVIDER_PEER_GROUPS

Extends billing metrics with peer group assignment.

| Column | Description |
|---|---|
| (all columns from VW_PROVIDER_BILLING_METRICS) | - |
| volume_tier | 'Low' (<P25), 'Medium' (P25–P75), 'High' (>P75) |
| peer_group_key | Concatenation: `derived_specialty_volume_tier` |

### VW_PEER_STATISTICS

One row per peer group (only groups with ≥10 providers).

| Column | Description |
|---|---|
| peer_group_key | Peer group identifier |
| peer_group_size | Number of providers in group |
| mean_avg_paid / sd_avg_paid | Mean and stddev of avg_paid_per_line |
| mean_lines_per_bene / sd_lines_per_bene | Mean and stddev of lines_per_beneficiary |
| (same pattern for all 7 z-score metrics) | - |

### VW_PROVIDER_ZSCORE_FLAGS

One row per provider in valid peer groups. Contains raw metrics, z-scores, and flags.

| Column | Description |
|---|---|
| (all columns from VW_PROVIDER_PEER_GROUPS) | - |
| peer_group_size | From VW_PEER_STATISTICS |
| z_avg_paid | Z-score of avg_paid_per_line within peer group |
| z_lines_per_bene | Z-score of lines_per_beneficiary |
| z_claims_per_bene | Z-score of claims_per_beneficiary |
| z_hcpcs_conc | Z-score of hcpcs_concentration |
| z_pct_high_em | Z-score of pct_high_complexity_em |
| z_avg_dgns | Z-score of avg_diagnoses_per_claim |
| z_total_paid | Z-score of total_paid |
| z_max_abs | MAX of absolute z-scores across all metrics |
| flag_zscore_2 | TRUE if z_max_abs > 2.0 |
| flag_zscore_3 | TRUE if z_max_abs > 3.0 |
| excess_billing_vs_mean | total_paid − (mean_avg_paid × total_lines) |

---

## 5. Python / DuckDB - Notebook Outputs

### provider_summary_for_sas.csv

Exported by Notebook 01. Feeds SAS `02_peer_comparison.sas`.

| Column | Description |
|---|---|
| provider_npi | Provider identifier |
| total_claims | Claim count (line 1 only) |
| distinct_beneficiaries | Unique patients |
| claims_per_beneficiary | total_claims / distinct_beneficiaries |
| total_paid | Sum of LINE_NCH_PMT_AMT_1 |
| avg_paid_per_claim | Mean of LINE_NCH_PMT_AMT_1 |
| total_allowed_charges | Sum of LINE_ALOWD_CHRG_AMT_1 |
| avg_allowed_per_claim | Mean of LINE_ALOWD_CHRG_AMT_1 |
| distinct_hcpcs_codes | Count distinct HCPCS_CD_1 |
| hcpcs_concentration | Fraction on most frequent HCPCS code |

**Filter:** Providers with ≥5 claims only (MIN_CLAIMS from `src/config.py`).
