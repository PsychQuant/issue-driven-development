---
name: github-math-format
description: GitHub Markdown math formatting rules — prevent KaTeX rendering errors in issues and comments
---

# GitHub Math Formatting

Writing to GitHub issues, PR descriptions, or comments requires KaTeX-compatible math.

## Underscore Rule

KaTeX treats `_` as subscript operator. Variable names with underscores break rendering.

| Pattern | Example | Result |
|---------|---------|--------|
| Variable name in math mode | `$\text{MSE_diff}$` | ❌ KaTeX error |
| Escaped underscore | `$MSE\_diff$` | ⚠️ Fragile |
| **Backtick code** | `` `MSE_diff` `` | ✅ Correct |
| Pure math symbol | `$\bar{I}_\infty$` | ✅ Correct |

**Rule**: Code identifiers with `_` → backtick. Math symbols with subscript → math mode.

**Mixed**: `$R_I = J \cdot$` `` `mse_info` `` — split at the boundary.

## Subscript Completeness

Every `_` in math mode MUST have a subscript argument:

```
WRONG:  $\bar{I}\infty$       → missing _, renders wrong
RIGHT:  $\bar{I}_\infty$      → correct subscript
RIGHT:  $\bar{I}_{\infty}$    → also correct (braced)
```

## Inline Math: Multiple Underscores Conflict (CRITICAL)

GitHub's markdown parser processes `_` as emphasis **before** KaTeX renders math. When a line has multiple `_` inside inline `$...$`, they get paired as italic markers and eaten.

```
BROKEN:  Similarly for $\bar{I}_{\infty}^{\prime}$ and $\bar{I}_{\infty}^{\prime\prime}$.
         → The _ between two $ blocks gets parsed as emphasis
```

**Workarounds** (pick one):

1. **Use Unicode** for simple superscripts/subscripts in text: d⁽¹⁾, d⁽²⁾, Ī′, Ī″
2. **Use display math** `$$...$$` which bypasses markdown parsing
3. **Limit to one subscript per inline math** — split complex expressions across sentences
4. **Avoid inline math entirely** for expressions with subscripts — describe in words

```
SAFE:    d⁽¹⁾ = 4 − 9/(2PQ)                          ← Unicode
SAFE:    $$\bar{I}_{\infty}^{\prime}$$                 ← display math
BROKEN:  $\bar{I}_{\infty}$ and $\bar{I}_{\infty}'$   ← multiple _ in one line
```

## Display Math

- Use `$$...$$` on its own line for display equations
- No blank lines inside the `$$` block (GitHub breaks rendering)
- Prefer `\text{}` for words inside math: `$d^{(r)} \text{ where } r = 1$`
- Display math does NOT have the underscore conflict — safe to use `_` freely
