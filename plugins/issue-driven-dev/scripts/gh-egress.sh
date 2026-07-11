#!/usr/bin/env bash
# gh-egress.sh — the single deterministic choke-point wrapper for GitHub issue
# egress (PsychQuant/issue-driven-development#202, openspec change
# add-privacy-scrubbing-gate, design D2).
#
# WHY THIS EXISTS
#   Every IDD skill dispatches AI-drafted issue bodies to GitHub via
#   `gh issue create|comment|edit`. Past the egress boundary the content is
#   public / notified / unrecoverable. Detection of private identifiers is an
#   LLM SEMANTIC self-review (design D1 — no regex denylist, no name-detector).
#   But "did the self-review actually run?" cannot be left to the AI remembering
#   across 12 sites / long context / unattended /loop. This wrapper makes the
#   EXISTENCE of the gate deterministic while leaving the CONTENT of detection to
#   the LLM. All egress routes through here instead of raw `gh issue ...`.
#
# WHAT IT DOES (and ONLY this — design D2)
#   (a) Enforce the self-review attestation. The calling skill, after running the
#       privacy self-review (rules/privacy-scrubbing.md) and resolving the
#       repo-visibility strictness level, passes `--scrub-attested <level>`.
#       Missing / invalid attestation → REFUSE dispatch (non-zero exit). This
#       guarantees the step EXISTS; it does not pretend to guarantee the
#       judgment was correct (that is the LLM's + the ENFORCE block-with-diff's
#       job — see rules/privacy-scrubbing.md).
#   (b) A tiny mechanical LAST-RESORT net catching ONLY 3 zero-tolerance MECHANICAL
#       items, as belt-and-suspenders for an LLM miss:
#         1. an absolute macOS home path `/Users/<name>`
#         2. verbatim `~/.claude.json` content (a project-path string copied out
#            of the user's actual ~/.claude.json `projects` object). The bare
#            filename token is PUBLIC (Anthropic docs) and deliberately NOT
#            matched — content is the secret, not the name (#203 item 1).
#       This net is LEVEL-INDEPENDENT (fires even at LIGHT) because these two are
#       absolute zero-tolerance leaks, not "ordinary identifiers".
#
# WHAT IT MUST NOT DO
#   No semantic pattern matching. No maintained denylist. No name detection. The
#   semantic breadth of "is this private?" is 100% the LLM self-review's job
#   (design D1). Expanding this net beyond the 2 literal items requires a
#   separate openspec change (spec: "net does not grow into semantic matching").
#
# ATTESTATION FORMAT — Open Question Q1 resolution (chosen at apply time)
#   Mechanism (a) from design.md Q1: a REQUIRED flag `--scrub-attested <level>`
#   whose value is the resolved gate strictness (`enforce` | `warn` | `light`).
#   Rationale: encoding the resolved LEVEL (not a bare boolean/magic token) means
#   the caller cannot attest without having run the repo-visibility
#   classification that produces the level — so the attestation proves the whole
#   Step-0.6 gate ran, not merely that some flag was appended. The flag is
#   per-call (not an env var) so it cannot be left globally set and silently
#   satisfy every future dispatch. The level is informational to the wrapper (the
#   mechanical net is level-independent); ENFORCE/WARN/LIGHT behavior differences
#   live in the LLM layer, upstream of dispatch.
#
# USAGE
#   gh-egress.sh <create|comment|edit> [gh issue <verb> args...] \
#                --scrub-attested <enforce|warn|light>
#
#   On success the wrapper `exec`s the real gh so stdout / stderr / exit code are
#   byte-for-byte the same as calling `gh issue <verb> ...` directly (backward
#   compat: callers that capture `URL=$(... )` are unaffected).
#
# EXIT CODES — wrapper-origin codes live in a dedicated refusal band >=10 (#227).
#   INVARIANT: this wrapper never exits with its own code below 10; any exit <10
#   observed by a caller is gh's OWN code flowing through the final `exec` (so an
#   unattended caller can mechanically split "gate refusal -> fix content/args"
#   from "gh failure -> fix auth/network" on $? alone).
#   0   dispatched (exec gh -- gh's exit codes flow through from here, all <10)
#   10  privacy net hit (absolute /Users/<name> path / verbatim ~/.claude.json content)
#   11  mention net hit (unattested @login token / entity-encoded @ form)
#   12  unscannable --body-file (not a readable regular file, #203 item 3)
#   13  attestation missing/invalid (--scrub-attested absent or bad level)
#   14  usage error (bad/missing verb, malformed/split-token args, flag missing its value)
#
# TEST OVERRIDES (test-only; never set in production)
#   IDD_GH_BIN       gh binary to exec       (default: gh)
#   IDD_CLAUDE_JSON  claude.json to probe    (default: $HOME/.claude.json)

