#!/usr/bin/env bash
# test.sh — fixture suite for check-diagnosis-readiness.sh detection logic
# (#61 — verify follow-up from #53; regex contract refined in #64/#65).
# Locks the DOCUMENTED behavior verbatim, including the acknowledged fenced-
# quote false-positive (#65 known limitation — changing it must flip a test
# deliberately, not silently).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../check-diagnosis-readiness.sh"
. "$HERE/../../lib/assert-helpers.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# hermetic gh shim: per-issue comment body from fixture files
mkdir -p "$W/bin" "$W/bodies"
cat > "$W/bin/gh" <<'SHIM'
#!/usr/bin/env bash
# expects: gh issue view <N> -R <repo> --json comments
n="$3"
body_file="$FIXTURE_BODIES/$n.txt"
if [ ! -f "$body_file" ]; then echo "not found" >&2; exit 1; fi
python3 - "$body_file" <<'PY'
import json,sys
print(json.dumps({"comments":[{"body":open(sys.argv[1]).read()}]}))
PY
SHIM
chmod +x "$W/bin/gh"
export FIXTURE_BODIES="$W/bodies"

run() { PATH="$W/bin:$PATH" bash "$SCRIPT" test/repo "$@" 2>/dev/null; }

# fixture matrix（#61 requested shapes; expected per documented contract）
printf '## Diagnosis\n\nroot cause...\n'                     > "$W/bodies/1.txt"   # canonical → ready
printf 'He said "## Diagnosis is required" somewhere.\n'     > "$W/bodies/2.txt"   # inline-quoted → NOT
printf '   ## Diagnosis\nindent-3 heading\n'                 > "$W/bodies/3.txt"   # 3-space (CommonMark heading) → ready
printf '    ## Diagnosis\nindent-4 = code block\n'           > "$W/bodies/4.txt"   # 4-space → NOT
printf '> ## Diagnosis\nblockquoted\n'                       > "$W/bodies/5.txt"   # blockquote prefix → NOT
printf '```\n## Diagnosis\n```\nexample only\n'              > "$W/bodies/6.txt"   # fenced quote → documented FALSE-POSITIVE (ready)
printf '\t## Diagnosis\ntab indent\n'                        > "$W/bodies/7.txt"   # tab → NOT
printf 'no diagnosis at all\n'                               > "$W/bodies/8.txt"   # none → NOT

OUT=$(run 1 2 3 4 5 6 7 8)
assert_grep  "canonical(1) → ready"                    '"ready":[' "$OUT"
python3 - "$OUT" <<'PY' && r=0 || r=1
import json,sys
d=json.loads(sys.argv[1])
assert sorted(d["ready"])==[1,3,6], d
assert sorted(d["not_ready"])==[2,4,5,7,8], d
PY
assert_exit "8-shape 矩陣分類完全符合文件化契約（含 #65 已知 fenced 誤陽）" 0 $r

# empty-comments issue → not_ready
printf '' > "$W/bodies/9.txt"
OUT=$(run 9)
python3 - "$OUT" <<'PY' && r=0 || r=1
import json,sys; d=json.loads(sys.argv[1]); assert d["not_ready"]==[9] and d["ready"]==[]
PY
assert_exit "空 body → not_ready" 0 $r

# gh failure → exit 1
PATH="$W/bin:$PATH" bash "$SCRIPT" test/repo 404 >/dev/null 2>&1
assert_exit "gh 失敗 → exit 1" 1 $?

print_summary "check-diagnosis-readiness"
