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
- [What to run](#what-to-run)
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
                                                                               serve  (now)
                                                                               enable (after reboot)
```

- **Queue host** — always-on machine where the Kit master must run for queued jobs (macOS or Linux, a VM is fine). Not a sleeping laptop. **One** waiter, **one** job table.
- **Client** — any machine that talks to that table (laptop, another workstation, or the queue host itself). Several clients at once is the point. A client must not become the Kit master.
- **Workers** — DistSSHKit `host:N` / `local:N` on the queue host and the other machines.

Jobs from every client share one FIFO; there are no per-user or per-machine queues. The waiter calls DistSSHKit `execute!(kind, script, hosts; detached=true)` and waits — the child (`julia -m DistSSHKit go|drive`) is the Kit master, not the waiter itself. Stopping the waiter does not cancel a running Kit/SSH tree.

## What to run

Day to day you only **submit**. If no waiter is up, `submit` starts one. You do not need `setup`, `serve`, or `enable` for a job to run.

| Command | What it does | When you need it |
| --- | --- | --- |
| `submit` | Enqueue a Kit `go` / `drive`. Starts a waiter if none is running. | Always (this is the product) |
| `serve` | Run the waiter **in this terminal, now**. Ctrl-C stops this waiter. | Watching the queue live, or running without autoserve |
| `enable` | Tell the OS: after reboot / login, start `serve` again (LaunchAgent / systemd). | A dedicated queue host that should come back by itself |
| `setup` | Write `~/.distsshkitqueue/config.toml` if missing (`--force` rewrites). | Optional. Defaults work without it. Use it for `store=` or `[env]`. |
| `stop` | Stop the waiter, keep files. `submit` will not auto-start until you `serve`. | Pause the queue |
| `disable` | Remove the OS unit. Does not delete the job table. | This machine should no longer auto-serve at boot |
| `teardown -y` | Stop waiter, remove unit and `~/.distsshkitqueue`. | Wipe Queue state on this host |

`serve` is “run the process”. `enable` is “register that process with the OS” (systemd’s word). They are not two ways to start the same thing. A sleeping laptop should not be the queue host, with or without a unit.

## Queue host (always-on)

Install once in the **default** env (`pkg> add DistSSHKitQueue`; pre-General: `pkg> develop` a clone). The table lives at `~/.distsshkitqueue/jobs.toml`.

A dedicated always-on box (Mac mini, Linux VM):

```bash
# on the queue host
julia -m DistSSHKitQueue setup                 # optional config.toml
julia -m DistSSHKitQueue enable                # survive reboot
```

After that, clients only `submit`. You do not leave a `serve` terminal open; the OS unit runs it.

Foreground, this session only (no reboot registration):

```bash
julia -m DistSSHKitQueue serve
```

`--qhost` is not valid here — `setup` / `serve` / `enable` / `disable` run only on this machine.

`stop` halts the waiter but leaves config, store, and any OS unit. It latches the waiter off, so `submit` will not auto-start it; only an explicit `serve` resumes. Clients can `--qhost HOST stop`. `disable` is the opposite of `enable`, not of `serve`.

A dedicated env at `~/.distsshkitqueue/env`, if present, is preferred as `--project` so a checkout can be deleted. `teardown` never runs `Pkg.rm`, and never deletes a git clone or Kit `.distsshkit/` results.

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
