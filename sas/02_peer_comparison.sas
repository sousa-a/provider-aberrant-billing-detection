/* =============================================================================
   P3 — Provider Aberrant Billing Pattern Detection
   02_peer_comparison.sas

   Purpose : Peer-group z-score computation and percentile ranking in SAS.
             Demonstrates PROC STDIZE, PROC RANK, PROC SQL with window
             functions, and BY-group processing.

   Input   : VW_PROVIDER_BILLING_METRICS export from Snowflake
             (same CSV used in 01_data_profiling.sas)

   Output  : sas_provider_flags.csv — provider-level flags for cross-method
             validation against Python Isolation Forest (Notebook 04)

   Key design decisions:
     - Peer group = (derived_specialty, volume_tier)
     - Volume tier: Low (<P25), Medium (P25-P75), High (>P75)
     - Minimum peer group size: 10 providers
     - Z-scores computed on log-transformed payment amounts (confirmed
       lognormal by NB01 and 01_data_profiling.sas)
     - Flagging thresholds: |z| > 2.0 (primary), |z| > 3.0 (severe)
   ============================================================================= */

/* ---------------------------------------------------------
   0. CONFIGURATION
   --------------------------------------------------------- */

%LET DATA_DIR = /home/u64579994
%LET INPUT_FILE = &DATA_DIR.provider_billing_metrics.csv;
%LET OUTPUT_DIR = &DATA_DIR.outputs/;

/* ---------------------------------------------------------
   1. IMPORT AND PREPARE DATA
   --------------------------------------------------------- */

PROC IMPORT DATAFILE="&INPUT_FILE."
    OUT=WORK.METRICS_RAW
    DBMS=CSV
    REPLACE;
    GETNAMES=YES;
    GUESSINGROWS=5000;
RUN;

/* Exclude low-volume providers (quality contract: <5 claims excluded) */
DATA WORK.METRICS;
    SET WORK.METRICS_RAW;
    WHERE total_claims >= 30;
    
    /* Log-transform payment metrics (confirmed lognormal in profiling phase) */
    IF avg_paid_per_line > 0 THEN log_avg_paid = LOG(avg_paid_per_line);
    IF total_paid > 0 THEN log_total_paid = LOG(total_paid);
    IF lines_per_beneficiary > 0 THEN log_lines_per_bene = LOG(lines_per_beneficiary);
RUN;

PROC SQL NOPRINT;
    SELECT COUNT(*) INTO :N_RETAINED FROM WORK.METRICS;
QUIT;
%PUT NOTE: Providers retained after min_claims filter: &N_RETAINED.;

/* ---------------------------------------------------------
   2. ASSIGN VOLUME TIERS
   Compute P25 and P75 of total_lines per specialty,
   then classify each provider into Low / Medium / High.
   --------------------------------------------------------- */

PROC SQL;
    CREATE TABLE WORK.SPECIALTY_PERCENTILES AS
    SELECT
        derived_specialty,
        COUNT(*) AS specialty_count,
        CALCULATED specialty_count AS n_specialty,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_lines) AS p25_lines,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_lines) AS p75_lines
    FROM WORK.METRICS
    GROUP BY derived_specialty;
QUIT;

/* Note: If PERCENTILE_CONT is not available in your SAS version,
   use PROC UNIVARIATE to compute P25/P75 per specialty instead:
   PROC UNIVARIATE DATA=WORK.METRICS NOPRINT;
       BY derived_specialty;
       VAR total_lines;
       OUTPUT OUT=WORK.SPECIALTY_PERCENTILES P25=p25_lines P75=p75_lines N=specialty_count;
   RUN;
*/

PROC SQL;
    CREATE TABLE WORK.METRICS_TIERED AS
    SELECT
        m.*,
        CASE
            WHEN m.total_lines < sp.p25_lines THEN 'Low'
            WHEN m.total_lines > sp.p75_lines THEN 'High'
            ELSE 'Medium'
        END AS volume_tier LENGTH=6,
        CATX('_', m.derived_specialty, 
            CASE
                WHEN m.total_lines < sp.p25_lines THEN 'Low'
                WHEN m.total_lines > sp.p75_lines THEN 'High'
                ELSE 'Medium'
            END) AS peer_group_key LENGTH=60
    FROM WORK.METRICS m
    LEFT JOIN WORK.SPECIALTY_PERCENTILES sp
        ON m.derived_specialty = sp.derived_specialty;
