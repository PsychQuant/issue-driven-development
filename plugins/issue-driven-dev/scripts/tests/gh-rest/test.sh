#!/usr/bin/env bash
# test.sh — scripts/lib/gh-rest.sh, the REST read helper (#416, change cloud-session-idd-all D3).
#
# A fake gh answers only `gh api <path>` from fixture files keyed by the request path (query string
# included), so every request the helper makes is visible in calls.log and nothing reaches GitHub.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
HELPER="$HERE/../../lib/gh-rest.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
FX="$W/fx"; mkdir -p "$FX"

cat > "$W/fake-gh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/calls.log"
[ "$1" = "api" ] || { echo "fake gh: only api is allowed, got: $*" >&2; exit 99; }
key="$(printf '%s' "$2" | tr '/?&=' '____')"
if [ -f "$FX/$key.err" ]; then cat "$FX/$key.err" >&2; exit "$(cat "$FX/$key.rc" 2>/dev/null || echo 1)"; fi
[ -f "$FX/$key.json" ] && { cat "$FX/$key.json"; exit 0; }
echo "fake gh: no fixture for $2 (key $key)" >&2; exit 98
SHIM
chmod +x "$W/fake-gh"
export IDD_GH_BIN="$W/fake-gh" FX

fx() { printf '%s' "$2" > "$FX/$(printf '%s' "$1" | tr '/?&=' '____').json"; }      # path json
fx_err() { local k; k="$(printf '%s' "$1" | tr '/?&=' '____')"; printf '%s\n' "$2" > "$FX/$k.err"; printf '%s' "${3:-1}" > "$FX/$k.rc"; }
reset() { rm -f "$FX"/*; }
run() { bash "$HELPER" "$@" 2>"$W/err"; }
j() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(eval(sys.argv[1]))' "$1"; }
comments() { # n start count → JSON array of n REST comments
  python3 -c 'import json,sys; s,n=int(sys.argv[1]),int(sys.argv[2]); print(json.dumps([{"id":i,"node_id":"IC_%d"%i,"user":{"login":"u%d"%i},"author_association":"MEMBER","body":"c%d"%i,"created_at":"2026-10-01T00:00:00Z","html_url":"https://x/c%d"%i} for i in range(s,s+n)]))' "$1" "$2"; }

ISSUE9='{"number":9,"title":"T9","state":"open","body":"B9","html_url":"https://github.com/o/r/issues/9","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-02T00:00:00Z","closed_at":null,"user":{"login":"alice"},"labels":[{"name":"bug","color":"x"}],"assignees":[{"login":"bob"}],"milestone":{"title":"M1","number":3,"state":"open"}}'

# ── issue-view: normalised fields ───────────────────────────────────────────
reset; fx "repos/o/r/issues/9" "$ISSUE9"
OUT="$(run issue-view 9 --repo o/r --json number,title,state,body,url,createdAt,closedAt,author,labels,assignees,milestone)"
assert_exit "issue-view exits 0" 0 $?
assert_eq "state is upper-case like gh" "OPEN" "$(printf '%s' "$OUT" | j "d['state']")"
assert_eq "createdAt camelCase" "2026-10-01T00:00:00Z" "$(printf '%s' "$OUT" | j "d['createdAt']")"
assert_eq "closedAt null kept" "None" "$(printf '%s' "$OUT" | j "d['closedAt']")"
assert_eq "author is {login}" "{'login': 'alice'}" "$(printf '%s' "$OUT" | j "d['author']")"
assert_eq "labels are [{name}]" "[{'name': 'bug'}]" "$(printf '%s' "$OUT" | j "d['labels']")"
assert_eq "assignees are [{login}]" "[{'login': 'bob'}]" "$(printf '%s' "$OUT" | j "d['assignees']")"
assert_eq "milestone is {title,number}" "{'title': 'M1', 'number': 3}" "$(printf '%s' "$OUT" | j "d['milestone']")"
assert_eq "url from html_url" "https://github.com/o/r/issues/9" "$(printf '%s' "$OUT" | j "d['url']")"
assert_eq "only requested fields are returned" "11" "$(printf '%s' "$OUT" | j "len(d)")"

# ── issue-view: comments are paged ──────────────────────────────────────────
reset; fx "repos/o/r/issues/9" "$ISSUE9"
fx "repos/o/r/issues/9/comments?per_page=100&page=1" "$(comments 1 100)"
fx "repos/o/r/issues/9/comments?per_page=100&page=2" "$(comments 101 50)"
OUT="$(run issue-view 9 --repo o/r --json comments)"
assert_exit "issue-view comments exits 0" 0 $?
assert_eq "150 comments across two pages" "150" "$(printf '%s' "$OUT" | j "len(d['comments'])")"
assert_eq "comment shape like gh" "{'id': 'IC_101', 'databaseId': 101, 'author': {'login': 'u101'}, 'authorAssociation': 'MEMBER', 'body': 'c101', 'createdAt': '2026-10-01T00:00:00Z', 'url': 'https://x/c101'}" \
  "$(printf '%s' "$OUT" | j "d['comments'][100]")"
refute_grep "no third page requested after a short page" "page=3" "$(cat "$FX/calls.log")"
refute_grep_re "issue body fetch skipped when only comments are asked" '^api repos/o/r/issues/9$' "$(cat "$FX/calls.log")"

# ── issue-view: URL argument carries the repo ───────────────────────────────
reset; fx "repos/o/r/issues/9" "$ISSUE9"
OUT="$(run issue-view https://github.com/o/r/issues/9 --json number)"
assert_eq "issue URL resolves repo and number" "9" "$(printf '%s' "$OUT" | j "d['number']")"

# ── issue-view: no --repo → gh placeholder resolves the current repo ────────
reset; fx "repos/{owner}/{repo}/issues/9" "$ISSUE9"
OUT="$(run issue-view 9 --json title)"
assert_eq "no --repo uses the {owner}/{repo} placeholder" "T9" "$(printf '%s' "$OUT" | j "d['title']")"

# ── issue-list: pull requests are excluded, limit applies ───────────────────
reset
fx "repos/o/r/issues?state=open&per_page=100&page=1" '[{"number":1,"title":"a","state":"open"},{"number":2,"title":"pr","state":"open","pull_request":{"url":"x"}},{"number":3,"title":"c","state":"open"}]'
OUT="$(run issue-list --repo o/r --json number,title)"
assert_eq "issue-list drops pull requests" "[1, 3]" "$(printf '%s' "$OUT" | j "[i['number'] for i in d]")"
OUT="$(run issue-list --repo o/r --limit 1 --json number)"
assert_eq "issue-list honours --limit" "[1]" "$(printf '%s' "$OUT" | j "[i['number'] for i in d]")"
reset; fx "repos/o/r/issues?state=closed&labels=bug,ui&per_page=100&page=1" '[{"number":4,"state":"closed"}]'
OUT="$(run issue-list --repo o/r --state closed --label bug --label ui --json number,state)"
assert_eq "issue-list passes state and labels" "[{'number': 4, 'state': 'CLOSED'}]" "$(printf '%s' "$OUT" | j "d")"
# idd-list's fetch (#416 verify, requirements lens): server-side sort before the limit (#299), full comments
reset
fx "repos/o/r/issues?state=open&sort=updated&direction=desc&per_page=100&page=1" '[{"number":8,"title":"new","state":"open","body":null},{"number":2,"title":"old","state":"open","body":"b"}]'
fx "repos/o/r/issues/8/comments?per_page=100&page=1" "$(comments 1 2)"
fx "repos/o/r/issues/2/comments?per_page=100&page=1" '[]'
OUT="$(run issue-list --repo o/r --sort updated --json number,body,comments)"
assert_exit "issue-list --sort updated with comments exits 0" 0 $?
assert_eq "server-side order kept, comments attached per issue" "[(8, 2), (2, 0)]" "$(printf '%s' "$OUT" | j "[(i['number'], len(i['comments'])) for i in d]")"
assert_eq "an empty body is \"\" like gh, not null" "''" "$(printf '%s' "$OUT" | j "repr(d[0]['body'])")"
run issue-list --repo o/r --sort bogus --json number >/dev/null; assert_exit "unknown --sort → exit 2" 2 $?
# a fetched number goes into the comments path: it must be an integer, or the whole read fails (no partial rows)
reset
fx "repos/o/r/issues?state=open&per_page=100&page=1" '[{"number":"4245 --hostname evil.example","state":"open"}]'
run issue-list --repo o/r --json number,comments >/dev/null; assert_exit "non-numeric fetched number → exit 1" 1 $?
refute_grep "…and it never reaches an api path" "4245" "$(cat "$FX/calls.log")"

# an absurdly long issue number is a usage error, not a ValueError crash (int() refuses 4300+ digits)
run issue-view "$(printf '9%.0s' $(seq 1 5000))" --repo o/r --json number >/dev/null 2>&1; assert_exit "a 5000-digit issue number → exit 2" 2 $?

# --closed-since (check-closed-without-summary's audit): REST `since` narrows by update time, the filter keeps
# issues CLOSED on/after the date, and --limit counts kept issues (not the raw page)
reset
fx "repos/o/r/issues?state=closed&since=2026-01-01T00:00:00Z&per_page=100&page=1" '[{"number":5,"state":"closed","closed_at":"2026-02-01T00:00:00Z"},{"number":4,"state":"closed","closed_at":"2025-12-30T00:00:00Z"},{"number":3,"state":"closed","closed_at":"2026-01-01T09:00:00Z"}]'
OUT="$(run issue-list --repo o/r --state closed --closed-since 2026-01-01 --limit 2 --json number,closedAt)"
assert_eq "--closed-since keeps issues closed on/after the date, limit after the filter" "[5, 3]" "$(printf '%s' "$OUT" | j "[i['number'] for i in d]")"
run issue-list --repo o/r --state closed --closed-since 'yesterday' --json number >/dev/null; assert_exit "--closed-since needs a date (exit 2)" 2 $?
run issue-list --repo o/r --state closed --closed-since 2026-02-30 --json number >/dev/null; assert_exit "--closed-since rejects an impossible date (exit 2)" 2 $?
# what search's `closed:>=` accepted still works: a single-digit date, and an offset timestamp (normalised to UTC Z,
# the form closed_at uses — otherwise the string compare in the filter is wrong)
reset
fx "repos/o/r/issues?state=closed&since=2026-01-05T00:00:00Z&per_page=100&page=1" '[{"number":7,"state":"closed","closed_at":"2026-01-05T00:00:00Z"}]'
OUT="$(run issue-list --repo o/r --state closed --closed-since 2026-1-5 --json number)"
assert_eq "--closed-since YYYY-M-D is zero-padded" "[7]" "$(printf '%s' "$OUT" | j "[i['number'] for i in d]")"
reset
fx "repos/o/r/issues?state=closed&since=2026-01-01T00:00:00Z&per_page=100&page=1" '[{"number":8,"state":"closed","closed_at":"2026-01-01T00:30:00Z"},{"number":6,"state":"closed","closed_at":"2025-12-31T23:59:00Z"}]'
OUT="$(run issue-list --repo o/r --state closed --closed-since 2026-01-01T08:00:00+08:00 --json number)"
assert_eq "--closed-since with an offset compares in UTC" "[8]" "$(printf '%s' "$OUT" | j "[i['number'] for i in d]")"

# ── pr-list ─────────────────────────────────────────────────────────────────
PRS='[{"number":3,"title":"m","body":"Refs #9","state":"closed","html_url":"https://x/pull/3","created_at":"2026-10-03T00:00:00Z","updated_at":"u","closed_at":"c","merged_at":"2026-10-04T00:00:00Z","head":{"ref":"idd/9-x","sha":"abc"},"base":{"ref":"main"},"draft":false,"user":{"login":"alice"}},
      {"number":4,"title":"n","body":null,"state":"closed","html_url":"https://x/pull/4","created_at":"2026-10-03T00:00:00Z","updated_at":"u","closed_at":"c","merged_at":null,"head":{"ref":"x","sha":"def"},"base":{"ref":"main"},"draft":true,"user":{"login":"bob"}}]'
reset; fx "repos/o/r/pulls?state=closed&per_page=100&page=1" "$PRS"
OUT="$(run pr-list --repo o/r --state merged --json number,state,mergedAt,headRefName,headRefOid,baseRefName,createdAt,url,body)"
assert_exit "pr-list exits 0" 0 $?
assert_eq "merged = closed with merged_at" "[3]" "$(printf '%s' "$OUT" | j "[p['number'] for p in d]")"
assert_eq "merged state label" "MERGED" "$(printf '%s' "$OUT" | j "d[0]['state']")"
assert_eq "head ref/sha/base normalised" "idd/9-x abc main" "$(printf '%s' "$OUT" | j "' '.join([d[0]['headRefName'],d[0]['headRefOid'],d[0]['baseRefName']])")"
OUT="$(run pr-list --repo o/r --state closed --json number,state,isDraft)"
assert_eq "closed includes merged (gh semantics)" "[(3, 'MERGED', False), (4, 'CLOSED', True)]" "$(printf '%s' "$OUT" | j "[(p['number'],p['state'],p['isDraft']) for p in d]")"
reset; fx "repos/o/r/pulls?state=open&per_page=100&page=1" '[{"number":7,"state":"open","merged_at":null,"head":{"ref":"a","sha":"1"},"base":{"ref":"main"}}]'
OUT="$(run pr-list --repo o/r --json number,state)"
assert_eq "pr-list defaults to open" "[{'number': 7, 'state': 'OPEN'}]" "$(printf '%s' "$OUT" | j "d")"

# mergeable needs the single-PR endpoint (the list endpoint does not carry it)
reset; fx "repos/o/r/pulls?state=open&per_page=100&page=1" '[{"number":7,"state":"open","merged_at":null,"head":{"ref":"a","sha":"1"},"base":{"ref":"main"}},{"number":9,"state":"open","merged_at":null,"head":{"ref":"b","sha":"2"},"base":{"ref":"main"}}]'
fx "repos/o/r/pulls/7" '{"number":7,"mergeable":false}'
fx "repos/o/r/pulls/9" '{"number":9,"mergeable":null}'
OUT="$(run pr-list --repo o/r --json number,mergeable)"
assert_eq "mergeable mapped like gh (false → CONFLICTING, null → UNKNOWN)" "[(7, 'CONFLICTING'), (9, 'UNKNOWN')]" "$(printf '%s' "$OUT" | j "[(p['number'], p['mergeable']) for p in d]")"
fx "repos/o/r/pulls/9" '{"number":9,"mergeable":true}'
assert_eq "mergeable true → MERGEABLE" "MERGEABLE" "$(run pr-list --repo o/r --json number,mergeable | j "d[1]['mergeable']")"
reset; fx "repos/o/r/pulls?state=open&per_page=100&page=1" '[{"number":7,"state":"open","merged_at":null,"body":null,"head":{"ref":"a","sha":"1"},"base":{"ref":"main"}}]'
OUT="$(run pr-list --repo o/r --json number,body)"
refute_grep "no single-PR fetch unless mergeable is asked" "pulls/7" "$(cat "$FX/calls.log")"
assert_eq "an empty PR body is \"\" like gh" "''" "$(printf '%s' "$OUT" | j "repr(d[0]['body'])")"

# pr-list paging stops at --limit without requesting further pages
reset
python3 -c 'import json; print(json.dumps([{"number":i,"state":"open","merged_at":None,"head":{"ref":"b","sha":"s"},"base":{"ref":"main"}} for i in range(1,101)]))' > "$FX/repos_o_r_pulls_state_open_per_page_100_page_1.json"
OUT="$(run pr-list --repo o/r --limit 100 --json number)"
assert_eq "limit 100 filled from one page" "100" "$(printf '%s' "$OUT" | j "len(d)")"
refute_grep "no page 2 once the limit is reached" "page=2" "$(cat "$FX/calls.log")"

# ── repo-view ───────────────────────────────────────────────────────────────
reset; fx "repos/o/r" '{"full_name":"o/r","default_branch":"main","fork":false,"visibility":"public","html_url":"https://github.com/o/r","permissions":{"admin":false,"maintain":false,"push":true,"triage":true,"pull":true}}'
OUT="$(run repo-view --repo o/r --json nameWithOwner,defaultBranchRef,isFork,visibility,url,viewerPermission)"
assert_eq "repo-view normalised" "o/r {'name': 'main'} False PUBLIC WRITE" \
  "$(printf '%s' "$OUT" | j "' '.join(map(str,[d['nameWithOwner'],d['defaultBranchRef'],d['isFork'],d['visibility'],d['viewerPermission']]))")"

# ── usage errors ────────────────────────────────────────────────────────────
run repo-view --repo o/r --json stargazerCount >/dev/null; assert_exit "unknown field → exit 2" 2 $?
assert_grep "unknown field lists accepted fields" "nameWithOwner" "$(cat "$W/err")"
run repo-view --repo o/r >/dev/null; assert_exit "missing --json → exit 2" 2 $?
run issue-create --repo o/r --json number >/dev/null; assert_exit "no write subcommands (unknown subcommand → exit 2)" 2 $?
run issue-view --repo o/r --json number >/dev/null; assert_exit "issue-view without an issue → exit 2" 2 $?

# ── failures and hints ──────────────────────────────────────────────────────
reset; fx_err "repos/x/y/issues/1" 'gh: GitHub access to this repository is not enabled for this session. Use add_repo to request access. (HTTP 403)'
run issue-view 1 --repo x/y --json title >/dev/null; assert_exit "cloud-blocked repo → exit 1" 1 $?
assert_grep "error line names the failed action" "gh-rest: issue-view" "$(cat "$W/err")"
assert_grep "hint tells the user to attach the repo" "hint: this cloud session cannot reach x/y" "$(cat "$W/err")"
reset; fx_err "repos/o/r/issues/404" 'gh: Not Found (HTTP 404)'
run issue-view 404 --repo o/r --json title >/dev/null; assert_exit "404 → exit 1" 1 $?
assert_grep "404 hint" "hint: o/r#404 does not exist, or this token cannot see it" "$(cat "$W/err")"
reset; fx "repos/o/r" 'not json'
run repo-view --repo o/r --json url >/dev/null; assert_exit "unparseable output → exit 1" 1 $?

print_summary "gh-rest (#416)"
