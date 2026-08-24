# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl` (unit + integration). Real SSH:

```bash
testenv/docker-ssh/scripts/up.sh --e2e
```

Apple silicon without Compose: [`testenv/apple-container-ssh`](../testenv/apple-container-ssh) (`./scripts/up.sh --e2e`, not CI). JETLS is `./.github/jetls-check.sh`. Aqua is `./.github/aqua-check.sh` (not `Pkg.test()`; CI job `Aqua`). Documenter is `docs/make.jl` (CI deploys).

## Layout

```text
test/
  runtests.jl           # Pkg.test() — unit + integration
  e2e.jl                # real OpenSSH; not Pkg.test()
  support.jl
  unit/
  integration/          # child julia and/or local DistSSHKit workers
  Project.toml
```

## Layers

Green on one layer does not imply the others. `Pkg.test()` does not run `e2e.jl`.

| Layer | Proves | Not |
| --- | --- | --- |
| JETLS | types / hints on entry files | runtime |
| Aqua | ambiguities, exports, compat | CLI / workers |
| unit | in-process queue / config | child julia, SSH |
| integration | child CLI (`-m DistSSHKitQueue`) and **parent:1** | real SSH / rsync |
| e2e | docker-ssh workers, waiter API, and `-m DistSSHKitQueue` (`--qhost` over loopback OpenSSH) | local-only CLI wiring |
| e2e daily | same `e2e.jl` from Linux, macOS Intel, or WSL2 (not a PR check) | macOS workers |

`enable` / `disable` / `teardown` in SSH E2E use `--write-only` (no runner systemd / LaunchAgent). Coverage: `Pkg.test` flag `pkgtest` on main push; `DSKQ_CODE_COVERAGE=1` on `up.sh --e2e` flag `e2e` (cut PRs and E2E daily Linux).
