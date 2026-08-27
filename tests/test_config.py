"""
Tests for src/config.py — verify paths exist and constants are valid.

Run: pytest tests/ -v
"""
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import (
    DESYNPUF_BASE, DESYNPUF_PATHS, PROJECT_ROOT,
    SNOWFLAKE_EXPORTS_DIR, FIGURES_DIR, OUTPUT_DIR,
    MIN_CLAIMS, MIN_PEER_GROUP_SIZE,
    Z_THRESHOLD_PRIMARY, Z_THRESHOLD_SEVERE,
    EXPECTED_ROWS, ZSCORE_METRICS, CHRONIC_CONDITION_COLS,
    CARRIER_LINE_GROUPS, COMPOSITE_WEIGHTS,
)


class TestPaths:
    """Verify that configured paths exist on disk."""

    def test_project_root_exists(self):
        assert PROJECT_ROOT.is_dir(), f"PROJECT_ROOT not found: {PROJECT_ROOT}"

    def test_src_dir_exists(self):
        assert (PROJECT_ROOT / 'src').is_dir(), "src/ directory missing"

    def test_desynpuf_base_exists(self):
        assert DESYNPUF_BASE.is_dir(), (
            f"DE-SynPUF base directory not found: {DESYNPUF_BASE}\n"
            f"Download from CMS and update DESYNPUF_BASE in src/config.py"
        )

    def test_all_desynpuf_subdirs_exist(self):
        for name, path in DESYNPUF_PATHS.items():
            assert path.is_dir(), f"Missing subdirectory: {name} → {path}"

    def test_desynpuf_subdirs_have_csv_files(self):
        for name, path in DESYNPUF_PATHS.items():
            csv_count = len(list(path.glob('*.csv')))
            assert csv_count > 0, f"No CSV files in {name}: {path}"

    def test_output_dirs_creatable(self):
        FIGURES_DIR.mkdir(parents=True, exist_ok=True)
        assert FIGURES_DIR.is_dir()


class TestConstants:
    """Verify that analytical constants are within valid ranges."""

    def test_min_claims_positive(self):
        assert MIN_CLAIMS > 0, f"MIN_CLAIMS must be positive, got {MIN_CLAIMS}"

    def test_min_peer_group_positive(self):
        assert MIN_PEER_GROUP_SIZE >= 2, f"MIN_PEER_GROUP_SIZE too small: {MIN_PEER_GROUP_SIZE}"

    def test_z_thresholds_ordered(self):
        assert Z_THRESHOLD_PRIMARY < Z_THRESHOLD_SEVERE, (
            f"Primary threshold ({Z_THRESHOLD_PRIMARY}) must be < "
            f"severe threshold ({Z_THRESHOLD_SEVERE})"
        )

    def test_z_thresholds_reasonable(self):
        assert 1.0 <= Z_THRESHOLD_PRIMARY <= 3.0
        assert 2.0 <= Z_THRESHOLD_SEVERE <= 5.0

    def test_composite_weights_sum_to_one(self):
        total = sum(COMPOSITE_WEIGHTS.values())
        assert abs(total - 1.0) < 0.001, f"Composite weights sum to {total}, expected 1.0"

    def test_expected_rows_all_positive(self):
        for table, count in EXPECTED_ROWS.items():
            assert count > 0, f"Expected rows for {table} must be positive"

    def test_zscore_metrics_nonempty(self):
        assert len(ZSCORE_METRICS) >= 3, "Need at least 3 metrics for meaningful z-scores"

    def test_chronic_conditions_count(self):
        assert len(CHRONIC_CONDITION_COLS) == 11, (
            f"Expected 11 chronic conditions (per DE-SynPUF codebook), got {len(CHRONIC_CONDITION_COLS)}"
        )

    def test_carrier_line_groups_have_13_items(self):
        for group_name, cols in CARRIER_LINE_GROUPS.items():
            assert len(cols) == 13, (
                f"CARRIER_LINE_GROUPS['{group_name}'] has {len(cols)} items, expected 13"
            )
