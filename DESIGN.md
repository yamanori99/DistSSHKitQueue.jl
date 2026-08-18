# DistSSHKitQueue — design

Not a DistSSHKit.jl feature. Not a fork. Separate git repository.

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the always-on entry on the controller: FIFO, occupancy, a waiter, and records of where Kit wrote results. Queue does not swallow Kit. Direct kit use (bypass the queue) stays valid. `go` job files do not import the kit or the queue.

Queue code `using DistSSHKit` (hard dependency). Submitters `using DistSSHKitQueue` (and, later, may keep typing DistSSHKit names if Kit grows a thin hand-off).

Name: DataFramesMeta pattern (parent + layer). `*HPC` is a bad AutoMerge fit. A Queue submodule would share SemVer with DistSSHKit.

**Public names are placeholders.** Freeze them after the CLI feels right. Shape is pattern 2: one verb; kit kind via `--drive` / `drive=true`.

## Containment

The long-lived process on the controller is Queue. The Kit **master** lives **under** it for one table job at a time. Queue is not a bigger Kit.

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

**First slice (now):** same Julia process. The waiter calls `go!` / `drive!`. While a job runs, that process **is** the Kit master. Enqueue from a REPL on the controller uses the same handle (`@async` the wait loop so the REPL can still submit).

**Later:** Queue only waits. Each table job is a child (`julia -m DistSSHKit go|drive …`). That child is the Kit master. Queue watches the PID, exit status, and Kit output paths. Use this when waiter and run must not share a fate.

Stopping the waiter does not cancel a running Kit/SSH tree. If the waiter process dies, persistence rules apply.

## Shape

- Platforms: macOS and Linux (WSL2 Ubuntu). Not native Windows (`ssh` / `rsync`).
- Occupancy: DistSSHKit `host:N`. FIFO. No preemption, no backfill.
- SSH to workers: new `ssh` per job, as in `go`. Keepalives only during a long run.
- Workers: `Distributed.jl` processes, not threads. Same Pkg/Manifest story as DistSSHKit.
- Control plane: Julia only. No HyperQueue / Slurm CLI, no HTTP, no third-party supervisor as the user API.
- Compat: Julia **1.12+**, DistSSHKit **0.3**. Queue work uses `dev` / git until a kit hook needs a DistSSHKit General patch (see [CONTRIBUTING.md](CONTRIBUTING.md#distsshkit-cuts)).
- House files follow DistSSHKit, slimmed. CI is `Pkg.test` on 1.12 plus Gitleaks, not a DistSSHKit clone.

## Operations

Day-to-day: Kit-shaped arguments (`script`, `host:N…`, kit kwargs). Queue adds wait, order, list, cancel-queued, and pointers to Kit output. Job files stay unchanged.

User-facing actions are Julia (`using DistSSHKitQueue`) or the same via `julia -m DistSSHKitQueue` when `@main` exists (same `[apps.*]` pattern as DistSSHKit).

Placeholder CLI (names not frozen):

```bash
# on the controller (waiter)
julia -m DistSSHKitQueue placeholder-head

# from any orderer: SSH into the controller (or a REPL already there)
julia -m DistSSHKitQueue placeholder SCRIPT.jl host:N
julia -m DistSSHKitQueue placeholder --drive SCRIPT.jl host:N
julia -m DistSSHKitQueue placeholder-list
julia -m DistSSHKitQueue placeholder-get ID
julia -m DistSSHKitQueue placeholder-slots
julia -m DistSSHKitQueue placeholder-cancel ID
```

Order from anywhere **first slice:** each orderer runs `ssh controller julia -m DistSSHKitQueue placeholder …` with the same tokens and kwargs Kit would take. The controller TOML is the hand-off. Whole-file rewrite under a lock so two orderers do not clobber the table. No listen socket, no HTTP.

Order from anywhere **feel later (optional Kit change):** keep typing DistSSHKit on the orderer (`go!(script, hosts...; master="controller")` or CLI equivalent). Kit must not start the master locally; it forwards the same argv to Queue on the controller. DistSSHKit [issue #50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) is the kit-side placeholder for that hand-off, not a scheduler inside DistSSHKit.

- `placeholder_head` — load store, `placeholder_step!` until interrupt
- `placeholder!` — enqueue (`drive=true` → DistSSHKit `drive!`, else `go!`)
- `placeholder_list` / `placeholder_get` / `placeholder_slots`
- `placeholder_cancel!` — `:queued` only
- stop — `InterruptException` on the wait loop; return, do not crash the REPL

Boot auto-restart is optional. Julia helpers may write and control a unit; users should not hand-edit those files as the primary path. `launchctl` / `systemctl` stay inside the helpers.

| OS | Auto-start (optional) |
| --- | --- |
| macOS | launchd LaunchAgent |
| Linux | systemd user unit |

## In process

`Placeholder`, `placeholder!`, `placeholder_list` / `placeholder_get`, `placeholder_cancel!`, `placeholder_step!`, `placeholder_head`, TOML `store`. Change this file if the default changes.

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
| result path | Where Kit already wrote (go batch root / drive output). Queue records the path; it does not invent a second collect tree. |

Kit kwargs (`args`, project, collect, …) travel as an opaque bag and are forwarded. Do not reimplement kit flags. `drive::Bool` is Queue-only and is not forwarded.

### Occupancy and FIFO

Parse `host:N` as DistSSHKit does. A job **fits** when every token’s free slots `>= N` for that host. Scan from the FIFO head; start the first job that fits. If job 1 needs 8 and 2 are free, job 2 does not jump.

Slots are held **per table job**, not per `pmap` item. `drive` + `pmap` keeps all `host:N` workers until that drive returns.

Lab work is mostly `pmap`-shaped: allocated workers stay busy and tend to finish together, so the next job sees a clean block of slots. `go` is N independent runs; a slow replica can free N-1 slots while one run continues. FIFO does not fill that hole.

### Persistence

TOML on the controller (`~/.distsshkitqueue/jobs.toml` or a start path). Same default on macOS and Linux. Rewrite the table on change, with an exclusive lock so several orderer machines can enqueue. Remote enqueue in the first slice is “write this table on the controller,” not a second protocol.

On waiter death: reload `:queued`; mark `:running` as `:failed` (do not guess about `ssh` children). No automatic requeue.

### Failure

A DistSSHKit throw (or non-zero child exit, later) marks `:failed`. The dispatcher takes the next fitting job. Do not stall the table on one failure.

### Public names

Placeholders. Split should not move: job files must not `using DistSSHKit` or `using DistSSHKitQueue`.

- `placeholder!(script, hosts...; drive=false, kwargs...)` — enqueue, return `id`
- `placeholder_list()` / `placeholder_get(id)` / `placeholder_slots`
- `placeholder_cancel!(id)` — `:queued` only
- `placeholder_head(; store=...)` — until interrupt

CLI stems match the Julia names without `!`. Decide the real verb after using `-m`.

### Tests

`Pkg.test` needs no SSH. An SSH scenario borrows DistSSHKit `testenv/docker-ssh/scripts/up.sh` and `DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/distsshkit-linux-ssh-worker:latest`. Do not copy `testenv/` or the DistSSHKit `test/e2e.jl` suite. Share a testenv repo only if both CIs own the same `up.sh`.

## Out of scope

- Scheduler inside DistSSHKit (a `master=` / forward hook is allowed; a kit-side job table is not)
- Weakdeps from Queue to DistSSHKit
- Glue package / `() -> go!(...)` callbacks
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
