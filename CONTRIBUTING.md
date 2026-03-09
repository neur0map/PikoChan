# Contributing to PikoChan

Thanks for your interest in PikoChan. This document explains how to contribute safely and effectively. PRs that don't follow these rules will be rejected.

---

## Before You Start

1. **Check existing issues** — search open issues before creating a new one. If your idea or bug is already tracked, comment on it instead.
2. **Open an issue first** — for anything beyond a typo fix, open an issue describing what you want to do and wait for a response. This prevents wasted effort on work that may not align with the project direction.
3. **One PR per issue** — each pull request should address exactly one issue or concern. Don't bundle unrelated changes.

---

## Branch Naming

Use this format:

```
<type>/<issue-number>-<short-description>
```

Examples:
- `fix/13-haptic-feedback-hover`
- `feat/15-matched-geometry-album-art`
- `docs/update-changelog`

Types: `fix`, `feat`, `refactor`, `docs`, `test`, `chore`

---

## Commit Messages

Follow this format:

```
<type>: <short summary>

<optional body explaining why, not what>

Resolves #<issue-number>
```

Rules:
- **Summary line**: imperative mood ("Add blur transitions", not "Added" or "Adds"), under 72 characters
- **Body**: explain *why* the change was made, not *what* changed (the diff shows what)
- **Issue reference**: include `Resolves #N` or `Fixes #N` if it closes an issue, `Ref #N` if related but not closing
- **No merge commits** — rebase your branch on `main` before opening the PR

Types:
| Type | Use for |
|------|---------|
| `fix` | Bug fixes |
| `feat` | New features or capabilities |
| `refactor` | Code restructuring without behavior change |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `chore` | Build config, dependencies, tooling |

Bad examples:
- `updated stuff`
- `fix bug`
- `WIP`
- `misc changes`

Good examples:
- `fix: prevent panel collapse when clicking playback controls`
- `feat: add iTunes Search API for browser album art`
- `refactor: split NotchManager music logic into MusicController`

---

## Pull Request Requirements

Every PR must include:

### Title
Same format as commit summary: `<type>: <short description>`

### Description
Use this template:

```markdown
## What
Brief description of the change.

## Why
Why this change is needed. Link the issue.

## How
How you implemented it. Mention key files changed and approach taken.

## Testing
How you verified it works. Screenshots or screen recordings for UI changes.

## Issue
Resolves #<number>
```

### Checklist (enforced)

- [ ] Targets a single issue or concern
- [ ] Branch is rebased on latest `main` (no merge commits)
- [ ] Builds without errors or warnings (`xcodebuild -scheme PikoChan`)
- [ ] No unrelated formatting changes, whitespace fixes, or drive-by refactors
- [ ] No new files unless absolutely necessary (prefer editing existing files)
- [ ] UI changes include a screenshot or screen recording
- [ ] Commit messages follow the format above
- [ ] No secrets, API keys, or credentials in the diff

---

## What Will Get Your PR Rejected

- **No linked issue** — every non-trivial PR needs an issue. Open one first.
- **Bundled changes** — fixing a bug + adding a feature + reformatting code in one PR. Split them.
- **Merge commits** — rebase, don't merge.
- **Vague commit messages** — "fix stuff", "update code", "WIP". Be specific.
- **Breaking existing behavior** without discussion in the issue first.
- **Adding dependencies** without prior approval in the issue.
- **Large refactors** without an approved plan. Open an issue, describe the refactor, wait for sign-off.
- **Generated or AI-dumped code** with no evidence of understanding. You should be able to explain every line you changed.

---

## Code Style

- **Swift 6.0** with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **`@Observable`** for state management (not `ObservableObject`/`@Published`)
- **No third-party dependencies** unless absolutely necessary and pre-approved
- **No force unwraps** (`!`) unless the crash is intentional and documented
- **No print statements** — use `PikoGateway` for logging
- Comments only where the logic isn't self-evident. Don't add docstrings to obvious code.
- Match the existing naming patterns in the file you're editing

---

## Architecture Rules

- **PikoChan runs without sandbox** — be extra careful with file system access. All paths go through `PikoPathGuard`
- **No direct linking to private frameworks** — MediaRemote is loaded via `dlopen`/`dlsym` at runtime
- **No network calls without user consent** — cloud features must be opt-in via config
- **State transitions go through `NotchManager.transition(to:)`** — don't set `state` directly
- **History pollution** — any internal LLM call must use `skipHistory: true`

---

## What Helps Most Right Now

- **Testing on different MacBook models** — notch geometry varies between generations
- **UI/UX feedback** — animation timing, interaction patterns, visual polish
- **Bug reports with reproduction steps** — especially around NSPanel behavior, hover detection, and music playback controls
- **Swift/AppKit expertise** — NSPanel quirks, Accessibility API, CoreAudio

---

## Labels

| Label | Meaning |
|-------|---------|
| `bug` | Something is broken |
| `enhancement` | New feature or improvement |
| `good first issue` | Approachable for newcomers |
| `help wanted` | Looking for contributors |
| `documentation` | Docs only |
| `wontfix` | Intentionally not addressing |

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