QUIT;

TITLE "2.1 — Peer Group Distribution";
PROC FREQ DATA=WORK.METRICS_TIERED ORDER=FREQ;
    TABLES peer_group_key / NOCUM;
RUN;
TITLE;

/* ---------------------------------------------------------
   3. FILTER: MINIMUM PEER GROUP SIZE
   Only peer groups with >= 10 providers are retained
   for z-score computation.
   --------------------------------------------------------- */

PROC SQL;
    CREATE TABLE WORK.PEER_GROUP_SIZES AS
    SELECT peer_group_key, COUNT(*) AS peer_group_size
    FROM WORK.METRICS_TIERED
    GROUP BY peer_group_key
    HAVING COUNT(*) >= 10;
QUIT;

PROC SQL;
    CREATE TABLE WORK.METRICS_VALID AS
    SELECT m.*, pg.peer_group_size
    FROM WORK.METRICS_TIERED m
    INNER JOIN WORK.PEER_GROUP_SIZES pg
        ON m.peer_group_key = pg.peer_group_key;
QUIT;

PROC SQL NOPRINT;
    SELECT COUNT(*) INTO :N_VALID FROM WORK.METRICS_VALID;
    SELECT COUNT(DISTINCT peer_group_key) INTO :N_GROUPS FROM WORK.METRICS_VALID;
QUIT;
%PUT NOTE: Providers in valid peer groups (>=10): &N_VALID.;
%PUT NOTE: Distinct peer groups: &N_GROUPS.;

/* ---------------------------------------------------------
   4. Z-SCORES VIA PROC STDIZE
   Standardize each metric within its peer group.
   METHOD=STD computes (x - mean) / stddev.
   --------------------------------------------------------- */

PROC SORT DATA=WORK.METRICS_VALID;
    BY peer_group_key;
RUN;

/* Z-scores on key billing metrics */
PROC STDIZE DATA=WORK.METRICS_VALID
    OUT=WORK.METRICS_ZSCORED
    METHOD=STD;
    BY peer_group_key;
    VAR log_avg_paid
        lines_per_beneficiary
        claims_per_beneficiary
        hcpcs_concentration
        pct_high_complexity_em
        avg_diagnoses_per_claim
        log_total_paid;
RUN;

/* Rename z-scored variables to z_ prefix for clarity */
DATA WORK.METRICS_ZSCORED;
    SET WORK.METRICS_ZSCORED(
        RENAME=(
            log_avg_paid=z_log_avg_paid
            lines_per_beneficiary=z_lines_per_bene
            claims_per_beneficiary=z_claims_per_bene
            hcpcs_concentration=z_hcpcs_conc
            pct_high_complexity_em=z_pct_high_em
            avg_diagnoses_per_claim=z_avg_dgns
            log_total_paid=z_log_total_paid
        )
    );

    /* Compute max absolute z-score across all metrics */
    z_max_abs = MAX(
        ABS(z_log_avg_paid),
        ABS(z_lines_per_bene),
        ABS(z_claims_per_bene),
        ABS(z_hcpcs_conc),
        ABS(z_pct_high_em),
        ABS(z_avg_dgns),
        ABS(z_log_total_paid)
    );

    /* Flag providers */
    flag_zscore_2 = (z_max_abs > 2.0);
    flag_zscore_3 = (z_max_abs > 3.0);
RUN;

TITLE "4.1 — Z-Score Flag Summary";
PROC FREQ DATA=WORK.METRICS_ZSCORED;
    TABLES flag_zscore_2 flag_zscore_3 / NOCUM;
RUN;
TITLE;

/* ---------------------------------------------------------
   5. PERCENTILE RANKING VIA PROC RANK
   Non-parametric alternative to z-scores.
   Flag: provider at P95+ in >= 2 metrics simultaneously.
   --------------------------------------------------------- */

