#!/usr/bin/env bash
# test.sh — #220 doc-sync sweep 的機械枚舉契約（防 glob-miss incident 重演）
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
git -C "$W" init -q; git -C "$W" config user.email t@t.t; git -C "$W" config user.name t
touch "$W/README.md" "$W/README_zh-TW.md" "$W/readme.markdown" "$W/CLAUDE.md" "$W/docs/x" 2>/dev/null
mkdir -p "$W/plugins/p"; touch "$W/plugins/p/CLAUDE.md" "$W/plugins/p/README.md" "$W/NOTREADME.txt" "$W/build-readme-gen.js"
( cd "$W" && git add -A && git commit -qm x )

ENUM='(^|/)(readme[^/]*\.(md|markdown)|claude\.md)$'
GOT=$(git -C "$W" ls-files | grep -icE "$ENUM")
assert_eq "枚舉命中 6 份 doc（含 zh-TW 變體與 plugin 層）" "6" "$GOT"
git -C "$W" ls-files | grep -iE "$ENUM" > "$W/hits"
assert_grep "README_zh-TW.md 命中（incident 形狀）" "README_zh-TW.md" "$(cat "$W/hits")"
assert_grep "plugin 層 CLAUDE.md 命中" "plugins/p/CLAUDE.md" "$(cat "$W/hits")"
refute_grep "非 doc 檔不誤中" "NOTREADME.txt" "$(cat "$W/hits")"
refute_grep "readme-字根的程式檔不誤中" "build-readme-gen.js" "$(cat "$W/hits")"

# SKILL.md drift-lock：Step 6.3 與枚舉 regex 存在
SKILL="$HERE/../../../skills/idd-close/SKILL.md"
assert_grep "SKILL.md 含 Step 6.3 doc-sync sweep" "Step 6.3: Doc-sync sweep" "$(cat "$SKILL")"
assert_grep "SKILL.md 含 task list 項 doc_sync_sweep" 'name="doc_sync_sweep"' "$(cat "$SKILL")"

# ── Where the sweep sits in idd-close (#512) ──
# spec-example: idd-close-doc-sync / where the doc-sync sweep sits in idd-close
# SKILL.md says where Step 6.3 sits in three places: the order of the step sections, the order of the
# Step 0.5 task list, and the 「位置」 sentence of Step 6.3. pos.py reads a SKILL.md and prints one line
# per disagreement, `<kind>: <what>` with kind = sentence | order | tasks, or `ok`. The step order and
# the task order were already right when the sentence was wrong, so each kind is also run against a
# copy broken on purpose: a check that cannot fail shows nothing.
cat > "$W/pos.py" <<'PY'
import re
import sys

OLD_SENTENCE = "**位置**：closing summary 已 publish、`gh issue close` 之前（與 Step 6 body sync 同區、序在 6.5 distribution sync 前）。"
SILENT_SENTENCE = "**位置**：closing summary 已貼出之後、Step 6.5 distribution sync 之前。"
TASKS = ["publish_and_close", "auto_update_body", "doc_sync_sweep", "distribution_sync_chain_detection"]
# "before the close": a word for closing, then at most ten characters of the same clause, then 前.
BEFORE_CLOSE = re.compile(
    r"(gh issue close|關閉|結案|\bclosed?\b)[^，。；、：（()後]{0,10}(之前|以前|前)"
    r"|before[^,.;:()]{0,40}(gh issue close|\bclosed?\b|\bclosing the issue\b)", re.I)
SAYS_CLOSED = re.compile(r"已關閉|已經關閉|已經關了|關閉之後|關閉後|關閉以後|after[^,.;:()]{0,40}\bclosed\b", re.I)


def kinds(lines):
    """text / code / fence per line; a fence closes only on a run of backticks at least as long."""
    out, infence, n = [], False, 0
    for line in lines:
        s = line.lstrip()
        m = re.match(r"`{3,}", s)
        if m and not infence:
            infence, n = True, len(m.group(0)); out.append("fence"); continue
        if m and infence and len(m.group(0)) >= n and s[len(m.group(0)):].strip() == "":
            infence = False; out.append("fence"); continue
        out.append("code" if infence else "text")
    return out


def headings(lines, kind, step):
    return [i for i, l in enumerate(lines) if kind[i] == "text" and l.startswith("### Step %s:" % step)]


def section(lines, kind, start):
    """[start, end): from a step heading to the next step heading or h2 outside a fence."""
    for i in range(start + 1, len(lines)):
        if kind[i] == "text" and (lines[i].startswith("### Step ") or lines[i].startswith("## ")):
            return start, i
    return start, len(lines)


