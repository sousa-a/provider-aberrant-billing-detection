"""
P3 — Provider Aberrant Billing Pattern Detection
data_loader.py — DuckDB connection factory and data loading utilities.

Provides standardized data loading for notebooks, ensuring all notebooks
work from the same connection settings and table definitions.

Usage:
    from src.data_loader import get_connection, create_carrier_lean, create_views
"""

import duckdb
import pandas as pd
from pathlib import Path

from .config import DESYNPUF_PATHS, SNOWFLAKE_EXPORTS_DIR, SNOWFLAKE_EXPORT_FILES


def get_connection(memory_limit: str = '6GB', threads: int = 4) -> duckdb.DuckDBPyConnection:
    """Create a DuckDB in-memory connection with standard settings.

    Args:
        memory_limit: Maximum memory DuckDB may use (e.g. '6GB').
        threads:      Number of parallel threads.

    Returns:
        DuckDB connection object.
    """
    con = duckdb.connect(':memory:')
    con.execute(f"SET memory_limit='{memory_limit}'")
    con.execute(f"SET threads TO {threads}")
    return con


def create_carrier_lean(con: duckdb.DuckDBPyConnection) -> int:
    """Materialize a lean carrier claims table with only the columns needed for P3.

    Reads all 40 carrier CSV files (20 samples × 2 segments) but selects only
    ~72 columns instead of the full 142. This is the one-time materialization
    cost — all subsequent queries hit this in-memory table.

    Args:
        con: Active DuckDB connection.

    Returns:
        Row count of the materialized table.
    """
    carrier_path = str(DESYNPUF_PATHS['carrier'] / '*.csv')

    con.execute(f"""
        CREATE TABLE carrier_lean AS
        SELECT
            DESYNPUF_ID,
            CLM_ID,
            CLM_FROM_DT,
            CLM_THRU_DT,
            ICD9_DGNS_CD_1, ICD9_DGNS_CD_2, ICD9_DGNS_CD_3, ICD9_DGNS_CD_4,
            ICD9_DGNS_CD_5, ICD9_DGNS_CD_6, ICD9_DGNS_CD_7, ICD9_DGNS_CD_8,
            PRF_PHYSN_NPI_1,  HCPCS_CD_1,  LINE_NCH_PMT_AMT_1,  LINE_ALOWD_CHRG_AMT_1,
            LINE_BENE_PTB_DDCTBL_AMT_1, LINE_COINSRNC_AMT_1,
            LINE_PRCSG_IND_CD_1, LINE_ICD9_DGNS_CD_1,
            PRF_PHYSN_NPI_2,  HCPCS_CD_2,  LINE_NCH_PMT_AMT_2,  LINE_ALOWD_CHRG_AMT_2,
            PRF_PHYSN_NPI_3,  HCPCS_CD_3,  LINE_NCH_PMT_AMT_3,  LINE_ALOWD_CHRG_AMT_3,
            PRF_PHYSN_NPI_4,  HCPCS_CD_4,  LINE_NCH_PMT_AMT_4,  LINE_ALOWD_CHRG_AMT_4,
            PRF_PHYSN_NPI_5,  HCPCS_CD_5,  LINE_NCH_PMT_AMT_5,  LINE_ALOWD_CHRG_AMT_5,
            PRF_PHYSN_NPI_6,  HCPCS_CD_6,  LINE_NCH_PMT_AMT_6,  LINE_ALOWD_CHRG_AMT_6,
            PRF_PHYSN_NPI_7,  HCPCS_CD_7,  LINE_NCH_PMT_AMT_7,  LINE_ALOWD_CHRG_AMT_7,
            PRF_PHYSN_NPI_8,  HCPCS_CD_8,  LINE_NCH_PMT_AMT_8,  LINE_ALOWD_CHRG_AMT_8,
            PRF_PHYSN_NPI_9,  HCPCS_CD_9,  LINE_NCH_PMT_AMT_9,  LINE_ALOWD_CHRG_AMT_9,
            PRF_PHYSN_NPI_10, HCPCS_CD_10, LINE_NCH_PMT_AMT_10, LINE_ALOWD_CHRG_AMT_10,
            PRF_PHYSN_NPI_11, HCPCS_CD_11, LINE_NCH_PMT_AMT_11, LINE_ALOWD_CHRG_AMT_11,
            PRF_PHYSN_NPI_12, HCPCS_CD_12, LINE_NCH_PMT_AMT_12, LINE_ALOWD_CHRG_AMT_12,
            PRF_PHYSN_NPI_13, HCPCS_CD_13, LINE_NCH_PMT_AMT_13, LINE_ALOWD_CHRG_AMT_13
        FROM read_csv_auto(
            '{carrier_path}',
            header=true,
            all_varchar=true
        )
    """)

    row_count = con.execute("SELECT COUNT(*) FROM carrier_lean").fetchone()[0]
    return row_count


def create_views(con: duckdb.DuckDBPyConnection) -> dict:
    """Create views for beneficiary, inpatient, outpatient, and PDE tables.

    Views are lazy — data stays on disk and is read only when queries execute.

    Args:
        con: Active DuckDB connection.

    Returns:
        Dict mapping table name to row count.
    """
    view_defs = {
        'beneficiary': {
            'path': str(DESYNPUF_PATHS['beneficiary'] / '*.csv'),
            'all_varchar': 'false',
        },
        'inpatient': {
            'path': str(DESYNPUF_PATHS['inpatient'] / '*.csv'),
            'all_varchar': 'true',
        },
        'outpatient': {
            'path': str(DESYNPUF_PATHS['outpatient'] / '*.csv'),
            'all_varchar': 'true',
        },
        'pde': {
            'path': str(DESYNPUF_PATHS['pde'] / '*.csv'),
            'all_varchar': 'false',
        },
    }

    row_counts = {}
    for name, cfg in view_defs.items():
        con.execute(f"""
            CREATE VIEW {name} AS
            SELECT *, filename AS _source_file
            FROM read_csv_auto(
                '{cfg['path']}',
                header=true,
                all_varchar={cfg['all_varchar']},
                filename=true
            )
        """)
        row_counts[name] = con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]

    return row_counts


def load_snowflake_export(name: str) -> pd.DataFrame:
    """Load a CSV from data/snowflake_exports/ by its logical name.

    File names follow the convention established during export:
    the SQL query text without the semicolon.

    Args:
        name: Logical name key from config.SNOWFLAKE_EXPORT_FILES.
              e.g. 'zscore_flags', 'billing_metrics', 'peer_stats'

    Returns:
        pandas DataFrame with the export contents.

    Raises:
        FileNotFoundError: If the export CSV doesn't exist on disk.
        KeyError: If the logical name isn't in SNOWFLAKE_EXPORT_FILES.
    """
    if name not in SNOWFLAKE_EXPORT_FILES:
        valid = ', '.join(sorted(SNOWFLAKE_EXPORT_FILES.keys()))
        raise KeyError(f"Unknown export name '{name}'. Valid names: {valid}")

    filename = SNOWFLAKE_EXPORT_FILES[name]
    filepath = SNOWFLAKE_EXPORTS_DIR / filename

    if not filepath.exists():
        raise FileNotFoundError(
            f"Snowflake export not found: {filepath}\n"
            f"Run the corresponding SELECT in Snowsight and download the CSV."
        )

    df = pd.read_csv(filepath)
    # Standardize column names to lowercase
    df.columns = [c.lower() for c in df.columns]
    return df
