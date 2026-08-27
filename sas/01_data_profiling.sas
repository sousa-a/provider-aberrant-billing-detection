/* =============================================================================
   P3 - Provider Aberrant Billing Pattern Detection
   01_data_profiling.sas

   Purpose : Data quality profiling in SAS - cross-validates Python NB01 findings.
             Demonstrates PROC FREQ, PROC MEANS, PROC UNIVARIATE, PROC MI,
             and PROC SGPLOT.

   Input   : VW_PROVIDER_BILLING_METRICS export from Snowflake
             (saved as provider_billing_metrics.csv in data/snowflake_exports/)

   Note on technology choices:
     This project implements the same pipeline across Snowflake, SAS, and Python.
     In production, a single stack would be chosen. The multi-stack approach
     demonstrates proficiency across technologies found in US healthcare FWA
     operations - from legacy SAS environments to cloud-native platforms.
   ============================================================================= */

/* ---------------------------------------------------------
   0. CONFIGURATION
   --------------------------------------------------------- */

%LET DATA_DIR = /home/u64579994;
%LET INPUT_FILE = &DATA_DIR.provider_billing_metrics.csv;
%LET OUTPUT_DIR = &DATA_DIR.outputs/;

/* Create output directory */
OPTIONS DLCREATEDIR;
LIBNAME out "&OUTPUT_DIR.";

/* ---------------------------------------------------------
   1. IMPORT DATA
   --------------------------------------------------------- */

PROC IMPORT DATAFILE="&INPUT_FILE."
    OUT=WORK.PROVIDER_METRICS
    DBMS=CSV
    REPLACE;
    GETNAMES=YES;
    GUESSINGROWS=5000;
RUN;

/* Verify import */
TITLE "1.1 - Dataset Structure (PROC CONTENTS)";
PROC CONTENTS DATA=WORK.PROVIDER_METRICS VARNUM;
RUN;
TITLE;

PROC SQL NOPRINT;
    SELECT COUNT(*) INTO :N_PROVIDERS FROM WORK.PROVIDER_METRICS;
QUIT;
%PUT NOTE: Loaded &N_PROVIDERS. providers from &INPUT_FILE.;

/* ---------------------------------------------------------
   2. COMPLETENESS CHECK
   Cross-validates Python NB01 completeness findings.
   --------------------------------------------------------- */

TITLE "2.1 - Missing Value Summary (PROC MEANS NMISS)";
PROC MEANS DATA=WORK.PROVIDER_METRICS N NMISS MIN MAX MEAN MEDIAN STD MAXDEC=2;
    VAR total_lines total_claims distinct_beneficiaries
        total_paid avg_paid_per_line avg_allowed_per_line
        median_paid_per_line lines_per_beneficiary claims_per_beneficiary
        distinct_hcpcs_codes hcpcs_concentration
        pct_high_complexity_em avg_diagnoses_per_claim
        avg_beneficiary_age avg_beneficiary_cc_count pct_complex_beneficiaries
        service_span_days;
RUN;
TITLE;

/* ---------------------------------------------------------
   3. DISTRIBUTION ANALYSIS
   --------------------------------------------------------- */

/* 3.1 - Payment amount distribution (avg_paid_per_line) */
TITLE "3.1 - Avg Paid Per Line: Distribution and Normality Tests";
PROC UNIVARIATE DATA=WORK.PROVIDER_METRICS NORMAL PLOT;
    VAR avg_paid_per_line;
    HISTOGRAM avg_paid_per_line / NORMAL LOGNORMAL;
    INSET N MEAN STD SKEWNESS KURTOSIS / POSITION=NE;
    QQPLOT avg_paid_per_line / NORMAL(MU=EST SIGMA=EST);
RUN;
TITLE;

/* 3.2 - Log-transformed payment amount */
DATA WORK.PROVIDER_METRICS_LOG;
    SET WORK.PROVIDER_METRICS;
    IF avg_paid_per_line > 0 THEN log_avg_paid = LOG(avg_paid_per_line);
    IF total_paid > 0 THEN log_total_paid = LOG(total_paid);
    IF lines_per_beneficiary > 0 THEN log_lines_per_bene = LOG(lines_per_beneficiary);
RUN;