set -u

usage() {
  echo "✗ gh-egress: usage: gh-egress.sh <create|comment|edit> [gh args...] --scrub-attested <enforce|warn|light>" >&2
}

# --- verb (first positional) -------------------------------------------------
VERB="${1:-}"
case "$VERB" in
  create|comment|edit) shift ;;
  "") echo "✗ gh-egress: missing egress verb." >&2; usage; exit 14 ;;
  *)  echo "✗ gh-egress: unknown egress verb '$VERB' (only create|comment|edit route through this gate)." >&2; usage; exit 14 ;;
esac

# --- parse: pull out --scrub-attested, forward everything else verbatim -------
require_scannable_bodyfile() {
  # Refuse '-' (stdin), FIFOs, process substitutions and anything that is not a
  # readable REGULAR file (#203 item 3): the gate cannot scan a stream without
  # consuming the bytes gh needs, and an unreadable file would dispatch unscanned.
  if [ "$1" = "-" ] || [ ! -f "$1" ] || [ ! -r "$1" ]; then
    echo "✗ gh-egress: REFUSED — --body-file '$1' is not a readable regular file." >&2
    echo "  stdin ('-'), FIFOs and process substitutions cannot be scanned without consuming the stream." >&2
    echo "  Write the body to a regular file first, then re-dispatch." >&2
    exit 12
  fi
}

ATTESTED=""
MENTION_ATTESTED=""   # comma-separated logins vetted via rules/tagging-collaborators.md 5-step (#117)
GH_ARGS=()          # forwarded to gh, byte-identical minus the attestation flag
SCAN_PARTS=()       # all drafted prose (--body / --title / --body-file) — privacy nets
BODY_PARTS=()       # body-channel prose only — mention net (GitHub never notifies on
                    # title mentions, and a plaintext title cannot be backtick-escaped)
