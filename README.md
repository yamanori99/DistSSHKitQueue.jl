# DistSSHKitQueue.jl

> [!WARNING]
> **Under construction.** Do not use this.

[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/CI.yml?branch=main&label=Test)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/jetls.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e-daily.yml)

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](#compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a FIFO waiter that sits in front of it: the **queue host** holds the job table and the waiter, and any number of **clients** enqueue, list, watch, and cancel.

Not on General yet. Julia **1.12+**, DistSSHKit **0.3.2+**.

- [Concept](#concept)
- [Queue host (always-on)](#queue-host-always-on)
- [Client (dev laptop)](#client-dev-laptop)
- [Same machine](#same-machine-laptop-is-the-queue-host)
- [Job record](#job-record)
- [Out of scope](#out-of-scope)
- [Compatibility](#compatibility)

## Concept

The long-lived process on the queue host is Queue: one table job runs at a time (the Kit master). Queue is not a bigger Kit — `host:N` is what that job passes on to DistSSHKit, and Queue does not keep a lab-wide slot ceiling.

```text
client A (laptop)  ──┐
client B (another) ──┼── --qhost HOST  submit / status / watch / cancel / teardown ──►  queue host
client = queue host ─┘     (omit --qhost)                                        Queue waiter
                                                                               store ~/.distsshkitqueue
                                                                               setup / serve / service
```

- **Queue host** — always-on machine where the Kit master must run for queued jobs (macOS or Linux, a VM is fine). Not a sleeping laptop. **One** waiter, **one** job table.
- **Client** — any machine that talks to that table (laptop, another workstation, or the queue host itself). Several clients at once is the point. A client must not become the Kit master.
- **Workers** — DistSSHKit `host:N` / `local:N` on the queue host and the other machines.

Jobs from every client share one FIFO; there are no per-user or per-machine queues. The waiter calls DistSSHKit `execute!(kind, script, hosts; detached=true)` and waits — the child (`julia -m DistSSHKit go|drive`) is the Kit master, not the waiter itself. Stopping the waiter does not cancel a running Kit/SSH tree.

## Queue host (always-on)

Queue lives here: store `~/.distsshkitqueue/jobs.toml`, waiter, optional OS unit. Install once in the **default** env (`pkg> add DistSSHKitQueue`; pre-General: `pkg> develop` a clone). Then:

```bash
# on the queue host
julia -m DistSSHKitQueue setup [--force]       # config.toml (re-run is a no-op unless --force)
julia -m DistSSHKitQueue serve                 # optional; submit also auto-starts a waiter
julia -m DistSSHKitQueue stop                  # stop the waiter, keep config / store
julia -m DistSSHKitQueue service install       # boot auto-start (LaunchAgent / systemd user unit)
julia -m DistSSHKitQueue service uninstall     # remove that unit
julia -m DistSSHKitQueue teardown -y           # waiter, unit, ~/.distsshkitqueue
```

`--qhost` is not valid here — `setup` / `serve` / `service` run only on this machine.

`stop` halts the waiter but leaves config, store, and any OS unit in place. It latches the waiter off, so `submit` will not auto-start it again; only an explicit `serve` resumes it. Clients can also run `--qhost HOST stop`.

`setup` writes `config.toml` if it is missing; re-running it leaves an existing file untouched (`--force` rewrites it). A dedicated env at `~/.distsshkitqueue/env`, if present, is preferred as `--project` so the checkout can be deleted later. `teardown` never runs `Pkg.rm`, and never deletes a git clone or Kit's `.distsshkit/` results.

## Client (dev laptop)

Run from the job directory with `julia --project=.`; Queue must be loadable from that env. Nothing is written on the laptop (no `~/.distsshkitqueue` there). `--qhost HOST` picks the queue host — pass it every time if you work with several clusters:

```bash
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts submit go SCRIPT.jl host:2
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts status
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts watch
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts cancel <id>
julia --project=. -m DistSSHKitQueue --qhost m4-mini-ts teardown -y
```

Remote Julia is detected the same way DistSSHKit does (`--remote-julia` / `JULIA_DISTRIBUTED_EXE` to override). `SCRIPT.jl` and `host:2` are interpreted **on the queue host**, not on the client. `submit` auto-starts the waiter there if none is running. `watch` redraws `status` until Ctrl-C without stopping the waiter; with `--qhost` it uses `ssh -t` so the remote TTY can clear the screen.

## Same machine (laptop is the queue host)

Omit `--qhost`:

```bash
julia --project=. -m DistSSHKitQueue submit go SCRIPT.jl local:2
julia --project=. -m DistSSHKitQueue status
julia --project=. -m DistSSHKitQueue watch
```

Ctrl-C on `serve` or `watch` only stops that process — the waiter (or the live view), never a running Kit job. The waiter itself runs Kit's `execute!(…; detached=true)`.

## Job record

Each row in the table has: `id` (UUID), `kind` (`:go` / `:drive`), `script`, `hosts`, `state` (`:queued` / `:running` / `:done` / `:failed` / `:cancelled`), `queued_at` / `started_at` / `finished_at`, `error`, and `result_path` — wherever Kit already wrote its output. Queue only records that path; it does not keep a second copy of Kit's result tree. Kit kwargs (`args`, `project`, `output_dir`, …) travel as an opaque bag, forwarded through DistSSHKit's `execute!` allow-list.

The table is TOML on the queue host (`~/.distsshkitqueue/jobs.toml`), rewritten under a directory lock so several clients can enqueue at once. If the waiter dies: `:queued` rows reload on the next `serve`, and any `:running` row is marked `:failed` — there is no PID reattach and no automatic requeue.

## Out of scope

A scheduler inside DistSSHKit, weakdeps from Queue to DistSSHKit, a glue package, lab-wide slot ceilings or occupancy packing, preemption / fair-share / priorities / reservations / backfill, HTTP or a listen socket, a sleeping laptop as the waiter, auto-retry of crashed `:running` jobs, cancelling a `:running` job, a Queue-owned copy of Kit's result trees, and native Windows.

## Compatibility

macOS and Linux (WSL2 Ubuntu); not native Windows, since the kit shells out to `ssh` / `rsync`. Julia **1.12+**, DistSSHKit **0.3.2+** — Queue sits on Kit's `execute!` / `KitRunResult`.
