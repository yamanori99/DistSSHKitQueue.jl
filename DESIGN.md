# DistSSHKitQueue — design

Not a DistSSHKit.jl feature. Not a fork. Separate git repository.

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the always-on entry on the controller: FIFO (one table job at a time), a waiter, and records of where Kit wrote results. Queue does not swallow Kit. Direct kit use (bypass the queue) stays valid. `go` job files do not import the kit or the queue.

Queue code `using DistSSHKit` (hard dependency). Submitters `using DistSSHKitQueue` (and, later, may keep typing DistSSHKit names if Kit grows a thin hand-off).

Name: DataFramesMeta pattern (parent + layer). `*HPC` is a bad AutoMerge fit. A Queue submodule would share SemVer with DistSSHKit.

**Public names are placeholders.** Freeze them after the CLI feels right. Shape is pattern 2: one verb; kit kind via `--drive` / `drive=true`.

## Containment

The long-lived process on the controller is Queue. One table job runs at a time (the Kit master). Queue is not a bigger Kit. `host:N` is what that job passes to DistSSHKit; Queue does not keep a lab-wide slot ceiling.

```text
orderer A (laptop)  ──┐
orderer B (another) ──┼── enqueue / list / cancel ──►  controller (always-on)
orderer = controller ─┘                                  Queue waiter (one table)
                                                           └── current job: Kit master
                                                                 └── workers (this host + others)
```

- **Controller** — always-on host where the Kit master must run (Mac mini, Linux box, VM). Not a sleeping laptop. **One** waiter, **one** job table.
- **Orderer** — any machine that talks to that table (laptop, another workstation, the controller itself). Several orderers at once is the point. An orderer must not become the Kit master.
- **Workers** — DistSSHKit `host:N` / `local:N` on the controller and the other machines.

Jobs from every orderer share one FIFO. No per-user or per-machine queues (fair-share stays out of scope). Script paths and the project tree are what the **controller** will pass to Kit; orderers do not run `go!` locally.

Kit has no “master lives on that host” today: `go!` / `drive!` make the calling process the master. That is why Queue sits on the controller. A later DistSSHKit hook (`master=` or equivalent) may hide the hand-off behind Kit names. Until then, Queue is the face from every orderer; Kit remains the executor on the controller.

`pmap` is not the lab queue. JACC.jl belongs in DistSSHKit/jobs, not here.

## How the master sits under Queue

**First slice (now):** the waiter process calls `go!` / `drive!`. Orderers enqueue by writing the store (CLI `go` / `drive`). Same host: the REPL can `@async serve!(h)` and `placeholder!`.

**Later:** Queue only waits. Each table job is a child (`julia -m DistSSHKit go|drive …`). That child is the Kit master. Queue watches the PID, exit status, and Kit output paths. Use this when waiter and run must not share a fate.

Stopping the waiter does not cancel a running Kit/SSH tree. If the waiter process dies, persistence rules apply.

## Shape