def check(lines):
    kind = kinds(lines)
    why = []
    at = {}
    for step in ("0.5", "4", "6", "6.3", "6.5"):
        found = headings(lines, kind, step)
        if len(found) != 1:
            why.append(("tasks" if step == "0.5" else "order", 'expected one "### Step %s:" heading, found %d' % (step, len(found))))
        else:
            at[step] = found[0]
    if all(k in at for k in ("4", "6", "6.3", "6.5")):
        a, b = section(lines, kind, at["4"])
        closes = [i for i in range(a, b) if kind[i] == "code" and lines[i].startswith("gh issue close ")]
        if not closes:
            why.append(("order", "Step 4 has no `gh issue close` command line"))
        elif not closes[-1] < at["6.3"]:
            why.append(("order", "Step 6.3 comes before the command that closes the issue"))
        if not at["4"] < at["6"] < at["6.3"] < at["6.5"]:
            why.append(("order", "the sections are not in the order Step 4, Step 6, Step 6.3, Step 6.5"))
    if "0.5" in at:
        a, b = section(lines, kind, at["0.5"])
        names = [m.group(1) for i in range(a, b) for m in [re.match(r'TaskCreate\(name="([A-Za-z_]+)"', lines[i])] if m]
        where = []
        for t in TASKS:
            if names.count(t) != 1:
                why.append(("tasks", "%s is listed %d times in the Step 0.5 task list" % (t, names.count(t))))
            else:
                where.append(names.index(t))
        if len(where) == len(TASKS) and where != sorted(where):
            why.append(("tasks", "the task list is not in the order " + ", ".join(TASKS)))
    if "6.3" in at:
        a, b = section(lines, kind, at["6.3"])
        sent = [lines[i] for i in range(a, b) if kind[i] == "text" and lines[i].startswith("**位置**")]
        if len(sent) != 1:
            why.append(("sentence", "Step 6.3 has %d position sentences, expected one" % len(sent)))
        else:
            if BEFORE_CLOSE.search(sent[0]):
                why.append(("sentence", "the position sentence says the sweep comes before the issue is closed"))
            if not SAYS_CLOSED.search(sent[0]):
                why.append(("sentence", "the position sentence does not say the issue is already closed"))
    return why


def move(lines, a, b, to):
    """Move lines[a:b] so that they start where line `to` (an index outside [a, b)) was."""
    block, rest = lines[a:b], lines[:a] + lines[b:]
    to = to - (b - a) if to >= b else to
    return rest[:to] + block + rest[to:]


def mutate(what, lines):
    kind = kinds(lines)
    one = lambda step: headings(lines, kind, step)[0]
    a, b = section(lines, kind, one("6.3"))
    put = {"says-before": [OLD_SENTENCE], "silent-on-close": [SILENT_SENTENCE], "no-sentence": []}
    if what in put:
        hits = [i for i in range(a, b) if kind[i] == "text" and lines[i].startswith("**位置**")]
        i = hits[0]
        return lines[:i] + put[what] + lines[i + 1:]
    if what == "before-step-4":
        return move(lines, a, b, one("4"))
    if what == "after-step-6.5":
        return move(lines, a, b, section(lines, kind, one("6.5"))[1])
    task = lambda name: [i for i, l in enumerate(lines) if l.startswith('TaskCreate(name="%s"' % name)][0]
    d = task("doc_sync_sweep")
    if what == "task-before-publish":
        return move(lines, d, d + 1, task("publish_and_close"))
    if what == "task-after-distribution":
        return move(lines, d, d + 1, task("distribution_sync_chain_detection") + 1)
    raise SystemExit("unknown mutation: " + what)


def main():
    lines = open(sys.argv[2], encoding="utf-8").read().split("\n")
    if sys.argv[1] == "check":
        why = check(lines)
        print("\n".join("%s: %s" % w for w in why) if why else "ok")
        return 1 if why else 0
    new = mutate(sys.argv[3], lines)
    if new == lines:
        raise SystemExit("mutation %s left the file as it was" % sys.argv[3])
    open(sys.argv[4], "w", encoding="utf-8").write("\n".join(new))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (IndexError, OSError) as e:
        print("error: %s" % e, file=sys.stderr)
        sys.exit(2)
PY

# position_verdict FILE → ok | the kinds of disagreement found, sorted and joined with + | error
position_verdict() {
  local out rc
  out=$(python3 "$W/pos.py" check "$1" 2>/dev/null); rc=$?
  case "$rc" in
    0) [ "$out" = ok ] && echo ok || echo error ;;
    1) printf '%s\n' "$out" | cut -d: -f1 | sort -u | paste -sd+ - ;;
    *) echo error ;;
  esac
}
# broken_verdict WHAT → the verdict on a copy of the shipped SKILL.md broken in one way; not-built when
# the copy could not be made or is the same as the shipped file
broken_verdict() {
  python3 "$W/pos.py" mutate "$SKILL" "$1" "$W/skill-$1.md" 2>/dev/null || { echo not-built; return; }
  position_verdict "$W/skill-$1.md"
}

assert_eq "現行的 SKILL.md：步驟順序、清單、「位置」那一句一致" "ok" "$(position_verdict "$SKILL")"
assert_eq "「位置」那一句說在 gh issue close 之前 → 抓到的是那一句" "sentence" "$(broken_verdict says-before)"
assert_eq "「位置」那一句沒說 issue 已經關閉 → 抓到的是那一句" "sentence" "$(broken_verdict silent-on-close)"
assert_eq "Step 6.3 沒有「位置」那一句 → 抓到的是那一句" "sentence" "$(broken_verdict no-sentence)"
assert_eq "Step 6.3 移到 Step 4 之前 → 抓到的是步驟順序" "order" "$(broken_verdict before-step-4)"
assert_eq "Step 6.3 移到 Step 6.5 之後 → 抓到的是步驟順序" "order" "$(broken_verdict after-step-6.5)"
assert_eq "清單裡 doc_sync_sweep 排在 publish_and_close 之前 → 抓到的是清單" "tasks" "$(broken_verdict task-before-publish)"
assert_eq "清單裡 doc_sync_sweep 排在 distribution_sync_chain_detection 之後 → 抓到的是清單" "tasks" "$(broken_verdict task-after-distribution)"

print_summary "doc-sync-sweep"