TITLE "3.2 - Log(Avg Paid): Distribution and Normality Tests";
PROC UNIVARIATE DATA=WORK.PROVIDER_METRICS_LOG NORMAL PLOT;
    VAR log_avg_paid;
    HISTOGRAM log_avg_paid / NORMAL;
    INSET N MEAN STD SKEWNESS KURTOSIS / POSITION=NE;
    QQPLOT log_avg_paid / NORMAL(MU=EST SIGMA=EST);
RUN;
TITLE;

/* Key comparison point:
   Python NB01 found skewness=3.44 (raw) → 0.07 (log).
   SAS PROC UNIVARIATE should confirm this.
   The Shapiro-Wilk and Anderson-Darling p-values will formally
   test the normality of the log-transformed distribution. */

/* 3.3 - Provider volume distribution (total_claims) */
TITLE "3.3 - Total Claims Per Provider: Distribution";
PROC UNIVARIATE DATA=WORK.PROVIDER_METRICS NORMAL PLOT;
    VAR total_claims;
    HISTOGRAM total_claims / ENDPOINTS=(0 TO 500 BY 10);
    INSET N MEAN MEDIAN STD P5 P25 P75 P95 P99 / POSITION=NE;
RUN;
TITLE;

/* 3.4 - Lines per beneficiary (utilization intensity) */
TITLE "3.4 - Lines Per Beneficiary (Utilization Intensity)";
PROC UNIVARIATE DATA=WORK.PROVIDER_METRICS NORMAL PLOT;
    VAR lines_per_beneficiary;
    HISTOGRAM lines_per_beneficiary / ENDPOINTS=(0 TO 50 BY 1);
    INSET N MEAN MEDIAN STD SKEWNESS / POSITION=NE;
RUN;
TITLE;

/* ---------------------------------------------------------
   4. CATEGORICAL DISTRIBUTIONS (PROC FREQ)
   --------------------------------------------------------- */

TITLE "4.1 - Derived Specialty Distribution";
PROC FREQ DATA=WORK.PROVIDER_METRICS ORDER=FREQ;
    TABLES derived_specialty / NOCUM PLOTS=FREQPLOT(ORIENT=HORIZONTAL);
RUN;
TITLE;

/* ---------------------------------------------------------
   5. MISSINGNESS PATTERN ANALYSIS (PROC MI)
   --------------------------------------------------------- */

/* PROC MI with NIMPUTE=0 produces a missingness diagnostic report
   without actually imputing anything. This shows:
   - Which variables have missing values
   - Missing data patterns (MCAR vs MAR)
   - Correlation between missingness across variables */

TITLE "5.1 - Missingness Pattern Diagnostic (PROC MI, NIMPUTE=0)";
PROC MI DATA=WORK.PROVIDER_METRICS NIMPUTE=0;
    VAR avg_paid_per_line avg_allowed_per_line lines_per_beneficiary
        claims_per_beneficiary hcpcs_concentration pct_high_complexity_em
        avg_diagnoses_per_claim avg_beneficiary_age avg_beneficiary_cc_count
        pct_complex_beneficiaries;
RUN;
TITLE;

/* ---------------------------------------------------------
   6. CORRELATION MATRIX
   Key billing metrics - identifies redundant features
   --------------------------------------------------------- */

TITLE "6.1 - Correlation Matrix: Key Billing Metrics";
PROC CORR DATA=WORK.PROVIDER_METRICS NOSIMPLE PLOTS=MATRIX(HISTOGRAM);
    VAR avg_paid_per_line lines_per_beneficiary claims_per_beneficiary
        hcpcs_concentration pct_high_complexity_em avg_diagnoses_per_claim
        distinct_hcpcs_codes;
RUN;
TITLE;

/* ---------------------------------------------------------
   7. DESCRIPTIVE STATISTICS BY SPECIALTY (PROC MEANS + BY)
   --------------------------------------------------------- */

PROC SORT DATA=WORK.PROVIDER_METRICS;
    BY derived_specialty;
RUN;

TITLE "7.1 - Billing Metrics by Derived Specialty";
PROC MEANS DATA=WORK.PROVIDER_METRICS N MEAN MEDIAN STD MIN MAX MAXDEC=2;
    BY derived_specialty;
    VAR total_paid avg_paid_per_line lines_per_beneficiary
        hcpcs_concentration pct_high_complexity_em distinct_beneficiaries;
RUN;
TITLE;

/* ---------------------------------------------------------
   8. VISUALIZATIONS (PROC SGPLOT)
   --------------------------------------------------------- */

