#!/usr/bin/env bash
# Claude's SKILL.md substitution requires the braced form (#401).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$HERE/../../../skills" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
skills = sorted(root.glob('*/SKILL.md'))
assert skills, f'No skills found under {root}'
bare = re.compile(r'\$CLAUDE_PLUGIN_ROOT\b')
failures = []
for path in skills:
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if bare.search(line):
            failures.append(f'{path.relative_to(root)}:{number}: use ${{CLAUDE_PLUGIN_ROOT}}')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(skills)} skills use braced plugin-root references')
PY
