# DistSSHKitQueue.jl

> [!WARNING]
> **Under construction.** Do not use this.

[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/CI.yml?branch=main&label=Test)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/jetls.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e-daily.yml)

[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](DESIGN.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a FIFO waiter. The **queue host** holds the table and the waiter. The **client** (dev laptop) only enqueues, lists, and cancels.

Not on General yet. Design: [DESIGN.md](DESIGN.md). Julia **1.12+**, DistSSHKit **0.3.2+**.

## Queue host (always-on)

Queue lives here: store `~/.distsshkitqueue/jobs.toml`, waiter, optional OS unit. Install once in the **default** env (`pkg> add DistSSHKitQueue`; pre-General: `pkg> develop` a clone). Then:

```bash
# on the queue host
julia -m DistSSHKitQueue setup [--service]   # config.toml; optional LaunchAgent / systemd
julia -m DistSSHKitQueue serve               # optional; submit also auto-starts a waiter
julia -m DistSSHKitQueue stop                # stop the waiter, keep config / store
julia -m DistSSHKitQueue teardown -y         # waiter, unit, ~/.distsshkitqueue
```

`--qhost` is not valid here. `setup` / `serve` / `service` run only on this machine.

`stop` halts the waiter but leaves config, store, and any OS unit. It latches the waiter off, so `submit` will not auto-start it; only an explicit `serve` resumes. Clients can `--qhost HOST stop`.

`setup` writes `config.toml` if missing. Dedicated env `~/.distsshkitqueue/env` (if present) is preferred as `--project` so a checkout can be deleted. `teardown` does not `Pkg.rm` or delete a git clone or Kit `.distsshkit/` results.

## Client (dev laptop)

Job dir, `julia --project=.`. Queue must be loadable from that env. Nothing is written to the laptop (`no ~/.distsshkitqueue` on this machine). `--qhost HOST` picks the queue host (several clusters: pass it every time):

```bash
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts submit go SCRIPT.jl host:2
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts status
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts watch
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts cancel <id>
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts teardown -y
```

Remote Julia is Kit auto-detect (`--remote-julia` / `JULIA_DISTRIBUTED_EXE` override). `SCRIPT.jl` / `host:2` are interpreted **on the queue host**. `submit` auto-starts the waiter there. `watch` redraws `status` until Ctrl-C; it does not stop the waiter. With `--qhost`, ssh uses `-t` so the remote TTY can clear the screen.

## Same machine (laptop is the queue host)

Omit `--qhost`:

```bash
julia --project=. -m DistSSHKitQueue submit go SCRIPT.jl local:2
julia --project=. -m DistSSHKitQueue status
julia --project=. -m DistSSHKitQueue watch
```

Ctrl-C stops the waiter only. The waiter runs Kit `execute!(…; detached=true)`.
