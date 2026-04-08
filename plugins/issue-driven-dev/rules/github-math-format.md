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

## Display Math

- Use `$$...$$` on its own line for display equations
- No blank lines inside the `$$` block (GitHub breaks rendering)
- Prefer `\text{}` for words inside math: `$d^{(r)} \text{ where } r = 1$`
