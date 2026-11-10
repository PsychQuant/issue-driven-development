#!/usr/bin/env bash
# close-stage suite (#392): the scenarios live in scenarios.sh; run_parallel.py runs them concurrently.
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_parallel.py"