next_is=""          # "body" | "title" | "bodyfile" when the previous arg expects a value
while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --mention-attested|--mention-attested=*)
      # Same malformed-shape guard as --scrub-attested (#203 item 6 / #117).
      if [ -n "$next_is" ]; then
        echo "✗ gh-egress: malformed args — '--mention-attested' found where a value for --body/--title/--body-file was expected." >&2
        exit 14
      fi
      case "$arg" in
        --mention-attested)
          [ $# -ge 2 ] || { echo "✗ gh-egress: --mention-attested needs a value." >&2; exit 14; }
          MENTION_ATTESTED="$2"; shift 2; continue ;;
        *)
          MENTION_ATTESTED="${arg#--mention-attested=}"; shift; continue ;;
      esac ;;
    --scrub-attested|--scrub-attested=*)
      # Malformed-shape guard (#203 item 6): the attestation flag appearing where
      # a value for --body/--title/--body-file is still pending means the caller
      # split its tokens (e.g. `--body --scrub-attested warn`) — the drafted
      # prose would silently escape the scan. Refuse as a usage error.
      if [ -n "$next_is" ]; then
        echo "✗ gh-egress: malformed args — '--scrub-attested' found where a value for --body/--title/--body-file was expected (split-token attestation)." >&2
        exit 14
      fi
      case "$arg" in
        --scrub-attested)
          [ $# -ge 2 ] || { echo "✗ gh-egress: --scrub-attested needs a value." >&2; exit 14; }
          ATTESTED="$2"; shift 2; continue ;;
        *)
          ATTESTED="${arg#--scrub-attested=}"; shift; continue ;;
      esac ;;
    -b|--body|-t|--title)
      GH_ARGS+=("$arg")
      case "$arg" in -t|--title) next_is="title" ;; *) next_is="body" ;; esac
      shift; continue ;;
    --body=*)   GH_ARGS+=("$arg"); SCAN_PARTS+=("${arg#--body=}"); BODY_PARTS+=("${arg#--body=}"); shift; continue ;;
    --title=*)  GH_ARGS+=("$arg"); SCAN_PARTS+=("${arg#--title=}");  shift; continue ;;
    -F|--body-file)
      GH_ARGS+=("$arg"); next_is="bodyfile"; shift; continue ;;
    -b?*)
      GH_ARGS+=("$arg"); SCAN_PARTS+=("${arg#-b}"); BODY_PARTS+=("${arg#-b}"); next_is=""; shift; continue ;;
    -t?*)
      GH_ARGS+=("$arg"); SCAN_PARTS+=("${arg#-t}"); next_is=""; shift; continue ;;
    -F?*)
      GH_ARGS+=("$arg"); f="${arg#-F}"
      require_scannable_bodyfile "$f"
      FCONTENT="$(cat "$f")"; SCAN_PARTS+=("$FCONTENT"); BODY_PARTS+=("$FCONTENT"); next_is=""; shift; continue ;;
    --body-file=*) GH_ARGS+=("$arg"); next_is=""; f="${arg#--body-file=}"
      require_scannable_bodyfile "$f"
      FCONTENT="$(cat "$f")"; SCAN_PARTS+=("$FCONTENT"); BODY_PARTS+=("$FCONTENT"); shift; continue ;;
    *)
      GH_ARGS+=("$arg")
      case "$next_is" in
        body)       SCAN_PARTS+=("$arg"); BODY_PARTS+=("$arg") ;;
        title)      SCAN_PARTS+=("$arg") ;;
        bodyfile)   require_scannable_bodyfile "$arg"; FCONTENT="$(cat "$arg")"
                    SCAN_PARTS+=("$FCONTENT"); BODY_PARTS+=("$FCONTENT") ;;
      esac
      next_is=""; shift; continue ;;
  esac
done

# --- (a) attestation enforcement (deterministic) -----------------------------
case "$ATTESTED" in
  enforce|warn|light) : ;;
  "") echo "✗ gh-egress: REFUSED — privacy self-review attestation missing." >&2
      echo "  Run the privacy-scrubbing self-review (rules/privacy-scrubbing.md), then pass" >&2
      echo "  --scrub-attested <enforce|warn|light> (the resolved repo-visibility strictness)." >&2
      exit 13 ;;
  *)  echo "✗ gh-egress: REFUSED — invalid attestation level '$ATTESTED' (expected enforce|warn|light)." >&2
      exit 13 ;;
esac

# --- (b) mechanical last-resort net (3 zero-tolerance mechanical items) -------
# (grown 2→3 by #117 mention net — mechanical token matching, NOT semantic;
#  the "no semantic matching" boundary from #202 D1/D2 is unchanged)
# Joined once; the net only ever inspects the drafted prose, never --repo /
# --label / --milestone etc. (so metadata-only edits are never false-flagged).
SCAN=""
for p in "${SCAN_PARTS[@]:-}"; do SCAN+="$p"$'\n'; done

net_refuse() { echo "✗ gh-egress: REFUSED — mechanical net caught $1." >&2
  echo "  Zero-tolerance literal leak (belt-and-suspenders backstop; the LLM self-review normally catches this)." >&2
  echo "  Redact it (e.g. /Users/<name> → ~, drop the ~/.claude.json excerpt), then re-dispatch." >&2
  exit 10; }

# 1. absolute macOS home path /Users/<name> — require a real name char right
#    after the slash so the /Users/<name> placeholder (angle bracket) and a bare
#    /Users/ do NOT match (design: "literal absolute home path", not a pattern set).
if printf '%s' "$SCAN" | grep -qE '/Users/[A-Za-z0-9._-]'; then
  net_refuse "an absolute /Users/<name> home path"