/* Rejoin original metric values for ranking */
PROC SQL;
    CREATE TABLE WORK.METRICS_FOR_RANK AS
    SELECT
        a.provider_npi,
        a.derived_specialty,
        a.peer_group_key,
        a.peer_group_size,
        b.avg_paid_per_line,
        b.lines_per_beneficiary,
        b.claims_per_beneficiary,
        b.hcpcs_concentration,
        b.pct_high_complexity_em,
        b.avg_diagnoses_per_claim,
        b.total_paid,
        b.distinct_beneficiaries,
        b.total_lines,
        a.z_max_abs,
        a.flag_zscore_2,
        a.flag_zscore_3
    FROM WORK.METRICS_ZSCORED a
    INNER JOIN WORK.METRICS_VALID b
        ON a.provider_npi = b.provider_npi;
QUIT;

PROC SORT DATA=WORK.METRICS_FOR_RANK;
    BY peer_group_key;
RUN;

PROC RANK DATA=WORK.METRICS_FOR_RANK
    OUT=WORK.METRICS_RANKED
    GROUPS=100
    TIES=MEAN;
    BY peer_group_key;
    VAR avg_paid_per_line lines_per_beneficiary claims_per_beneficiary
        hcpcs_concentration pct_high_complexity_em avg_diagnoses_per_claim
        total_paid;
    RANKS pctl_avg_paid pctl_lines_per_bene pctl_claims_per_bene
          pctl_hcpcs_conc pctl_pct_high_em pctl_avg_dgns
          pctl_total_paid;
RUN;

/* Count how many metrics each provider is at P95+ */
DATA WORK.METRICS_RANKED;
    SET WORK.METRICS_RANKED;
    n_metrics_p95 = (pctl_avg_paid >= 95)
                  + (pctl_lines_per_bene >= 95)
                  + (pctl_claims_per_bene >= 95)
                  + (pctl_hcpcs_conc >= 95)
                  + (pctl_pct_high_em >= 95)
                  + (pctl_avg_dgns >= 95)
                  + (pctl_total_paid >= 95);

    /* Flag: P95+ in >= 2 metrics */
    flag_percentile = (n_metrics_p95 >= 2);
RUN;

TITLE "5.1 — Percentile Flag Summary";
PROC FREQ DATA=WORK.METRICS_RANKED;
    TABLES flag_percentile n_metrics_p95 / NOCUM;
RUN;
TITLE;

/* ---------------------------------------------------------
   6. COMBINED FLAG SUMMARY
   --------------------------------------------------------- */

TITLE "6.1 — Cross-Tabulation: Z-Score Flag vs Percentile Flag";
PROC FREQ DATA=WORK.METRICS_RANKED;
    TABLES flag_zscore_2 * flag_percentile / NOCUM NOPERCENT NOROW NOCOL;
RUN;
TITLE;

TITLE "6.2 — Top 20 Providers by Z-Max (Both Methods Flagged)";
PROC SQL OUTOBS=20;
    SELECT
        provider_npi,
        derived_specialty,
        peer_group_key,
        peer_group_size,
        total_paid FORMAT=DOLLAR14.2,
        z_max_abs FORMAT=8.4,
        n_metrics_p95,
        flag_zscore_2,
        flag_zscore_3,
        flag_percentile
    FROM WORK.METRICS_RANKED
    WHERE flag_zscore_2 = 1 AND flag_percentile = 1
    ORDER BY z_max_abs DESC;
QUIT;
TITLE;

/* ---------------------------------------------------------
   7. EXPORT FOR CROSS-METHOD VALIDATION
   This CSV feeds Python Notebook 04 (concordance matrix
   with Isolation Forest flags).
   --------------------------------------------------------- */

PROC EXPORT DATA=WORK.METRICS_RANKED
    OUTFILE="&OUTPUT_DIR.sas_provider_flags.csv"
    DBMS=CSV REPLACE;
RUN;

%PUT NOTE: ============================================================;
%PUT NOTE: SAS 02_peer_comparison.sas complete.;
%PUT NOTE: Exported: sas_provider_flags.csv;
%PUT NOTE: Contains z-score flags (PROC STDIZE) and percentile flags;
%PUT NOTE: (PROC RANK) for cross-method validation against Python IF.;
%PUT NOTE: Proceed to: 03_visualization.sas;
%PUT NOTE: ============================================================;
