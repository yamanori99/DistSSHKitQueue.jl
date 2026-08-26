# Contributing

Internals of this repo. Users: [README.md](README.md), [README.ja.md](README.ja.md), [NEWS.md](NEWS.md), [docs](https://yamanori99.github.io/DistSSHQueue.jl/dev/) (`docs/`; [docs/README.md](docs/README.md)).

This is a **separate** package from DistSSHKit: FIFO `serve` in front of one Kit `go` / `drive`, not a bigger Kit. Placement tokens, `execute!`, `kit.pid` / `kit.result`, `terminate_run!`, demo argv, and rsync/collect are Kit's. Queue records table state and the path Kit already wrote.

Julia slots match Kit (`min` / `max` / `tip` in `.github/julia-slots.env`). SSH E2E is this repo's `testenv/docker-ssh` (Kit-shaped workers). CI is `Pkg.test` (unit + child CLI / `parent:1`), JETLS, Aqua, path-gated PR SSH E2E on slot **max** (`test/e2e.jl`: `serve` API, queue-host CLI, `qhost:` over loopback OpenSSH), Gitleaks, schedule-only **E2E weekly** (Linux / macOS Intel / WSL), and schedule-only **CI weekly**.

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to `ssh` / `rsync`).

| What | Need |
| --- | --- |
| Library, `Pkg.test()`, `julia -m DistSSHQueue`, docs | Julia **1.12+** |
| DistSSHKit | **0.4.2+** from General (`execute!`, `job_id`, `kit.pid` / `kit.result`). Not a git sibling. |

