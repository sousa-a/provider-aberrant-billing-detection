"""
Tests for src/quality.py — run quality functions on a small fixture CSV.

Run: pytest tests/ -v
"""
import sys
from pathlib import Path

import duckdb
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.quality import (
    compute_completeness,
    check_referential_integrity,
    check_temporal_consistency,
)


def _create_test_connection():
    """Create a DuckDB connection with small test tables."""
    con = duckdb.connect(':memory:')

    # Claims table with known completeness pattern
    con.execute("""
        CREATE TABLE test_claims (
            CLM_ID VARCHAR,
            DESYNPUF_ID VARCHAR,
            CLM_FROM_DT VARCHAR,
            CLM_THRU_DT VARCHAR,
            PROVIDER_NPI VARCHAR,
            HCPCS_CODE VARCHAR,
            PAYMENT_AMT DOUBLE
        )
    """)
    con.execute("""
        INSERT INTO test_claims VALUES
            ('C001', 'B001', '20090115', '20090115', 'P001', '99213', 50.0),
            ('C002', 'B002', '20090220', '20090220', 'P001', '99214', 80.0),
            ('C003', 'B003', '20090310', '20090310', 'P002', '99213', 50.0),
            ('C004', 'B001', '20090415', '20090415', NULL,   '99215', 120.0),
            ('C005', 'B004', '20090520', '20090520', 'P003', NULL,    NULL)
    """)

    # Beneficiary table (B004 has no match in claims for integrity test)
    con.execute("""
        CREATE TABLE test_beneficiary (
            DESYNPUF_ID VARCHAR,
            BENE_BIRTH_DT VARCHAR,
            BENE_DEATH_DT VARCHAR
        )
    """)
    con.execute("""
        INSERT INTO test_beneficiary VALUES
            ('B001', '19400101', NULL),
            ('B002', '19350515', '20090601'),
            ('B003', '19500301', NULL),
            ('B005', '19450101', NULL)
    """)

    return con


class TestComputeCompleteness:
    """Test the single-pass completeness function."""

    def test_returns_dataframe(self):
        con = _create_test_connection()
        result = compute_completeness(con, 'test_claims')
        assert isinstance(result, pd.DataFrame)
        con.close()

    def test_correct_column_count(self):
        con = _create_test_connection()
        result = compute_completeness(con, 'test_claims')
        assert len(result) == 7, f"Expected 7 columns, got {len(result)}"
        con.close()

    def test_total_rows_correct(self):
        con = _create_test_connection()
        result = compute_completeness(con, 'test_claims')
        assert result['total'].iloc[0] == 5
        con.close()

    def test_full_completeness_columns(self):
        con = _create_test_connection()
        result = compute_completeness(con, 'test_claims')
        clm_id_row = result[result['column'] == 'CLM_ID'].iloc[0]
        assert clm_id_row['pct_complete'] == 100.0
        con.close()

    def test_partial_completeness(self):
        con = _create_test_connection()
        result = compute_completeness(con, 'test_claims')
        npi_row = result[result['column'] == 'PROVIDER_NPI'].iloc[0]
        # 4 out of 5 are non-null
        assert npi_row['pct_complete'] == 80.0
        con.close()

    def test_payment_completeness(self):
        con = _create_test_connection()
        result = compute_completeness(con, 'test_claims')
        pmt_row = result[result['column'] == 'PAYMENT_AMT'].iloc[0]
        # 4 out of 5 are non-null
        assert pmt_row['pct_complete'] == 80.0
        con.close()


class TestReferentialIntegrity:
    """Test orphan key detection."""

    def test_finds_orphan_in_claims(self):
        con = _create_test_connection()
        # B004 is in claims but not in beneficiary
        result = check_referential_integrity(
            con, 'test_claims', 'test_beneficiary',
            'DESYNPUF_ID', 'DESYNPUF_ID'
        )
        assert result['orphan_count'] == 1  # B004
        con.close()

    def test_finds_orphan_in_beneficiary(self):
        con = _create_test_connection()
        # B005 is in beneficiary but not in claims
        result = check_referential_integrity(
            con, 'test_beneficiary', 'test_claims',
            'DESYNPUF_ID', 'DESYNPUF_ID'
        )
        assert result['orphan_count'] == 1  # B005
        con.close()

    def test_pass_status_when_no_orphans(self):
        con = _create_test_connection()
        # Check claims against itself — no orphans possible
        result = check_referential_integrity(
            con, 'test_claims', 'test_claims',
            'DESYNPUF_ID', 'DESYNPUF_ID'
        )
        assert result['status'] == '✓ PASS'
        con.close()


class TestTemporalConsistency:
    """Test date violation detection."""

    def test_no_violations_in_range(self):
        con = _create_test_connection()
        result = check_temporal_consistency(
            con, 'test_claims',
            date_from_col='CLM_FROM_DT',
            date_thru_col='CLM_THRU_DT',
            expected_min='2009-01-01',
            expected_max='2009-12-31'
        )
        assert result['date_range_violations'] == 0
        assert result['end_before_start'] == 0
        con.close()

    def test_detects_out_of_range(self):
        con = _create_test_connection()
        # Add a row clearly outside any reasonable range
        con.execute("""
            INSERT INTO test_claims VALUES
                ('C099', 'B001', '20070101', '20070101', 'P001', '99213', 50.0)
        """)
        result = check_temporal_consistency(
            con, 'test_claims',
            date_from_col='CLM_FROM_DT',
            date_thru_col='CLM_THRU_DT',
            expected_min='2008-01-01',
            expected_max='2010-12-31'
        )
        assert result['date_range_violations'] > 0
        con.close()
