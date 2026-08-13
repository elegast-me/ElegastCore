#!/usr/bin/env bash
# Run all tooling unit tests. Exits non-zero on any failure.
#
#   tools/tests/run.sh
#
# Tests that need optional dependencies (liblua5.4) skip rather than fail, so
# a fresh checkout still reports cleanly.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
exec python3 -m unittest discover -s tools/tests -p "test_*.py" -v