fi

# 2. verbatim ~/.claude.json CONTENT. The bare filename/path token used to be
#    matched here too, but the name is public documentation — only the content
#    leaks anything. Dropped per #203 item 1 (it also blocked issues discussing
#    this gate itself, e.g. #202/#203).
#    A project-path string copied verbatim out of the user's actual
#    ~/.claude.json `projects` object (the "project basename leaks local folder
#    structure" threat), or a path-shaped value under a sensitive key name
#    (mcpServers[].env secret files etc. — #225 taxonomy). Extraction is ONE
#    python3 parser (#225) so every machine scans the same set; PUBLIC tool
#    paths (mcpServers[].command etc.) are not false-flagged (#203 item 2).
#    ${HOME:-} guard: both IDD_CLAUDE_JSON and HOME unset must not crash under
#    set -u — the probe just skips (#203 item 4).
#    #225 unified scan: ONE python3 parser replaces the old jq/no-jq dual path
#    whose results diverged per machine (jq: projects-only; no-jq: whole-file
#    wide — a secret path under mcpServers[].env dispatched on one machine and
#    refused on the other). Taxonomy: projects keys ∪ path-shaped string values
#    whose key (or any ancestor key) matches the tight sensitive-name set
#    (key|token|secret|credential|password|auth|env). Public tool paths
#    (mcpServers[].command / args) stay un-flagged (#203 item 2 preserved).
#    python3 absent OR parse failure → fail CLOSED to the bash-only whole-file
#    wide net (over-refusing beats leaking, #203 verify sec-2) — the degraded
#    path only ever over-matches, never under-matches the unified set.
CJSON="${IDD_CLAUDE_JSON:-${HOME:-}/.claude.json}"
if [ -n "$SCAN" ] && [ -r "$CJSON" ]; then
  PY_OK=0
  if command -v python3 >/dev/null 2>&1; then
    if KEYS_RAW="$(python3 - "$CJSON" <<'PYEOF' 2>/dev/null
import json, re, sys
try:
    cfg = json.load(open(sys.argv[1]))
    if not isinstance(cfg, dict):
        raise ValueError("top-level not an object")
except Exception:
    sys.exit(3)   # parse failure -> bash falls CLOSED to the wide net
SENS = re.compile(r"(?i)(key|token|secret|credential|password|auth|env)")
out = set()
proj = cfg.get("projects")
if isinstance(proj, dict):
    out.update(k for k in proj if isinstance(k, str))
def walk(node, sens):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, sens or bool(SENS.search(str(k))))
    elif isinstance(node, list):
        for v in node:
            walk(v, sens)
    elif isinstance(node, str) and sens:
        out.add(node)
walk({k: v for k, v in cfg.items() if k != "projects"}, False)
for s_ in sorted(out):
    print(s_)