- Platforms: macOS and Linux (WSL2 Ubuntu). Not native Windows (`ssh` / `rsync`).
- Occupancy / lab-wide `host:N` ceilings: Kit (`size!`, job tokens). Queue is FIFO, one table job.
- SSH to workers: new `ssh` per job, as in `go`. Keepalives only during a long run.
- Workers: `Distributed.jl` processes, not threads. Same Pkg/Manifest story as DistSSHKit.
- Control plane: Julia only. No HyperQueue / Slurm CLI, no HTTP, no third-party supervisor as the user API.
- Compat: Julia **1.12+**, DistSSHKit **0.3.1+**. Queue work uses `dev` / git until a kit hook needs a DistSSHKit General patch (see [CONTRIBUTING.md](CONTRIBUTING.md#distsshkit-cuts)).
- House files follow DistSSHKit, slimmed. CI is `Pkg.test` and JETLS on 1.12 plus Gitleaks, not a DistSSHKit clone.

## Operations

Day-to-day: Kit-shaped arguments (`script`, `host:N…`, kit kwargs). Queue adds wait, order, list, cancel-queued, and pointers to Kit output. Job files stay unchanged.

User-facing actions are Julia (`using DistSSHKitQueue`) or `julia -m DistSSHKitQueue`.

```bash
# controller: start the waiter (no subcommand is the same)
julia --project=Lab.jl -m DistSSHKitQueue serve
julia --project=Lab.jl -m DistSSHKitQueue status

# orderer: Kit argv, enqueue only (does not run go! / drive!)
ssh mini 'julia --project=Lab.jl -m DistSSHKitQueue go SCRIPT.jl mini:4'
ssh mini 'julia --project=Lab.jl -m DistSSHKitQueue drive local:2 SCRIPT.jl'
```

Store: `~/.distsshkitqueue/jobs.toml` (`DISTSSHKITQUEUE_STORE`). Whole-file rewrite under a directory lock. No listen socket, no HTTP, no `stop` subcommand (Ctrl-C / OS unit). Empty `-m DistSSHKitQueue` prints help; `serve` starts the waiter. Ctrl-C leaves the waiter; running Kit is not killed.

`serve` / `status` are Queue. `go` / `drive` are Kit's CLI, stored as a table row.

Order from anywhere **feel later (optional Kit change):** type DistSSHKit on the orderer (`go!(…; master="controller")`). DistSSHKit [issue #50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) / [#129](https://github.com/yamanori99/DistSSHKit.jl/issues/129) is that hand-off, not a scheduler inside DistSSHKit.

- `serve` / `serve!` — load store, one FIFO job at a time until interrupt
- `status` — print the table
- CLI `go` / `drive` — enqueue (Kit parsers)
- `placeholder!` — Julia enqueue (`drive=true` → `drive!`)
- `placeholder_cancel!` — `:queued` only

Boot auto-restart is optional. Julia helpers may write and control a unit; users should not hand-edit those files as the primary path. `launchctl` / `systemctl` stay inside the helpers.

| OS | Auto-start (optional) |
| --- | --- |
| macOS | launchd LaunchAgent |
| Linux | systemd user unit |

## In process

`Placeholder`, `placeholder!`, `serve!` / `serve`, `status` CLI, TOML `store`. Change this file if the default changes.

`-m` and OS-service helpers are the same surface, not a second protocol. The in-memory table does not depend on them.

First-slice tests and the controller REPL still pass an explicit `Placeholder` handle. The human-facing shape is Kit’s `script, hosts...; kwargs...` (handle optional / default queue on the controller).

### Job record

| Field | Meaning |
| --- | --- |
| `id` | Stable string (UUID). |
| `kind` | `:go` or `:drive`. |
| `script` | Path DistSSHKit would get (resolved on the controller). |
| `hosts` | DistSSHKit tokens (`local:2`, `user@box:4`). |
| `state` | `:queued` / `:running` / `:done` / `:failed` / `:cancelled`. |
| `queued_at` / `started_at` / `finished_at` | UTC. |
| `error` | Short string if `:failed`. |
| `result_path` | Where Kit already wrote (go batch root / drive `output_dir`). Queue records the path; it does not invent a second collect tree. |

Kit kwargs (`args`, `project`, `output_dir`, …) travel as an opaque bag and are forwarded. DistSSHKit **0.3.1+**: `go!` and `drive!` both take `output_dir`. Do not reimplement kit flags. `drive::Bool` is Queue-only and is not forwarded.

### FIFO

One table job at a time. `host:N` on the job is forwarded to DistSSHKit; Queue does not keep a lab-wide slot map. No backfill, no packing.

### Persistence

TOML on the controller (`~/.distsshkitqueue/jobs.toml` or a start path). Same default on macOS and Linux. Rewrite the table on change, with an exclusive lock so several orderer machines can enqueue. Remote enqueue in the first slice is “write this table on the controller,” not a second protocol.

On waiter death: reload `:queued`; mark `:running` as `:failed` (do not guess about `ssh` children). No automatic requeue.

### Failure

A DistSSHKit throw, `GoResult`/`DriveResult` with `ok=false`, or (later) a non-zero child exit marks `:failed`. The dispatcher takes the next fitting job. Do not stall the table on one failure.

### Public names

Placeholders. Split should not move: job files must not `using DistSSHKit` or `using DistSSHKitQueue`.

- `serve` / `status` (Queue). CLI `go` / `drive` (Kit argv, enqueue).
- `placeholder!` / `placeholder_list` / `placeholder_get` / `placeholder_cancel!` (Julia; names not frozen)
- `serve!` until interrupt (alias `placeholder_head`)

### Tests

`Pkg.test` needs no SSH. An SSH scenario borrows DistSSHKit `testenv/docker-ssh/scripts/up.sh` and `DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/distsshkit-linux-ssh-worker:latest`. Do not copy `testenv/` or the DistSSHKit `test/e2e.jl` suite. Share a testenv repo only if both CIs own the same `up.sh`.

## Out of scope

- Scheduler inside DistSSHKit (a `master=` / forward hook is allowed; a kit-side job table is not)
- Weakdeps from Queue to DistSSHKit
- Glue package / `() -> go!(...)` callbacks
- Lab-wide slot ceilings / occupancy packing (Kit `size!` / job tokens)
- Preemption, fair-share, priorities, reservations, backfill
- HTTP, listen socket, third-party queue APIs
- Laptop as Kit master when using Queue (sleeping laptop as waiter stays forbidden)
- Auto-retry of crashed `:running` jobs
- `:running` cancel (DistSSHKit/SSH kill)
- Queue-owned copy of Kit result trees (pointers only)
- Native Windows
- DistSSHKitWatch
- Org account, house CI template
- General registration until there is queue code

## GitHub

Private repo. Public later can keep history.

DistSSHKit [issue #50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) is the DistSSHKit-side request this package answers. It is not a DistSSHKit feature and must not stay on a DistSSHKit milestone. Close #50 when this package is public enough to point at, with a comment that the scheduler is DistSSHKitQueue, not `schedule` in DistSSHKit. A later kit hook only forwards enqueue to this package. Until then, that link is maintainer-only.
