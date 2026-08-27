"""
P3 — Provider Aberrant Billing Pattern Detection
config.py — Centralized configuration, paths, and constants.

All thresholds, column lists, and file paths are defined here.
No magic numbers in notebooks — import from this module.
"""

from pathlib import Path

# =============================================================================
# Paths
# =============================================================================

# Project root (this file lives in src/, so parent is the repo root)
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# DE-SynPUF CSV source directory (shared across P1, P2, P3)
DESYNPUF_BASE = Path(
    '/home/aosousa/Documents/PORTFOLIO/Fraud-Waste-Abuse-FWA/'
    'CMS DE-SynPUF MEDICARE/data/desynpuf_csvs'
)

DESYNPUF_PATHS = {
    'beneficiary': DESYNPUF_BASE / 'beneficiary',
    'inpatient':   DESYNPUF_BASE / 'inpatient',
    'outpatient':  DESYNPUF_BASE / 'outpatient',
    'carrier':     DESYNPUF_BASE / 'carrier',
    'pde':         DESYNPUF_BASE / 'pde',
}

# Snowflake exports (CSVs downloaded from Snowsight)
SNOWFLAKE_EXPORTS_DIR = PROJECT_ROOT / 'data' / 'snowflake_exports'

# Output directories
OUTPUT_DIR     = PROJECT_ROOT / 'outputs'
FIGURES_DIR    = OUTPUT_DIR / 'figures'
CASE_FILES_DIR = OUTPUT_DIR / 'case_files'

# Evidence (screenshots, logs)
EVIDENCE_DIR   = PROJECT_ROOT / 'evidence'

# =============================================================================
# Analytical thresholds
# =============================================================================

# Minimum claim lines for a provider to be included in peer comparison
MIN_CLAIMS = 30

# Minimum providers in a peer group for z-scores to be reliable
MIN_PEER_GROUP_SIZE = 10

# Z-score flagging thresholds
Z_THRESHOLD_PRIMARY = 2.0   # Primary flag: |z| > 2.0
Z_THRESHOLD_SEVERE  = 3.0   # Severe flag:  |z| > 3.0

# Percentile flag: provider at P95+ in >= this many metrics simultaneously
PERCENTILE_THRESHOLD = 95
MIN_METRICS_AT_PERCENTILE = 2

# Isolation Forest contamination values for sensitivity analysis
IF_CONTAMINATION_VALUES = [0.03, 0.05, 0.10, 0.15]

# Composite risk score weights
COMPOSITE_WEIGHTS = {
    'zscore':          0.30,
    'isolation_forest': 0.30,
    'excess_billing':  0.30,
    'peer_group_penalty': 0.10,
}

# Priority classification thresholds
PRIORITY_THRESHOLDS = {
    'HIGH':   {'composite_pctl': 95, 'excess_billing': 50_000},
    'MEDIUM': {'composite_pctl': 85, 'excess_billing': 25_000},
    'LOW':    {'composite_pctl': 75},
}

# =============================================================================
# Expected row counts (from Snowflake load — all 20 samples, all years)
# Used for cross-validation between Snowflake, DuckDB, and SAS
# =============================================================================

EXPECTED_ROWS = {
    'beneficiary':       6_873_274,
    'carrier':          94_863_452,
    'inpatient':         1_332_822,
    'outpatient':       15_826_987,
    'pde':             111_085_969,
}

# =============================================================================
# Column name lists
# =============================================================================

# Carrier line-level columns (1-13) used in completeness heatmap
CARRIER_LINE_NUMBERS = range(1, 14)

CARRIER_LINE_GROUPS = {
    'HCPCS':    [f'HCPCS_CD_{i}' for i in CARRIER_LINE_NUMBERS],
    'Payment':  [f'LINE_NCH_PMT_AMT_{i}' for i in CARRIER_LINE_NUMBERS],
    'Allowed':  [f'LINE_ALOWD_CHRG_AMT_{i}' for i in CARRIER_LINE_NUMBERS],
    'Provider': [f'PRF_PHYSN_NPI_{i}' for i in CARRIER_LINE_NUMBERS],
}

# Chronic condition columns in beneficiary summary
CHRONIC_CONDITION_COLS = {
    'SP_ALZHDMTA':  'Alzheimer/Dementia',
    'SP_CHF':       'Heart failure',
    'SP_CHRNKIDN':  'Chronic kidney',
    'SP_CNCR':      'Cancer',
    'SP_COPD':      'COPD',
    'SP_DEPRESSN':  'Depression',
    'SP_DIABETES':  'Diabetes',
    'SP_ISCHMCHT':  'Ischemic heart',
    'SP_OSTEOPRS':  'Osteoporosis',
    'SP_RA_OA':     'RA/OA',
    'SP_STRKETIA':  'Stroke/TIA',
}

# Provider billing metrics used in z-score computation
ZSCORE_METRICS = [
    'avg_paid_per_line',
    'lines_per_beneficiary',
    'claims_per_beneficiary',
    'hcpcs_concentration',
    'pct_high_complexity_em',
    'avg_diagnoses_per_claim',
    'total_paid',
]

# HCPCS-to-specialty mapping (simplified BETOS-like proxy)
# NOTE: This is a proxy. In production, NPPES taxonomy would be used.
HCPCS_SPECIALTY_MAP = {
    'Evaluation & Management': ('99201', '99499'),
    'Surgery':                 ('10021', '69990'),
    'Radiology':               ('70010', '79999'),
    'Pathology & Lab':         ('80047', '89398'),
    'Medicine':                ('90281', '99199'),
    'Anesthesiology':          ('00100', '01999'),
}

# =============================================================================
# Snowflake export file names
# (named by SQL query as specified by user)
# =============================================================================

SNOWFLAKE_EXPORT_FILES = {
    'billing_metrics':       'provider_billing_metrics.csv',
    'zscore_flags':          'provider_zscore_flags.csv',
    'peer_stats':            'peer_statistics.csv',
    'dim_provider':          'dim_provider.csv',
    'fact_summary':          'fact_summary_counts.csv',
    'dq_completeness_carrier': 'dq_completeness_carrier.csv',
    'dq_completeness_bene':    'dq_completeness_beneficiary.csv',
    'dq_ref_integrity':        'dq_referential_integrity.csv',
    'dq_temporal':             'dq_temporal_consistency.csv',
    'dq_cardinality_claims':   'dq_cardinality_claims.csv',
    'dq_cardinality_benes':    'dq_cardinality_benes.csv',
    'dq_cardinality_payment':  'dq_cardinality_payment.csv',
    'dq_cardinality_specialty': 'dq_cardinality_specialty.csv',
}

# =============================================================================
# Data source citation
# =============================================================================

DATA_SOURCE_CITATION = (
    "Source: CMS DE-SynPUF (2008-2010), all 20 samples.\n"
    "(https://www.cms.gov/data-research/statistics-trends-and-reports/"
    "medicare-claims-synthetic-public-use-files/"
    "cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf)\n"
    "Analysis: Alessandro Oliveira de Sousa (August, 2026)."
)

TECH_DISCLAIMER = (
    "This project deliberately implements the same analytical pipeline across "
    "Snowflake (SQL), SAS, and Python/DuckDB. In a production setting, a single "
    "technology stack would be selected based on organizational infrastructure, "
    "licensing, and team expertise. The multi-stack approach here demonstrates "
    "proficiency across the technologies most commonly found in US healthcare "
    "FWA operations."
)
