# Tests

How this repo tests DistSSHKitQueue. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the Queue checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl` (unit + integration). It tags autoserve waiters and SIGTERMs them on exit or if `Pkg.test`'s parent dies, so Ctrl-C does not leave `nohup` `serve` on the laptop. Real SSH:

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
| e2e | docker-ssh workers, waiter API, and `-m DistSSHKitQueue` (`qhost:` over loopback OpenSSH) | local-only CLI wiring |
| e2e daily | same `e2e.jl` from Linux, macOS Intel, or WSL2 (not a PR check) | macOS workers |

`enable` / `disable` / `teardown` in SSH E2E use `--write-only` (no runner systemd / LaunchAgent). Coverage: `Pkg.test` max slot flag `pkgtest` on main push; `DSKQ_CODE_COVERAGE=1` on `up.sh --e2e` flag `e2e` (cut PRs and E2E daily Linux).

## SSH E2E roles

The product path is three **roles**, not three CI jobs and not two kinds of docker worker.

| Role | In `e2e.jl` today | Not |
| --- | --- | --- |
| **client** | loopback OpenSSH (`qhost:dskq-qh`) | a docker box |
| **qhost** | the machine that runs `--e2e` (waiter + Kit controller) | a worker container |
| **child** | docker-ssh / Apple boxes (`child:dskq-w1`, …) | the queue host |

Keep one `up.sh --e2e`. Do not split client↔qhost vs qhost↔child into two suites. Do not name a worker `qhost`. Kit child SSH stays DistSSHKit's E2E; Queue only needs `execute!` through the waiter.

`parent:1` in this suite occupies FIFO on the queue host. It is not a third worker topology.

SSH Host `dskq-w1` / `dskq-w2` vs Compose/DNS `child-1` / `child-2` is leftover (`dskq-` so Kit's stack can coexist). Aligning those names (`child-1` / `host1`, loopback `qh`) is naming review ([#35](https://github.com/yamanori99/DistSSHKitQueue.jl/issues/35)), not a 0.1.0 gate. Three physical hosts is dedicated-host smoke ([#46](https://github.com/yamanori99/DistSSHKitQueue.jl/issues/46)), not this file.
