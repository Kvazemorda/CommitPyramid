# Contributing to CommitPyramid

Thanks for considering contributing to CommitPyramid. Here's how to get involved — whether you're fixing a bug, suggesting a feature, or dropping in some pixel art.

---

## Code of Conduct

Be kind, assume good intent. That's it.

---

## Ways to Contribute

- **Bug reports** — open an Issue with steps to reproduce and your macOS/Xcode versions
- **Feature requests** — open an Issue tagged `[FEATURE]` and describe the problem you want solved
- **Code** — fix bugs, add features, improve tests, refactor
- **Art / assets** — sprites, textures, UI icons; see [CONTRIBUTING-ASSETS.md](CONTRIBUTING-ASSETS.md) for the full guide

---

## Before You Start

1. Read [`docs/concept.md`](concept.md) and [`docs/architecture.md`](architecture.md) to understand what CommitPyramid is and how it's structured.
2. Look at open Issues — your idea or bug might already be tracked.
3. For anything non-trivial (new subsystem, significant refactor, new game mechanic), open a feature request Issue first. A quick discussion about approach can save everyone time.

---

## Development Setup

```bash
git clone https://github.com/Kvazemorda/CommitPyramid.git
cd CommitPyramid
swift build
swift run CommitPyramid
```

**Requirements:** macOS 14+, Xcode 15+. No external dependencies — everything is in the Swift package.

---

## Code Style

CommitPyramid follows standard Swift conventions with a few project-specific preferences:

- **4-space indentation** (no tabs)
- **`final class` by default** — open it up only if subclassing is intentional
- **Prefer value types** (`struct`, `enum`) over reference types where it makes sense
- **`async/await` for all IO** — no callbacks or semaphores
- **No force-unwrap** in production code; use `guard` or optional chaining

Tests live in `Tests/CommitPyramidTests/`. Add a test for any non-trivial logic you introduce.

---

## Pull Request Workflow

1. **Fork** the repo and create a branch:
   - `feature/short-name` for new features
   - `fix/issue-N` for bug fixes (where N is the Issue number)
   - `art/<unit-name>` for asset contributions

2. **Commit messages:**
   - Short subject line, 50 characters or fewer
   - Body (if needed) explains *why*, not just *what*

3. **Before pushing**, make sure everything builds and tests pass:
   ```bash
   swift build && swift test
   ```

4. **Open a PR** using the template in `.github/PULL_REQUEST_TEMPLATE.md`. Fill in the relevant sections.

5. **Keep commits focused.** Squash merge is the default, but clean history in the branch makes review easier.

---

## Review Process

Here's what to expect after opening a PR:

- A reviewer will check that the build and tests pass, there are no new compiler warnings, the code follows existing patterns, and no personal data ended up in the diff.
- Expect feedback and iteration — that's normal and welcome.
- Response time is best-effort; this is a small open-source project.

---

## Project Structure

```
Sources/CommitPyramid/       # Main app source
  App/                       # AppDelegate, window controllers
  Data/                      # Models, persistence, file watchers
  Game/                      # SpriteKit scene, engine loop
  UI/                        # SwiftUI views, SpriteKit bridges
  World/                     # Map generation logic
  Theme/                     # Color palette, visual constants
Tests/CommitPyramidTests/    # Unit and integration tests
concept/                     # Russian working docs (maintainer-internal)
docs/                        # English public documentation
.github/                     # Issue/PR templates, CI workflows
```

---

## Tasks System

CommitPyramid uses a structured PM/lead/run workflow internally (documented under `concept/`) to track planned work across cycles. Contributors don't need to follow any of that — just open Issues and PRs naturally. The maintainer will pick up your contribution and integrate it into the planning flow.
