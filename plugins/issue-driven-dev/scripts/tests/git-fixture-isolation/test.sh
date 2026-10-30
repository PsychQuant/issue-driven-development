#!/usr/bin/env bash
# The Python harness creates its own disposable caller; never uses the real one.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/test_isolation.py"
