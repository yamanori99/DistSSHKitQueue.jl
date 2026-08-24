# Contributing

Internals of this repo. Users: [README.md](README.md), [NEWS.md](NEWS.md).

This is a **separate** package from DistSSHKit. Do not copy Kit Julia slots. SSH E2E is this repo's `testenv/docker-ssh` (Kit-shaped workers). CI is `Pkg.test` (unit + child CLI / `parent:1`), JETLS, Aqua, path-gated PR SSH E2E on Julia 1.12 (`test/e2e.jl`: waiter API, queue-host CLI, `--qhost` over loopback OpenSSH), Gitleaks, schedule-only **E2E daily** (Linux / macOS Intel / WSL), and schedule-only **CI weekly**.

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to `ssh` / `rsync`).

| What | Need |
| --- | --- |
| Library, `Pkg.test()`, docs | Julia **1.12+** |
| DistSSHKit | **0.4.0+** (hard dependency; `execute!`, `job_id`, `kit.pid` / `kit.result`) |

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

JETLS CI uses `aviatesk/JETLS.jl/.github/actions/check@release` (moving tag). After a bump, re-read [cli-check](https://aviatesk.github.io/JETLS.jl/dev/cli-check/) and keep failing on hint+.

JETLS is the type gate. Do not commit `.vscode/settings.json` to silence the Language Server.

[Fatou](https://fatou.dev) is local only. Do not add `fatou.toml` or Fatou to `.vscode/extensions.json`. After a Fatou bump, check it did not rewrite files you did not mean to touch.

### PR CI

Ubuntu **1.12** (no DistSSHKit slots): `Pkg.test`, JETLS, Aqua, Documenter, Gitleaks. Linux E2E runs if `src/`, `test/`, `testenv/`, `Project.toml`, `test/Project.toml`, or the E2E workflow changed.

These files **alone** skip the heavy steps (job still starts; Pkg.test / JETLS / Aqua / Documenter do not run):

`README.md`, `CONTRIBUTING.md`, `NEWS.md`, `SECURITY.md`, `LICENSE`, `.gitignore`, `.github/pull_request_template.md`.

A new root markdown file stays heavy until listed in [`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml). Changes under `docs/src` still run those jobs. A `cut` label skips none of this: Pkg.test, JETLS, Aqua, Documenter, and Linux E2E all run. macOS / WSL stay on `E2E daily`, not the PR.

CI uploads Codecov on **main push** only (`Pkg.test`, flag `pkgtest`). PR E2E does not upload; `cut` PRs and **E2E daily** Linux upload flag `e2e`. Public repo + Codecov OIDC (`id-token: write`). Status checks are informational (`codecov.yml`). Local coverage:

```bash
julia --project=. -e 'using Pkg; Pkg.test(; coverage=true)'
DSKQ_CODE_COVERAGE=1 ./testenv/docker-ssh/scripts/up.sh --e2e
```

Required to merge (ruleset `main` uses these names). A skipped E2E still leaves the job green. E2E daily and CI weekly are not required.

- `Pkg.test - 1.12 - ubuntu-latest`
- `JETLS - 1.12 - ubuntu-latest`
- `Aqua - 1.12 - ubuntu-latest`
- `Documenter - 1.12 - ubuntu-latest`
- `Gitleaks`
- `ubuntu-latest → ubuntu-24.04`

| When | Workflow | What |
| --- | --- | --- |
| 04:00 JST, or Run workflow | `E2E daily` | `ubuntu-latest`, `macos-15-intel`, WSL2 → `ubuntu-24.04`. Linux job uploads E2E Codecov. Not a PR check. Failure opens (or comments on) Issue `E2E daily failed`; a later green run closes it. After a `cut` merge, dispatch this on that commit and wait for green before register. |
| Sunday 10:00 JST, or Run workflow | `CI weekly` | Same `Pkg.test` / JETLS / Aqua as a PR (no coverage). Not a PR check. Catches Aqua / JETLS `@release` drift when nothing merged that week. Failure opens Issue `CI weekly failed` (`ci`). |

## Pull requests

- Branch from `main`. Squash-merge only. Merged heads are deleted.
- One reviewable change per PR. Split unless `main` would be broken in between.
- Large plans: discuss in an issue first, then small PRs.

## Release

| Label | Meaning |
| --- | --- |
| `breaking` | Incompatible behavior. May land **without** a version bump. |
| `cut` | `Project.toml` `version` went up. |

On a breaking line bump `x` in `0.x.y`; otherwise bump `y`. Do not ship an empty cut. Do not automate the bump or `@JuliaRegistrator register`.

### DistSSHKit cuts

Queue work does not, by itself, trigger a DistSSHKit General patch. Develop against `dev` / git. Docs, opt-in flags, and CI on the kit wait.

If Queue cannot implement something without a kit hook, open a DistSSHKit Enhancement, land the small PR, then cut DistSSHKit (`0.4.y`) so Queue can pin General. Kit freeze and cut rules: [DistSSHKit CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKit.jl/blob/main/CONTRIBUTING.md#when-to-cut).

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
