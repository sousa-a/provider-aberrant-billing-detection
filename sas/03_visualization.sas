/* =============================================================================
   P3 — Provider Aberrant Billing Pattern Detection
   03_visualization.sas

   Purpose : Publication-quality visualizations in SAS for the README,
             Medium blog post, and portfolio. Demonstrates PROC SGPLOT,
             PROC SGPANEL, and ODS GRAPHICS.

   Input   : WORK.METRICS_RANKED from 02_peer_comparison.sas
             (Run 02 first, or re-import the sas_provider_flags.csv)

   Output  : PNG figures saved to &OUTPUT_DIR.
   ============================================================================= */

/* ---------------------------------------------------------
   0. CONFIGURATION
   --------------------------------------------------------- */

%LET DATA_DIR = /home/u64579994
%LET OUTPUT_DIR = &DATA_DIR.outputs/;

/* If running standalone (not after 02), re-import the flags CSV */
%MACRO LOAD_IF_NEEDED;
    %IF %SYSFUNC(EXIST(WORK.METRICS_RANKED)) = 0 %THEN %DO;
        %PUT NOTE: WORK.METRICS_RANKED not found. Importing from CSV...;
        PROC IMPORT DATAFILE="&OUTPUT_DIR.sas_provider_flags.csv"
            OUT=WORK.METRICS_RANKED
            DBMS=CSV REPLACE;
            GETNAMES=YES;
            GUESSINGROWS=5000;
        RUN;
    %END;
%MEND;
%LOAD_IF_NEEDED;

/* Set ODS graphics options */
ODS GRAPHICS ON / WIDTH=10IN HEIGHT=6IN IMAGEFMT=PNG RESET=ALL;

/* ---------------------------------------------------------
   1. VOLUME vs INTENSITY SCATTER — the key FWA diagnostic plot
   --------------------------------------------------------- */

/* This plot distinguishes two provider profiles:
     - High volume, normal unit cost → legitimate high-volume practice
     - Normal volume, high unit cost → potential FWA (upcoding, abuse)
   Color-coding by flag status shows where the model finds outliers. */

TITLE "Provider Billing Profiles: Volume vs Intensity";
TITLE2 "Color indicates z-score flag status (|z| > 2.0)";
PROC SGPLOT DATA=WORK.METRICS_RANKED;
    SCATTER X=total_lines Y=avg_paid_per_line /
        GROUP=flag_zscore_2
        MARKERATTRS=(SYMBOL=CIRCLEFILLED SIZE=4)
        TRANSPARENCY=0.6;
    XAXIS LABEL="Total Claim Lines (log scale)" TYPE=LOG LOGBASE=10
        GRID GRIDATTRS=(COLOR=CXEEEEEE);
    YAXIS LABEL="Average Paid Per Line ($)"
        GRID GRIDATTRS=(COLOR=CXEEEEEE);
    KEYLEGEND / TITLE="Flagged (|z|>2)"
        LOCATION=INSIDE POSITION=TOPRIGHT ACROSS=1;
RUN;
TITLE;

/* ---------------------------------------------------------
   2. Z-SCORE DISTRIBUTION BY SPECIALTY
   --------------------------------------------------------- */

PROC SORT DATA=WORK.METRICS_RANKED;
    BY derived_specialty;
RUN;

TITLE "Z-Score Distribution by Derived Specialty";
TITLE2 "Max absolute z-score across all billing metrics";
PROC SGPANEL DATA=WORK.METRICS_RANKED;
    PANELBY derived_specialty / COLUMNS=3 ROWS=3 UNISCALE=ROW
        HEADERATTRS=(SIZE=9);
    HISTOGRAM z_max_abs / FILLATTRS=(COLOR=CX4A6FA5) BINWIDTH=0.5;
    REFLINE 2 / AXIS=X LINEATTRS=(PATTERN=DASH COLOR=CXD4A017 THICKNESS=2)
        LABEL="z=2";
    REFLINE 3 / AXIS=X LINEATTRS=(PATTERN=DASH COLOR=CXC0392B THICKNESS=2)
        LABEL="z=3";
    COLAXIS LABEL="Max |z-score|" VALUES=(0 TO 10 BY 1);
    ROWAXIS LABEL="Frequency";
RUN;
TITLE;

/* ---------------------------------------------------------
   3. BOX PLOTS BY PEER GROUP — avg paid per line
   --------------------------------------------------------- */

TITLE "Average Paid Per Line by Peer Group";
TITLE2 "Box plots showing within-group variation";
PROC SGPLOT DATA=WORK.METRICS_RANKED;
    VBOX avg_paid_per_line / CATEGORY=peer_group_key
        FILLATTRS=(COLOR=CX4A6FA5)
        MEDIANATTRS=(COLOR=CXD4A017 THICKNESS=2)
        OUTLIERATTRS=(SYMBOL=CIRCLEFILLED SIZE=3 COLOR=CXC0392B);
    XAXIS LABEL="Peer Group" FITPOLICY=ROTATE
        VALUEATTRS=(SIZE=7);
    YAXIS LABEL="Avg Paid Per Line ($)";
RUN;
TITLE;

/* ---------------------------------------------------------
   4. HCPCS CONCENTRATION vs CLAIMS PER BENEFICIARY
   Identifies providers who bill a narrow set of codes
   at high intensity — a common FWA pattern.
   --------------------------------------------------------- */

