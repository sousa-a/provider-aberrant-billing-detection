"""
P3 — Provider Aberrant Billing Pattern Detection
quality.py — Data quality assessment utilities.

Reusable functions for completeness checks, referential integrity,
and temporal consistency. Used in NB01 and for cross-validation
against Snowflake DATA_QUALITY views.

Usage:
    from src.quality import compute_completeness, check_referential_integrity
"""

import pandas as pd
import duckdb


def compute_completeness(con: duckdb.DuckDBPyConnection,
                         table_name: str,
                         exclude_prefixes: tuple = ('_', 'filename')) -> pd.DataFrame:
    """Compute % NOT NULL for every column in a table — single SQL pass.

    Instead of running one COUNT(col) query per column (N full scans),
    this builds a single SELECT with all COUNT(col) expressions and
    executes it in one pass.

    Args:
        con:              Active DuckDB connection.
        table_name:       Name of the table or view to profile.
        exclude_prefixes: Column name prefixes to skip (metadata columns).

    Returns:
        DataFrame with columns: column, non_null, total, pct_complete, pct_missing.
    """
    # Get column names
    all_cols = [desc[0] for desc in con.execute(f"SELECT * FROM {table_name} LIMIT 0").description]
    cols = [c for c in all_cols if not any(c.startswith(p) for p in exclude_prefixes)]

    # Build single-pass query
    count_exprs = ',\n    '.join(f"COUNT({col}) AS n_{col.lower()}" for col in cols)
    query = f"SELECT COUNT(*) AS total_rows,\n    {count_exprs}\nFROM {table_name}"

    result = con.execute(query).fetchdf()
    total_rows = int(result['total_rows'].iloc[0])

    rows = []
    for col in cols:
        non_null = int(result[f'n_{col.lower()}'].iloc[0])
        rows.append({
            'column':       col,
            'non_null':     non_null,
            'total':        total_rows,
            'pct_complete': round(non_null / total_rows * 100, 2) if total_rows > 0 else 0,
            'pct_missing':  round((1 - non_null / total_rows) * 100, 2) if total_rows > 0 else 100,
        })

    return pd.DataFrame(rows)


def print_completeness_tiers(df_completeness: pd.DataFrame, max_per_tier: int = 15):
    """Print completeness results grouped by quality tier.

    Args:
        df_completeness: Output of compute_completeness().
        max_per_tier:    Max columns to show per tier before truncating.
    """
    tiers = [
        ('100% complete',    df_completeness[df_completeness['pct_complete'] == 100]),
        ('90-99%',           df_completeness[(df_completeness['pct_complete'] >= 90) & (df_completeness['pct_complete'] < 100)]),
        ('50-89%',           df_completeness[(df_completeness['pct_complete'] >= 50) & (df_completeness['pct_complete'] < 90)]),
        ('<50% (sparse)',    df_completeness[df_completeness['pct_complete'] < 50]),
    ]

    total_cols = len(df_completeness)
    print(f"Completeness summary ({total_cols} columns):")
    print("=" * 60)
    for tier_name, tier_df in tiers:
        print(f"\n  {tier_name}: {len(tier_df)} columns")
        for _, r in tier_df.head(max_per_tier).iterrows():
            print(f"    {r['column']:40s} {r['pct_complete']:6.2f}%")
        if len(tier_df) > max_per_tier:
            print(f"    ... and {len(tier_df) - max_per_tier} more")


def check_referential_integrity(con: duckdb.DuckDBPyConnection,
                                 left_table: str, right_table: str,
                                 left_key: str, right_key: str,
                                 description: str = "") -> dict:
    """Check for orphan keys between two tables.

    Counts distinct values in left_table.left_key that have no
    matching value in right_table.right_key.

    Args:
        con:          Active DuckDB connection.
        left_table:   Table containing the foreign key.
        right_table:  Table containing the primary key.
        left_key:     Column name in left_table.
        right_key:    Column name in right_table.
        description:  Human-readable description of the check.

    Returns:
        Dict with keys: check, orphan_count, total, pct, status.
    """
    result = con.execute(f"""
        SELECT
            COUNT(DISTINCT l.{left_key}) AS orphan_count,
            (SELECT COUNT(DISTINCT {left_key}) FROM {left_table}) AS total
        FROM {left_table} l
        WHERE NOT EXISTS (
            SELECT 1 FROM {right_table} r WHERE r.{right_key} = l.{left_key}
        )
    """).fetchdf()

    orphan_count = int(result['orphan_count'].iloc[0])
    total = int(result['total'].iloc[0])
    pct = round(orphan_count / total * 100, 4) if total > 0 else 0

    return {
        'check':        description or f"{left_table}.{left_key} → {right_table}.{right_key}",
        'orphan_count': orphan_count,
        'total':        total,
        'pct':          pct,
        'status':       '✓ PASS' if orphan_count == 0 else '⚠ WARN',
    }


def check_temporal_consistency(con: duckdb.DuckDBPyConnection,
                                table_name: str,
                                date_from_col: str = 'CLM_FROM_DT',
                                date_thru_col: str = 'CLM_THRU_DT',
                                expected_min: str = '2008-01-01',
                                expected_max: str = '2010-12-31') -> dict:
    """Check for temporal violations in a claims table.

    Args:
        con:            Active DuckDB connection.
        table_name:     Table to check.
        date_from_col:  Column with service start date.
        date_thru_col:  Column with service end date.
        expected_min:   Earliest acceptable date (YYYY-MM-DD).
        expected_max:   Latest acceptable date (YYYY-MM-DD).

    Returns:
        Dict with violation counts.
    """
    date_cast = (
        f"COALESCE(TRY_CAST({date_from_col} AS DATE), "
        f"TRY_STRPTIME({date_from_col}, '%Y%m%d')::DATE)"
    )
    date_thru_cast = (
        f"COALESCE(TRY_CAST({date_thru_col} AS DATE), "
        f"TRY_STRPTIME({date_thru_col}, '%Y%m%d')::DATE)"
    )

    result = con.execute(f"""
        SELECT
            COUNT(*) AS total_rows,
            SUM(CASE WHEN {date_cast} < DATE '{expected_min}'
                       OR {date_cast} > DATE '{expected_max}'
                     THEN 1 ELSE 0 END) AS date_range_violations,
            SUM(CASE WHEN {date_thru_cast} < {date_cast}
                     THEN 1 ELSE 0 END) AS end_before_start
        FROM {table_name}
        WHERE {date_from_col} IS NOT NULL
    """).fetchdf()

    r = result.iloc[0]
    total = int(r['total_rows'])

    return {
        'total_rows':            total,
        'date_range_violations': int(r['date_range_violations']),
        'end_before_start':      int(r['end_before_start']),
        'pct_range':             round(r['date_range_violations'] / total * 100, 4) if total > 0 else 0,
        'pct_end_before_start':  round(r['end_before_start'] / total * 100, 4) if total > 0 else 0,
    }
