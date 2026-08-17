# Contributing

Internals of this repo. Users: [README.md](README.md), [DESIGN.md](DESIGN.md), [NEWS.md](NEWS.md).

This is a **separate** package from DistSSHKit. Do not copy Kit E2E, Julia slots, bake, or `testenv/`. CI is `Pkg.test` on Julia 1.12 plus Gitleaks, not a Kit clone.

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to `ssh` / `rsync`).

- Library, `Pkg.test()`, and docs: Julia **1.12+**
- Hard dependency: DistSSHKit **0.3**

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
```

Layout: [test/README.md](test/README.md).

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
```

JETLS is the type gate when it is added. Do not commit `.vscode/settings.json` to silence the Language Server.

[Fatou](https://fatou.dev) is local only. Do not add `fatou.toml` or Fatou to `.vscode/extensions.json`.

### PR CI

Ubuntu: `Pkg.test` on **1.12**, Gitleaks. No slots, no SSH E2E, no Documenter deploy yet.

## Workflow

Branch from `main`. Squash-merge only. One reviewable change per PR; split unless `main` would be broken in between. Large plans: [DESIGN.md](DESIGN.md) first, then small PRs. Merged heads are deleted.

### Release

Not on General yet. When it is:

- `breaking`: incompatible behavior. Can land without a version bump.
- `cut`: `Project.toml` `version` went up.
- On a breaking line bump `x` in `0.x.y`; otherwise bump `y`.
- After merge: `@JuliaRegistrator register` on the **merge commit**, and paste the [NEWS.md](NEWS.md) section under `Release notes:`.

## Issues

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. Usage questions can wait until Discussions are on. Security: [SECURITY.md](SECURITY.md).

Every PR needs one type label (`bug` / `enhancement` / `chore`) when labels exist.

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links: `docs/src` and README. User-visible behavior: NEWS (date the section when tagged). Generative AI is allowed; you own the diff. Keep docs plain.
