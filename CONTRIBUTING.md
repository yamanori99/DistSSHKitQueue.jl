# Contributing

Internals of this repo. Users: [README.md](README.md), [DESIGN.md](DESIGN.md), [NEWS.md](NEWS.md).

This is a **separate** package from DistSSHKit. Do not copy Kit Julia slots. SSH E2E is this repo's `testenv/docker-ssh` (Kit-shaped workers). CI is `Pkg.test` (Codecov), JETLS, path-gated PR SSH E2E on Julia 1.12, Gitleaks, and schedule-only **E2E daily** (Linux / macOS Intel / WSL).

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to `ssh` / `rsync`).

| What | Need |
| --- | --- |
| Library, `Pkg.test()`, docs | Julia **1.12+** |
| DistSSHKit | **0.3.1+** (hard dependency) |

Prefer [juliaup](https://github.com/JuliaLang/juliaup).

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHKitQueue.jl.git
cd DistSSHKitQueue.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

From another app:

```bash
julia --project=/path/to/MyProject.jl -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKitQueue.jl")'
```

## Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
./.github/jetls-check.sh    # hint+; same files as CI
./.github/aqua-check.sh     # latest registry Aqua; not part of Pkg.test()
./testenv/docker-ssh/scripts/up.sh --e2e
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
gitleaks detect --source .
```

Layout: [test/README.md](test/README.md).

JETLS is the type gate (`./.github/jetls-check.sh`, hint+). Do not commit `.vscode/settings.json` to silence the Language Server.

[Fatou](https://fatou.dev) is local only. Do not add `fatou.toml` or Fatou to `.vscode/extensions.json`. After a Fatou bump, check it did not rewrite files you did not mean to touch.

### PR CI

Ubuntu: `Pkg.test` (Codecov `pkgtest`), JETLS, and path-gated SSH E2E (Codecov `e2e`) on **1.12**, Gitleaks. **E2E daily** (`ssh-e2e-daily.yml`) is not a PR check: cron 04:00 JST plus `workflow_dispatch`, GHCR image `dskq-linux-ssh-worker`, Linux / `macos-15-intel` (Colima) / WSL2. Failure opens issue `E2E daily failed` (`ci`). No slots, no Documenter deploy yet. Public repo + Codecov OIDC (`id-token: write`). Status checks are informational (`codecov.yml`).

CI E2E (`DSKQ_CODE_COVERAGE=1`) writes `.cov` and uploads to Codecov (merged with `Pkg.test`). Daily E2E does not upload coverage. Local coverage:

```bash
julia --project=. -e 'using Pkg; Pkg.test(; coverage=true)'
DSKQ_CODE_COVERAGE=1 ./testenv/docker-ssh/scripts/up.sh --e2e
```

## Pull requests

- Branch from `main`. Squash-merge only. Merged heads are deleted.
- One reviewable change per PR. Split unless `main` would be broken in between.
- Large plans: [DESIGN.md](DESIGN.md) first, then small PRs.

## Release

| Label | Meaning |
| --- | --- |
| `breaking` | Incompatible behavior. May land **without** a version bump. |
| `cut` | `Project.toml` `version` went up. |

On a breaking line bump `x` in `0.x.y`; otherwise bump `y`. Do not ship an empty cut. Do not automate the bump or `@JuliaRegistrator register`.

### DistSSHKit cuts

Queue work does not, by itself, trigger a DistSSHKit General patch. Develop against `dev` / git. Docs, opt-in flags, and CI on the kit wait.

If Queue cannot implement something without a kit hook, open a DistSSHKit Enhancement, land the small PR, then cut DistSSHKit (`0.3.y`) so Queue can pin General. Kit freeze and cut rules: [DistSSHKit CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKit.jl/blob/main/CONTRIBUTING.md#when-to-cut).

### When to cut

**Not on General yet.** Cut when DistSSHKit compat must move, or when we need a version pin ourselves. Do not register.

**After the first General release**, same rule as DistSSHKit: cut when [NEWS.md](NEWS.md) **Unreleased** has something General users should get.

| Unreleased is… | Cut? |
| --- | --- |
| Happy-path bug (FIFO enqueue / waiter) | Yes, that patch promptly |
| Opt-in flags, docs, CI | When someone needs it on General, **or** those items have sat in Unreleased for **two weeks** |

### After a cut on General

1. `@JuliaRegistrator register` on the **merge commit** (not the PR body).
2. Paste the NEWS section under `Release notes:`.

## Issues

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. Usage questions can wait until Discussions are on. Security: [SECURITY.md](SECURITY.md).

Every PR needs one type label (`bug` / `enhancement` / `chore`) when labels exist.

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links: `docs/src` and README. User-visible behavior: NEWS (date the section when tagged). Generative AI is allowed; you own the diff. Keep docs plain.