Prefer [juliaup](https://github.com/JuliaLang/juliaup). Details: [Requirements](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/).

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHQueue.jl.git
cd DistSSHQueue.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

That pulls DistSSHKit from General. Do not add a `[sources]` path to a Kit checkout unless you are landing an unreleased kit hook.

From another app:

```bash
julia --project=/path/to/MyProject.jl -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHQueue.jl")'
```

## Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run this on slot **min** and **max** (and **tip** if you have nightly). Layout: [test/README.md](test/README.md).

```bash
./.github/jetls-check.sh    # hint+; same files as CI
./.github/aqua-check.sh     # latest registry Aqua; not part of Pkg.test()
./testenv/docker-ssh/scripts/up.sh --e2e
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
gitleaks detect --source .
```

JETLS CI uses `aviatesk/JETLS.jl/.github/actions/check@release` (moving tag). After a bump, re-read [cli-check](https://aviatesk.github.io/JETLS.jl/dev/cli-check/) and keep failing on hint+.

JETLS is the type gate. Do not commit `.vscode/settings.json` to silence the Language Server.

[Fatou](https://fatou.dev) is local only. Do not add `fatou.toml` or Fatou to `.vscode/extensions.json`. After a Fatou bump, check it did not rewrite files you did not mean to touch.

### Julia slots

Exactly three pins, in [`.github/julia-slots.env`](.github/julia-slots.env). Do not add a fourth version job. Slide the pin; keep job names `min` / `max` / `tip`.

| Slot | Role | Required |
| --- | --- | --- |
| **min** | `Project.toml` julia floor. Pkg.test (no coverage), Aqua, JETLS, Documenter | yes |
| **max** | Newest tagged or prerelease (`versions.json`). Pkg.test, Aqua, PR / weekly E2E, GHCR worker. Codecov `pkgtest` on **main push** only | yes |
| **tip** | Next-minor nightly. Pkg.test, Aqua. `continue-on-error` | no |

JETLS is min plus `JULIA_SLOT_JETLS_MAX` (job name still `JETLS - max`). That pin lags when `max` / `tip` move past what JETLS lists (today 1.12.2–1.13). Raise it only after JETLS supports that runtime. No JETLS **tip**.

When a new RC lands, change `JULIA_SLOT_MAX` only. If that RC is a new **major.minor**, bump the worker Dockerfile / WSL `--default-channel` in the same PR (E2E pair). When bumping compat, raise `JULIA_SLOT_MIN` only.

### PR CI

Ubuntu: `Pkg.test` min / max / tip, JETLS min / max, Aqua min / max / tip, Documenter min, Gitleaks. Linux E2E (max) runs if `src/`, `test/`, `testenv/`, `Project.toml`, `test/Project.toml`, or the E2E workflow changed; otherwise that job is skipped.

These files **alone** skip the heavy steps (job still starts; Pkg.test / JETLS / Aqua / Documenter do not run):

`README.md`, `README.ja.md`, `CONTRIBUTING.md`, `NEWS.md`, `SECURITY.md`, `LICENSE`, `.gitignore`, `.github/pull_request_template.md`.

A new root markdown file stays heavy until listed in [`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml). Changes under `docs/src` still run those jobs. A `cut` label skips none of this: Pkg.test, JETLS, Aqua, Documenter, and Linux E2E all run. macOS / WSL stay on `E2E weekly`, not the PR.

CI uploads Codecov on **main push** only (`Pkg.test` max slot, flag `pkgtest`). PR E2E does not upload; `cut` PRs and **E2E weekly** Linux upload flag `e2e`. Public repo + Codecov OIDC (`id-token: write`). Status checks are informational (`codecov.yml`). Local coverage:

```bash
julia --project=. -e 'using Pkg; Pkg.test(; coverage=true)'
DSKQ_CODE_COVERAGE=1 ./testenv/docker-ssh/scripts/up.sh --e2e
```

Required to merge (ruleset `main` uses these names). Tip jobs are allow-failure. Path-gated E2E skips the job `ubuntu-latest → ubuntu-24.04` (Actions: Skipped; GitHub still treats a skipped required check as pass). E2E weekly and CI weekly are not required.

- `Pkg.test - min - ubuntu-latest`
- `Pkg.test - max - ubuntu-latest`
- `JETLS - min - ubuntu-latest`
- `JETLS - max - ubuntu-latest`
- `Aqua - min - ubuntu-latest`
- `Aqua - max - ubuntu-latest`
- `Documenter - min - ubuntu-latest`
- `Gitleaks`
- `ubuntu-latest → ubuntu-24.04`
- `PR label`

| When | Workflow | What |
| --- | --- | --- |
| Sunday 04:00 JST, or Run workflow | `E2E weekly` | `ubuntu-latest`, `macos-15-intel`, WSL2 → `ubuntu-24.04`. Linux job uploads E2E Codecov. Not a PR check. Failure opens (or comments on) Issue `E2E weekly failed`; a later green run closes it. After a `cut` merge, dispatch this on that commit and wait for green before register. |
| Sunday 10:00 JST, or Run workflow | `CI weekly` | Same `Pkg.test` / JETLS / Aqua slots as a PR (no coverage). Not a PR check. Catches max / Aqua / JETLS `@release` drift when nothing merged that week. Failure of min/max jobs opens Issue `CI weekly failed` (`ci`); tip is omitted from that notify. |

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

Queue pins DistSSHKit **0.4.2+** from General. Ordinary Queue work does not `Pkg.develop` Kit and does not, by itself, trigger a DistSSHKit General patch. Docs, opt-in flags, and CI on the kit wait.

If Queue cannot implement something without a kit hook, open a DistSSHKit Enhancement, land the small PR, then cut DistSSHKit (`0.4.y`) so Queue can pin General. `Pkg.develop` a Kit checkout only until that cut is on General. Kit freeze and cut rules: [DistSSHKit CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKit.jl/blob/main/CONTRIBUTING.md#when-to-cut).

### When to cut

**Not on General yet.** Cut when DistSSHKit compat must move, or when we need a version pin ourselves. Do not register.

**After the first General release**, same rule as DistSSHKit: cut when [NEWS.md](NEWS.md) **Unreleased** has something General users should get.

| Unreleased is… | Cut? |
| --- | --- |
| Happy-path bug (FIFO enqueue / `serve`) | Yes, that patch promptly |
| Opt-in flags, docs, CI | When someone needs it on General, **or** those items have sat in Unreleased for **two weeks** |

### After a cut on General

1. `@JuliaRegistrator register` on the **merge commit** (not the PR body).
2. Paste the NEWS section under `Release notes:`.

## Issues

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. The area dropdown is triage; add `area:*` if useful. Usage questions can wait until Discussions are on. Security: [SECURITY.md](SECURITY.md).

A Queue failure is not automatically a Queue bug. Decide the repo first:

- Queue lagged Kit's contract (demo argv, translating `terminate_run!` wait into `:cancelled`, collect under a gitignored path): fix Queue. Do not open DistSSHKit.
- Queue cannot land the feature without a Kit hook: DistSSHKit Enhancement, Kit PR, Kit cut, then pin here ([DistSSHKit cuts](#distsshkit-cuts)).
- Reproduced Kit defect (`execute!` `ok` with empty collect, wait/cancel that contradicts Kit docs): open a [DistSSHKit issue](https://github.com/yamanori99/DistSSHKit.jl/issues) with the Kit log / `kit.result` / `failed_step`. Link it from the Queue issue or PR. A Queue-only workaround is temporary and must say so.

Do not file DistSSHKit on speculation. Reproduce against Kit (or this E2E with Kit artifacts) first.

Every PR needs one type label (`bug` / `enhancement` / `chore`) when labels exist.

## Labels

```bash
./.github/gen-labeler.sh          # rewrite
./.github/gen-labeler.sh --check  # CI drift
```

Every tracked path must match some `area:*` glob (`gen-labeler.sh --check`). Globs are positive paths; do not add `!` excludes (labeler ORs them as "not this path" and tags unrelated files). Path labeler syncs only `area:*`. After `setLabels` it restores type / `cut` / other non-area labels so a concurrent Type job is not wiped.

| Paths | Label |
| --- | --- |
| `src/client/**` | `area:client` |
| `src/qhost/**` | `area:qhost` |
| Leftover queue (`src/DistSSHQueue.jl`, `src/DistSSHQueue/**`, matching unit tests, shared `test/integration/cli.jl`, package meta) | `area:queue` |
| Harness under `test/` (not `unit/` / `integration/`) and `testenv/**` | `area:test` |
| `test/e2e.jl` | `area:client` and `area:qhost` as well |
| `docs/**` | `area:docs` |
| `README.md`, `README.ja.md`, `NEWS.md`, `CONTRIBUTING.md`, `SECURITY.md` | `area:project-docs` |
| `.github/**`, `codecov.yml` | `area:ci` |

New leftover queue test file: edit the script, regenerate, create the GitHub label.

Backfill every PR after a vocabulary change:

```bash
./.github/retag-pr-areas.sh           # dry-run
./.github/retag-pr-areas.sh --apply
```

### Type labels

Every PR needs one of `bug` / `enhancement` / `chore`. Dependabot skips the type check (`dependencies` only). Override with `gh pr edit N --add-label …`.

CI infers, in order:

1. A unique type on a closing issue (`Fixes #N`)
2. Else the branch prefix: `feat/` → enhancement, `fix/` → bug, `breaking/` → breaking, `chore/` / `docs/` / `ci/` / `test/` / anything else → chore

`fix/` plus `Fixes` an enhancement issue gets `enhancement`. `breaking` may sit next to the type label. After merge a human registers; TagBot tags (once on General).

Ruleset `main` requires check `PR label` (workflow `Type`). Type labels (`bug` / `enhancement` / `breaking` / `chore` / `cut`) and each `area:*` must exist (`gh label create` if missing).

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links: `docs/src`, [README.md](README.md), and [README.ja.md](README.ja.md). User-visible behavior: NEWS (date the section when tagged). Generative AI is allowed; you own the diff. Keep docs plain.
