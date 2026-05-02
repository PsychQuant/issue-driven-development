#!/bin/bash
# Version-aware auto-download wrapper for idd-route binary.
#
# Design (mirrors plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh):
# - Reads desired version from plugin.json `binaries.idd-route.version` (falls back
#   to top-level `version` field for backward compat with other plugins)
# - Compares against ~/bin/.idd-route.version sidecar
# - Re-downloads when plugin update bumps the desired version
# - Atomic file swap (.tmp + mv) so partial downloads never break a working install
# - Falls back to releases/latest if plugin.json unreadable or pinned tag missing
#
# Source repo: https://github.com/PsychQuant/idd-route-swift
# Asset name: literal `idd-route` (universal arm64+x86_64 macOS binary)

set -u

REPO="PsychQuant/idd-route-swift"
BINARY_NAME="idd-route"
INSTALL_DIR="$HOME/bin"
BINARY="$INSTALL_DIR/$BINARY_NAME"
VERSION_FILE="$INSTALL_DIR/.${BINARY_NAME}.version"

# Locate plugin root via wrapper's own path. Wrapper lives at PLUGIN_ROOT/bin/*.sh.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

# Read desired binary version from plugin.json.
# Prefer `.binaries.idd-route.version` (decoupled from plugin shell version);
# fall back to top-level `version` field for plugins that haven't adopted the
# binaries field yet.
DESIRED_VERSION=""
if [[ -f "$PLUGIN_JSON" ]]; then
    # Try `.binaries.idd-route.version` first (multi-line JSON parse via grep)
    DESIRED_VERSION=$(awk '
        /"binaries"/ { in_bin = 1 }
        in_bin && /"idd-route"/ { in_target = 1 }
        in_target && /"version"/ {
            match($0, /"version":[[:space:]]*"[^"]+"/);
            v = substr($0, RSTART, RLENGTH);
            sub(/.*"version":[[:space:]]*"/, "", v);
            sub(/".*/, "", v);
            print v;
            exit
        }
    ' "$PLUGIN_JSON" 2>/dev/null || true)

    # Fallback to top-level version
    if [[ -z "$DESIRED_VERSION" ]]; then
        DESIRED_VERSION=$(grep -oE '"version":[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
            | head -1 | cut -d'"' -f4 || true)
    fi
fi

# Read currently installed version from sidecar (empty if missing).
INSTALLED_VERSION=""
[[ -f "$VERSION_FILE" ]] && INSTALLED_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)

# Decide whether to download.
NEED_DOWNLOAD=false
REASON=""
if [[ ! -x "$BINARY" ]]; then
    NEED_DOWNLOAD=true
    REASON="binary not installed"
elif [[ -n "$DESIRED_VERSION" ]] && [[ "$INSTALLED_VERSION" != "$DESIRED_VERSION" ]]; then
    NEED_DOWNLOAD=true
    REASON="plugin wants v${DESIRED_VERSION}, installed is v${INSTALLED_VERSION:-unknown}"
fi

if $NEED_DOWNLOAD; then
    echo "$BINARY_NAME: $REASON — downloading from $REPO..." >&2
    mkdir -p "$INSTALL_DIR"

    # Resolve download URL.
    # Prefer `gh` CLI (uses user's auth — much higher rate limit, won't hit
    # the 60-req/hr unauthenticated wall when many tools call this in a row).
    # Falls back to plain curl if gh is missing or fails.
    URL=""
    for TAG_PATH in \
        "${DESIRED_VERSION:+repos/$REPO/releases/tags/v$DESIRED_VERSION}" \
        "repos/$REPO/releases/latest"
    do
        [[ -z "$TAG_PATH" ]] && continue
        if command -v gh &>/dev/null; then
            URL=$(gh api "$TAG_PATH" --jq ".assets[] | select(.name == \"$BINARY_NAME\") | .browser_download_url" 2>/dev/null | head -1)
            [[ -n "$URL" ]] && break
        fi
        URL=$(curl -sL --max-time 30 "https://api.github.com/$TAG_PATH" 2>/dev/null \
            | grep '"browser_download_url"' | grep "/$BINARY_NAME\"" | head -1 \
            | sed 's/.*"\(https[^"]*\)".*/\1/')
        [[ -n "$URL" ]] && break
    done

    if [[ -z "$URL" ]]; then
        if [[ -x "$BINARY" ]]; then
            echo "$BINARY_NAME: WARNING — no download URL found, keeping existing binary" >&2
        else
            echo "$BINARY_NAME: ERROR — no download URL found at $REPO. Install manually: https://github.com/$REPO/releases" >&2
            exit 1
        fi
    else
        if curl -sL --max-time 300 "$URL" -o "${BINARY}.tmp" 2>/dev/null; then
            chmod +x "${BINARY}.tmp"
            mv "${BINARY}.tmp" "$BINARY"
            echo "${DESIRED_VERSION:-unknown}" > "$VERSION_FILE"
            echo "$BINARY_NAME: installed v${DESIRED_VERSION:-latest}" >&2
        else
            rm -f "${BINARY}.tmp" 2>/dev/null
            if [[ -x "$BINARY" ]]; then
                echo "$BINARY_NAME: WARNING — download failed, keeping existing binary" >&2
            else
                echo "$BINARY_NAME: ERROR — download failed" >&2
                exit 1
            fi
        fi
    fi
fi

exec "$BINARY" "$@"