TITLE "Code Concentration vs Utilization Intensity";
TITLE2 "Providers with high concentration AND high claims/beneficiary are flagged";
PROC SGPLOT DATA=WORK.METRICS_RANKED;
    SCATTER X=hcpcs_concentration Y=claims_per_beneficiary /
        GROUP=flag_zscore_2
        MARKERATTRS=(SYMBOL=CIRCLEFILLED SIZE=4)
        TRANSPARENCY=0.6;
    XAXIS LABEL="HCPCS Concentration (fraction on top code)"
        VALUES=(0 TO 1 BY 0.1)
        GRID GRIDATTRS=(COLOR=CXEEEEEE);
    YAXIS LABEL="Claims Per Beneficiary"
        GRID GRIDATTRS=(COLOR=CXEEEEEE);
    KEYLEGEND / TITLE="Flagged (|z|>2)"
        LOCATION=INSIDE POSITION=TOPRIGHT ACROSS=1;
RUN;
TITLE;

/* ---------------------------------------------------------
   5. PARETO CHART — top 20 providers by total_paid
   --------------------------------------------------------- */

PROC SQL;
    CREATE TABLE WORK.TOP20_PAID AS
    SELECT
        provider_npi,
        derived_specialty,
        total_paid,
        flag_zscore_2,
        flag_percentile
    FROM WORK.METRICS_RANKED
    ORDER BY total_paid DESC;
QUIT;

DATA WORK.TOP20_PAID;
    SET WORK.TOP20_PAID(OBS=20);
    rank = _N_;
    provider_label = CATS("P", PUT(rank, Z2.), " (", SUBSTR(provider_npi, 1, 4), "...)");
RUN;

TITLE "Top 20 Providers by Total Paid Amount";
TITLE2 "Amber bars = flagged by both z-score and percentile methods";
PROC SGPLOT DATA=WORK.TOP20_PAID;
    VBAR provider_label / RESPONSE=total_paid
        GROUP=flag_zscore_2
        GROUPDISPLAY=CLUSTER
        DATALABEL DATALABELATTRS=(SIZE=7);
    XAXIS LABEL="Provider (ranked)" FITPOLICY=ROTATE
        VALUEATTRS=(SIZE=7);
    YAXIS LABEL="Total Paid ($)" GRID
        GRIDATTRS=(COLOR=CXEEEEEE);
    FORMAT total_paid DOLLAR14.;
RUN;
TITLE;

/* ---------------------------------------------------------
   6. SENSITIVITY CURVE — flag count vs z-score threshold
   --------------------------------------------------------- */

DATA WORK.SENSITIVITY;
    SET WORK.METRICS_RANKED;
    ARRAY thresholds[8] _TEMPORARY_ (1.0 1.5 2.0 2.5 3.0 3.5 4.0 5.0);
    DO i = 1 TO 8;
        threshold = thresholds[i];
        flagged = (z_max_abs > threshold);
        OUTPUT;
    END;
    DROP i;
RUN;

PROC SQL;
    CREATE TABLE WORK.SENSITIVITY_CURVE AS
    SELECT
        threshold,
        SUM(flagged) AS n_flagged,
        COUNT(*) AS n_total,
        SUM(flagged) / COUNT(*) * 100 AS pct_flagged FORMAT=8.2
    FROM WORK.SENSITIVITY
    GROUP BY threshold
    ORDER BY threshold;
QUIT;

TITLE "Sensitivity Analysis: Flag Count vs Z-Score Threshold";
TITLE2 "Trade-off between sensitivity (more flags) and specificity (fewer flags)";
PROC SGPLOT DATA=WORK.SENSITIVITY_CURVE;
    SERIES X=threshold Y=pct_flagged /
        LINEATTRS=(COLOR=CX1B3A4B THICKNESS=2)
        MARKERS MARKERATTRS=(SYMBOL=CIRCLEFILLED SIZE=8 COLOR=CX4A6FA5);
    REFLINE 2 / AXIS=X LINEATTRS=(PATTERN=DASH COLOR=CXD4A017)
        LABEL="Primary threshold (z=2)";
    REFLINE 3 / AXIS=X LINEATTRS=(PATTERN=DASH COLOR=CXC0392B)
        LABEL="Severe threshold (z=3)";
    XAXIS LABEL="Z-Score Threshold" VALUES=(1 TO 5 BY 0.5);
    YAXIS LABEL="% Providers Flagged";
    INSET ("z=2" = PUT(pct_flagged, 8.2) "z=3" = PUT(pct_flagged, 8.2))
        / POSITION=TOPRIGHT;
RUN;
TITLE;

ODS GRAPHICS OFF;

%PUT NOTE: ============================================================;
%PUT NOTE: SAS 03_visualization.sas complete.;
%PUT NOTE: All figures saved to &OUTPUT_DIR.;
%PUT NOTE: Key figures for README and Medium post:;
%PUT NOTE:   - Volume vs Intensity scatter (FWA diagnostic);
%PUT NOTE:   - Z-score distribution by specialty (panel);
%PUT NOTE:   - Sensitivity curve (threshold trade-off);
%PUT NOTE:   - HCPCS concentration vs intensity;
%PUT NOTE: ============================================================;