PYEOF
)"; then
      PY_OK=1
      KEYS="$(printf '%s\n' "$KEYS_RAW" \
                | grep -E '^/.{11,}$' \
                | grep -E '/[^/]+/' \
                | sort -u)"
    fi
  fi
  if [ "$PY_OK" -eq 0 ]; then
    # python3 absent OR parse failure (malformed config) — fail CLOSED to the
    # whole-file wide net; a silently disabled net would leak (#203 verify sec-2).
    KEYS="$(grep -oE '"(/[^"]{11,})"' "$CJSON" 2>/dev/null \
              | sed -E 's/^"//; s/"$//' \
              | grep -E '/[^/]+/' \
              | sort -u)"
  fi
  if [ -n "$KEYS" ] && printf '%s' "$SCAN" | grep -qFf <(printf '%s\n' "$KEYS"); then
    net_refuse "verbatim content copied from ~/.claude.json"
  fi
fi

# 3. unattested @-mention net (#117). GitHub notifies real users on any raw
#    @login token in posted prose — irreversibly, and context-blind. AI-generated
#    bodies routinely carry incidental tokens (internal codenames like @codex,
#    quoted conversation text, dynamic values), which the intent-gated
#    tagging-collaborators.md protocol never sees. This net is UNCONDITIONAL:
#    every raw token must either be escaped (backticks / fenced code — inert on
#    GitHub, stripped before this scan) or covered by --mention-attested
#    (set only after the 5-step protocol resolved the logins).
#    Prefix guard [^[:alnum:]_] keeps email-like user@host out (GitHub does not
#    notify on those either).
MBODY=""
for p in "${BODY_PARTS[@]:-}"; do MBODY+="$p"$'\n'; done
# GFM: a fence opener allows at most 3 leading spaces; >=4 is literal indented
# code and must NOT toggle fence state (logic 117-3 false-negative otherwise).
# URL spans are exempt: GitHub's mention parser does not notify on @handle
# inside an autolinked URL (unpkg.com/@scope/pkg, mastodon.social/@dev), and
# backtick-escaping a URL would break the link (DA-117-B, R2). Only
# autolink-ELIGIBLE spans qualify — host must contain a dot; no-dot/malformed
# "URLs" (https://@user, http://localhost/@user) render as literal text where
# /@name IS a live mention, so they stay in the scan (117-A, R3).
MSCAN="$(printf '%s' "$MBODY" | awk '/^ ? ? ?```/{infence=!infence; next} !infence{print}' | sed -E 's/`[^`]*`//g; s|https?://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+[^[:space:])>]*||g')"
# Entity-encoded @ (&#64; / &#x40; / &commat;) followed by a login shape: GitHub
# may decode these before its mention scan — fail closed and refuse outright.
# Known friction (DA-117-A, accepted): prose that merely DISCUSSES the encoded
# form also refuses. Unlike the removed .claude.json filename net (public name,
# zero leak value), a raw entity-encoded @login has essentially one legitimate
# prose use — discussing bypasses — which is rare and naturally backtick-escapable
# (this guard runs AFTER fence/inline-code stripping, so `&#64;login` in code
# spans already passes). Irreversible-notification risk outweighs the friction.
if printf '%s' "$MSCAN" | grep -qiE '&#0*64;([a-z0-9-]|&#)|&#x0*40;([a-z0-9-]|&#)|&commat;([a-z0-9-]|&#)'; then
  echo "✗ gh-egress: REFUSED — entity-encoded @-mention (e.g. &#64;login) in body." >&2
  echo "  Encoded forms can decode into live mentions on GitHub. Spell it as literal text in backticks instead." >&2
  exit 11
fi
UNATTESTED_MENTIONS=""
while IFS= read -r login; do
  [ -z "$login" ] && continue
  case ",$MENTION_ATTESTED," in
    *",$login,"*) : ;;
    *) UNATTESTED_MENTIONS="$UNATTESTED_MENTIONS @$login" ;;
  esac
done < <(printf '%s\n' "$MSCAN" \
           | grep -oE '(^|[^[:alnum:]_])@[A-Za-z0-9][A-Za-z0-9-]*' \
           | grep -oE '@[A-Za-z0-9-]+' \
           | sed 's/^@//' \
           | sort -u)
if [ -n "$UNATTESTED_MENTIONS" ]; then
  echo "✗ gh-egress: REFUSED — unattested @-mention token(s):$UNATTESTED_MENTIONS" >&2
  echo "  GitHub notifies real users on raw @login tokens (irreversible). Either:" >&2
  echo "    - escape non-mention tokens in backticks (\`@name\`) — inert on GitHub, or" >&2
  echo "    - run the rules/tagging-collaborators.md 5-step protocol, then re-dispatch with" >&2
  echo "      --mention-attested <login1,login2> covering every intended mention." >&2
  exit 11
fi

# --- dispatch: byte-for-byte identical to raw `gh issue <verb> ...` -----------
GH_BIN="${IDD_GH_BIN:-gh}"
# ${arr[@]+...} idiom: empty array expands to NOTHING (":-" would yield one
# phantom '' positional, #203 item 5); bash-3.2 safe.
exec "$GH_BIN" issue "$VERB" ${GH_ARGS[@]+"${GH_ARGS[@]}"}