/* 8.1 - Box plot: avg_paid_per_line by specialty */
TITLE "8.1 - Avg Paid Per Line by Derived Specialty";
PROC SGPLOT DATA=WORK.PROVIDER_METRICS;
    VBOX avg_paid_per_line / CATEGORY=derived_specialty
         FILLATTRS=(COLOR=CX4A6FA5) MEDIANATTRS=(COLOR=CXD4A017 THICKNESS=2);
    XAXIS LABEL="Derived Specialty" FITPOLICY=ROTATE;
    YAXIS LABEL="Avg Paid Per Line ($)";
RUN;
TITLE;

/* 8.2 - Scatter: volume (total_claims) vs intensity (avg_paid_per_line) */
TITLE "8.2 - Volume vs Intensity: Total Claims vs Avg Paid";
PROC SGPLOT DATA=WORK.PROVIDER_METRICS;
    SCATTER X=total_claims Y=avg_paid_per_line /
        MARKERATTRS=(SYMBOL=CIRCLEFILLED SIZE=3 COLOR=CX4A6FA5)
        TRANSPARENCY=0.7;
    XAXIS LABEL="Total Claims" TYPE=LOG LOGBASE=10;
    YAXIS LABEL="Avg Paid Per Line ($)";
    REFLINE 5 / AXIS=X LINEATTRS=(PATTERN=DASH COLOR=CXC0392B)
        LABEL="Min threshold=5";
RUN;
TITLE;

/* 8.3 - Histogram: HCPCS concentration */
TITLE "8.3 - HCPCS Code Concentration Distribution";
PROC SGPLOT DATA=WORK.PROVIDER_METRICS;
    HISTOGRAM hcpcs_concentration / FILLATTRS=(COLOR=CX4A6FA5)
        BINWIDTH=0.05;
    DENSITY hcpcs_concentration / LINEATTRS=(COLOR=CXD4A017 THICKNESS=2);
    XAXIS LABEL="HCPCS Concentration (fraction of claims on top code)"
        VALUES=(0 TO 1 BY 0.1);
    YAXIS LABEL="Frequency";
RUN;
TITLE;

/* ---------------------------------------------------------
   9. EXPORT PROFILING SUMMARY
   --------------------------------------------------------- */

/* Summary table: one row per specialty with key statistics */
PROC SQL;
    CREATE TABLE WORK.PROFILING_SUMMARY AS
    SELECT
        derived_specialty,
        COUNT(*) AS provider_count,
        MEAN(avg_paid_per_line) AS mean_avg_paid FORMAT=DOLLAR12.2,
        MEDIAN(avg_paid_per_line) AS median_avg_paid FORMAT=DOLLAR12.2,
        STD(avg_paid_per_line) AS sd_avg_paid FORMAT=DOLLAR12.2,
        MEAN(lines_per_beneficiary) AS mean_lines_per_bene FORMAT=8.2,
        MEAN(hcpcs_concentration) AS mean_hcpcs_conc FORMAT=8.4,
        MEAN(pct_high_complexity_em) AS mean_pct_high_em FORMAT=8.2,
        MEAN(total_paid) AS mean_total_paid FORMAT=DOLLAR14.2,
        MEAN(distinct_beneficiaries) AS mean_distinct_benes FORMAT=8.1
    FROM WORK.PROVIDER_METRICS
    GROUP BY derived_specialty
    ORDER BY provider_count DESC;
QUIT;

TITLE "9.1 - Profiling Summary by Specialty";
PROC PRINT DATA=WORK.PROFILING_SUMMARY NOOBS;
RUN;
TITLE;

PROC EXPORT DATA=WORK.PROFILING_SUMMARY
    OUTFILE="&OUTPUT_DIR.sas_profiling_summary.csv"
    DBMS=CSV REPLACE;
RUN;

%PUT NOTE: ============================================================;
%PUT NOTE: SAS 01_data_profiling.sas complete.;
%PUT NOTE: Cross-validate findings against Python NB01 and Snowflake;
%PUT NOTE: DATA_QUALITY views. Key comparison points:;
%PUT NOTE:   - Skewness of avg_paid_per_line (NB01: 3.44 raw);
%PUT NOTE:   - Provider count by specialty;
%PUT NOTE:   - Missingness patterns;
%PUT NOTE: Proceed to: 02_peer_comparison.sas;
%PUT NOTE: ============================================================;
