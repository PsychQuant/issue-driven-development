#!/usr/bin/env python3
"""generate-path-map.py — render docs/wiki/Path-Map.md from docs/workflows.md (#276 Phase 2).

Single source: docs/workflows.md — its `## Path Flowchart` mermaid block is
lifted verbatim, and the `### <A-H>.` / `#### P-` catalog headings become
per-category navigation tables. Output is DETERMINISTIC (no timestamps) so the
path-map-sync drift-guard can byte-diff the committed page.

Usage:
  python3 scripts/generate-path-map.py            # write docs/wiki/Path-Map.md
  python3 scripts/generate-path-map.py --check    # exit 1 if committed page is stale
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / "docs" / "workflows.md"
PAGE = ROOT / "docs" / "wiki" / "Path-Map.md"

REPO_BLOB = "https://github.com/PsychQuant/issue-driven-development/blob/main/docs/workflows.md"


def extract_mermaid(text: str) -> str:
    """The mermaid fence inside `## Path Flowchart` — verbatim."""
    m = re.search(r"^## Path Flowchart.*?^```mermaid\n(.*?)^```", text, re.M | re.S)
    if not m:
        sys.exit("✗ workflows.md has no `## Path Flowchart` mermaid block")
    return m.group(1).rstrip("\n")


def extract_catalog(text: str):
    """[(category_heading, [(p_name, tail_or_first_line), ...]), ...]"""
    cats = []
    cur = None
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        cm = re.match(r"^### ([A-H]\..+)$", line)
        if cm:
            cur = (cm.group(1).strip(), [])
            cats.append(cur)
        pm = re.match(r"^#### (P-[a-z0-9-]+)\s*(?:[—(](.*))?$", line)
        if pm and cur is not None:
            name = pm.group(1)
            tail = (pm.group(2) or "").strip().rstrip("）)").strip()
            if not tail:
                # fall back to the section's first prose line
                j = i + 1
                while j < len(lines) and (not lines[j].strip() or lines[j].startswith("```")):
                    # skip blanks; skip a whole fence if one opens
                    if lines[j].startswith("```"):
                        j += 1
                        while j < len(lines) and not lines[j].startswith("```"):
                            j += 1
                    j += 1
                if j < len(lines):
                    tail = lines[j].strip()
            if len(tail) > 90:
                tail = tail[:87] + "…"
            cur[1].append((name, tail))
        i += 1
    return [c for c in cats if c[1]]


def render(text: str) -> str:
    mermaid = extract_mermaid(text)
    cats = extract_catalog(text)
    n = sum(len(ps) for _, ps in cats)
    out = []
    out.append("# IDD Path Map")
    out.append("")
    out.append(f"> **{n} 條 sanctioned path 的選擇導航圖** — maintainer 日常查詢用（#276）。")
    out.append(f"> Single source：[docs/workflows.md]({REPO_BLOB})（§ Path Flowchart + § Path Catalog）；")
    out.append("> 本頁由 `scripts/generate-path-map.py` 生成，**請勿直接編輯** — 改 workflows.md 後重跑 generator。")
    out.append("")
    out.append("```mermaid")
    out.append(mermaid)
    out.append("```")
    out.append("")
    out.append("## Path 一覽（依類別）")
    out.append("")
    for heading, paths in cats:
        out.append(f"### {heading}")
        out.append("")
        out.append("| Path | 說明 |")
        out.append("|------|------|")
        for name, tail in paths:
            out.append(f"| `{name}` | {tail} |")
        out.append("")
    out.append("---")
    out.append("")
    out.append(f"細節（touchpoints、mode、assumptions、risk）與 § Anti-patterns 見 [docs/workflows.md]({REPO_BLOB})。")
    return "\n".join(out) + "\n"


def main() -> None:
    text = WORKFLOWS.read_text(encoding="utf-8")
    rendered = render(text)
    if "--check" in sys.argv:
        if not PAGE.exists():
            sys.exit(f"✗ {PAGE} missing — run the generator")
        if PAGE.read_text(encoding="utf-8") != rendered:
            sys.exit(f"✗ {PAGE} is STALE — workflows.md changed; rerun: python3 scripts/generate-path-map.py")
        print("OK — Path-Map.md is fresh")
        return
    PAGE.parent.mkdir(parents=True, exist_ok=True)
    PAGE.write_text(rendered, encoding="utf-8")
    print(f"wrote {PAGE} ({n if (n := rendered.count('| `P-')) else 0} paths)")


if __name__ == "__main__":
    main()
