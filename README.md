# DistSSHKitQueue.jl

> [!WARNING]
> **Under construction.** Do not use this.

[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/CI.yml?branch=main&label=Test)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/jetls.yml)
[![Aqua](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/aqua.yml?branch=main&label=Aqua)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/aqua.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e-daily.yml)

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](#compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Small-lab job queue on top of [DistSSHKit.jl](https://github.com/yamanori99/DistSSHKit.jl).

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is a FIFO waiter that sits in front of it: the **queue host** holds the job table and the waiter, and any number of **clients** enqueue, list, watch, and cancel.

Not on General yet. Julia **1.12+**, DistSSHKit **0.4.1+**.

- [Concept](#concept)
- [What to run](#what-to-run)
- [Queue host (always-on)](#queue-host-always-on)
- [Client (dev laptop)](#client-dev-laptop)
- [Job record](#job-record)
- [Out of scope](#out-of-scope)
- [Compatibility](#compatibility)

## Concept

A **client** is a **dev machine**. It does not run the queue. You point it at **one always-on queue host**. Any number of clients can do that; they share **one** FIFO table (one DistSSHKit job at a time).

```text
  clients = dev machines (no cap)          one queue host (always on)
  ───────────────────────────────          ──────────────────────────
  yours / a colleague's / …                waiter   one Kit job at a time
       │                                   table    ~/.distsshkitqueue
       │  julia -m DistSSHKitQueue         serve    now, this terminal
       │    qhost:NAME                     enable   again after reboot
       │    submit | status | add-host | list-host | watch | …
       └────────────────────────────────►  then DistSSHKit go/drive
                                           → workers (Kit tokens)
```

`qhost:NAME` is the SSH name of that box (same idea as Kit `child:NAME`, but it names the queue host, not a worker). Already logged in there? Omit it.

```bash
julia --project=. -m DistSSHKitQueue qhost:mini submit go child:host1:4 SCRIPT.jl
```

- **Queue host** — the always-on machine that holds the table and runs the Kit master for the current job (macOS or Linux; a VM is fine). One waiter, one table. A sleeping laptop is not this box.
- **Client** — a dev machine that submits, lists, watches, or cancels. No cap. It must not become the Kit master.
- **Workers** — where the script actually runs. DistSSHKit tokens: `parent[:N]` on the queue host, `child:NAME[:N]` on SSH machines.

Queue is not a bigger Kit and does not keep a lab-wide slot ceiling. The waiter starts DistSSHKit (`execute!(…; detached=true)`) and waits. Stopping the waiter does not cancel a Kit job that is already running.

## What to run

Day to day you only **submit** from a client (`qhost:HOST`). If no waiter is up, `submit` starts one on the queue host. You do not need `setup`, `serve`, or `enable` for a job to run.

| Command | What it does | When you need it |
| --- | --- | --- |
| `submit` | Enqueue a Kit `go` / `drive`. Starts a waiter if none is running. | Always (this is the product) |
| `list-host` | Read-only Kit names and host tokens (`parent` / `child:NAME`) plus `ssh -G` Host / HostName / User / Port. Not Kit `--hosts`. | See which host token to pass to `submit` |
| `add-host` | Write a Kit SSH name into config `hosts` (`parent` or `host1` / `child:host1`). First add creates the list (submit is no longer allow-all). | Lab inventory |
| `remove-host` | Drop a name from that list. Last name left is `hosts = []` (submit accepts none). | Lab inventory |
| `serve` | Run the waiter **in this terminal, now**. Ctrl-C stops this waiter. | Watching the queue live on the queue host, or running without autoserve |
| `enable` | Tell the OS: after reboot / login, start `serve` again (LaunchAgent / systemd). | A dedicated queue host that should come back by itself |
| `setup` | Write `~/.distsshkitqueue/config.toml` if missing (`--force` rewrites). | Optional. Defaults work without it. Use it for `store=` or `[env]`. |
| `stop` | Stop the waiter, keep files. `submit` will not auto-start until you `serve`. | Pause the queue |
| `disable` | Remove the OS unit. Does not delete the job table. | This machine should no longer auto-serve at boot |
| `teardown -y` | Stop waiter, remove unit and `~/.distsshkitqueue`. | Wipe Queue state on this host |

`serve` is “run the process”. `enable` is “register that process with the OS” (systemd’s word). They are not two ways to start the same thing. `enable` does not make a laptop a queue host.

## Queue host (always-on)

Install once in the **default** env (`pkg> add DistSSHKitQueue`; pre-General: `pkg> develop` a clone). DistSSHKit **0.4.1+** comes from General with it. The table lives at `~/.distsshkitqueue/jobs.toml`. Kit SSH names live in `config.toml` as `hosts`. Prefer CLI `add-host` / `remove-host` / `list-host` (hand-edit still works). Omit the key to allow any name. CLI `submit` reads that file; library `submit!` needs `Queue(; allowed=…)` and does not load `config.toml`.

### `add-host` / `remove-host` / `list-host`

Not DistSSHKit `--hosts` (that still names workers on `go` / `drive`). These verbs only touch the lab inventory and how SSH would connect. They do not enqueue. `list-host` does not print private keys or IdentityFile.

On the queue host:

```bash
julia -m DistSSHKitQueue add-host parent host1
julia -m DistSSHKitQueue list-host
julia -m DistSSHKitQueue remove-host host1
```

From a **client** the verbs are forwarded, like `status`. `ssh -G` still runs on the queue host, not on the client:

```bash
julia -m DistSSHKitQueue qhost:mini add-host host1
julia -m DistSSHKitQueue qhost:mini list-host
```

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

`qhost:HOST` is not valid here — `setup` / `serve` / `enable` / `disable` run only on this machine.

Already on that box (ssh session, console): omit `qhost:HOST` for `submit` / `status` / `watch` / `cancel` / `stop` / `teardown`. Kit argv is still DistSSHKit’s (`go child:NAME:N SCRIPT.jl`, or `parent:N` when workers are on the queue host).

`stop` halts the waiter but leaves config, store, and any OS unit. It latches the waiter off, so `submit` will not auto-start it; only an explicit `serve` resumes. Clients can `qhost:HOST stop`. `disable` is the opposite of `enable`, not of `serve`.

A dedicated env at `~/.distsshkitqueue/env`, if present, is preferred as `--project` so a checkout can be deleted. `teardown` never runs `Pkg.rm`, and never deletes a git clone or Kit `.distsshkit/` results.

Ctrl-C on `serve` or `watch` only stops that process — the waiter (or the live view), never a running Kit job.

## Client (dev laptop)

Run from the job directory with `julia --project=.`; Queue must be loadable from that env. Nothing is written on the laptop (no `~/.distsshkitqueue` there). `qhost:HOST` picks the queue host (same token style as Kit `child:NAME`). `--hosts` stays Kit's (workers). Pass `qhost:` every time if you work with several clusters:

```bash
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts add-host host1
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts list-host
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts submit go child:host:2 SCRIPT.jl
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts status
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts watch
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts cancel <id>
julia --project=. -m DistSSHKitQueue qhost:m4-mini-ts teardown -y
```

Remote Julia on the queue host is detected the same way DistSSHKit does (`--remote-julia` / `JULIA_DISTRIBUTED_EXE` to override). Kit `--julia` stays on `submit go` / `submit drive`. `SCRIPT.jl` and placement tokens are interpreted **on the queue host**, not on the client. `submit` auto-starts the waiter there if none is running. `watch` redraws `status` until Ctrl-C without stopping the waiter; with `qhost:HOST` it uses `ssh -t` so the remote TTY can clear the screen. Both print `qhost`: the token plus this machine's hostname (or `local (hostname)` when you omitted it). Job `HOSTS` stays DistSSHKit `parent[:N]` / `child:NAME[:N]`.

## Job record

Each row in the table has: `id` (UUID), `kind` (`:go` / `:drive`), `script`, `hosts`, `state` (`:queued` / `:running` / `:done` / `:failed` / `:cancelled`), `queued_at` / `started_at` / `finished_at`, `error`, and `result_path` — wherever Kit already wrote its output. Queue only records that path; it does not keep a second copy of Kit's result tree. Kit kwargs (`args`, `project`, `output_dir`, …) travel as an opaque bag, forwarded through DistSSHKit's `execute!` allow-list. The waiter also passes `job_id` (the row UUID) so Kit progress lines can carry `job=`.

The table is TOML on the queue host (`~/.distsshkitqueue/jobs.toml`), rewritten under a directory lock so several clients can enqueue at once. If the waiter dies: `:queued` rows reload on the next `serve`. A `:running` row whose DistSSHKit `kit.pid` is still alive stays `:running` (the waiter will not start the next FIFO job; it polls that pid). A `:running` row with no live `kit.pid` is `:done` or `:failed` from `kit.result` when that file exists, otherwise `:failed`.

## Out of scope

A scheduler inside DistSSHKit, weakdeps from Queue to DistSSHKit, a glue package, lab-wide slot ceilings or occupancy packing, preemption / fair-share / priorities / reservations / backfill, HTTP or a listen socket, a sleeping laptop as the waiter, auto-retry of crashed `:running` jobs, a Queue-owned copy of Kit's result trees, and native Windows.

## Compatibility

macOS and Linux (WSL2 Ubuntu); not native Windows, since the kit shells out to `ssh` / `rsync`. Julia **1.12+**, DistSSHKit **0.4.1+** — Queue sits on Kit's `execute!` / `KitProcess` / `kit.pid` / `kit.result`.
