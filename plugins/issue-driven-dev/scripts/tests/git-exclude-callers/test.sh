#!/usr/bin/env bash
# Execute the actual skill snippets against isolated Git fixtures (#446).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/test.py"
