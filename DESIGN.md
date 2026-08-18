# DistSSHKitQueue — design

Not a DistSSHKit.jl feature. Not a fork. Separate git repository.

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the hall: FIFO, occupancy, and a long-lived Julia process on an always-on host. Submitters `using DistSSHKitQueue`. Queue code `using DistSSHKit` (hard dependency). Direct kit use stays valid. `go` job files do not import the kit.

Name: DataFramesMeta pattern (parent + layer). `*HPC` is a bad AutoMerge fit. A Queue submodule would share SemVer with the kitchen.

## Layers

1. DistSSHKit — kitchen, one job.
2. DistSSHKitQueue — hall. The job table is the monitor (queued / running / done).

`pmap` is not the lab queue. JACC.jl belongs in Kit/jobs, not here.

## Shape

- Head: always-on host (Mac mini, Linux box, VM). Not a sleeping laptop.
- Platforms: macOS and Linux (WSL2 Ubuntu). Not native Windows (`ssh` / `rsync`).
- Occupancy: DistSSHKit `host:N`. FIFO. No preemption, no backfill.
- SSH: new `ssh` per job, as in `go`. Keepalives only during a long run.
- Workers: `Distributed.jl` processes, not threads. Same Pkg/Manifest story as the kit.
- Control plane: Julia only. No HyperQueue / Slurm CLI, no HTTP, no third-party supervisor as the user API.
- Compat: Julia **1.12+**, DistSSHKit **0.3**. The hall does not need newer language APIs.
- House files follow DistSSHKit, slimmed. CI is `Pkg.test` on 1.12 plus Gitleaks, not a Kit clone.

## Operations

User-facing actions are Julia (`using DistSSHKitQueue`) or the same via `julia -m DistSSHKitQueue` when `@main` exists (same `[apps.*]` pattern as DistSSHKit).

- `run_head` — load store, `step!` until interrupt
- `submit_go!` / `submit_drive!`
- `jobs` / `job` / `occupancy`
- `cancel!` — `:queued` only
- stop — `InterruptException` on the head loop; return, do not crash the REPL

Submit is **same process** as the head. `ssh` into the host and attach a REPL (or `-m`) is still one queue. No listen socket. `go!` / `drive!` run in that process.

Stopping the head does not cancel running kit/SSH children. If the process dies, persistence rules apply.

Boot auto-restart is optional. Julia helpers may write and control a unit; users should not hand-edit those files as the primary path. `launchctl` / `systemctl` stay inside the helpers.

| OS | Auto-start (optional) |
| --- | --- |
| macOS | launchd LaunchAgent |
| Linux | systemd user unit |

## In process

`Hall`, `submit_go!` / `submit_drive!`, `jobs` / `job`, `cancel!`, `step!`, `run_head`, TOML `store`. Change this file if the default changes.

`-m` and OS-service helpers are the same surface, not a second protocol. The in-memory hall does not depend on them.

### Job record

| Field | Meaning |
| --- | --- |
| `id` | Stable string (UUID). |
| `kind` | `:go` or `:drive`. |
| `script` | Path the kit would get. |
| `hosts` | DistSSHKit tokens (`local:2`, `user@mini:4`). |
| `state` | `:queued` / `:running` / `:done` / `:failed` / `:cancelled`. |
| `queued_at` / `started_at` / `finished_at` | UTC. |
| `error` | Short string if `:failed`. |

Kit kwargs (`args`, project, collect, …) travel as an opaque bag and are forwarded. Do not reimplement kit flags.

### Occupancy and FIFO

Parse `host:N` as DistSSHKit does. A job **fits** when every token’s free slots `>= N` for that host. Scan from the FIFO head; start the first job that fits. If job 1 needs 8 and 2 are free, job 2 does not jump.

Slots are held **per hall job**, not per `pmap` item. `drive` + `pmap` keeps all `host:N` workers until that drive returns.

Lab work is mostly `pmap`-shaped: allocated workers stay busy and tend to finish together, so the next job sees a clean block of slots. `go` is N independent runs; a slow replica can free N-1 slots while one run continues. FIFO does not fill that hole.

### Persistence

TOML on the head (`~/.distsshkitqueue/jobs.toml` or a start path). Same default on macOS and Linux. Rewrite the table on change.

On head death: reload `:queued`; mark `:running` as `:failed` (do not guess about `ssh` children). No automatic requeue.

### Failure

A kit throw marks `:failed`. The dispatcher takes the next fitting job. Do not stall the hall on one failure.

### Public names

Names can move; the split should not. Job files must not `using DistSSHKit` or `using DistSSHKitQueue`.

- `submit_go!(script, hosts...; kwargs...)` / `submit_drive!(…)` — enqueue, return `id`
- `jobs()` / `job(id)` / `occupancy`
- `cancel!(id)` — `:queued` only
- `run_head(; store=...)` — until interrupt

### Tests

`Pkg.test` needs no SSH. An SSH hall scenario borrows Kit `testenv/docker-ssh/scripts/up.sh` and `DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/distsshkit-linux-ssh-worker:latest`. Do not copy `testenv/` or the kit `test/e2e.jl` suite. Share a testenv repo only if both CIs own the same `up.sh`.

## Out of scope

- Scheduler inside DistSSHKit
- Weakdeps from Queue to Kit
- Glue package / `() -> go!(...)` callbacks
- Preemption, fair-share, priorities, reservations, backfill
- HTTP, remote submit, laptop-as-head
- Auto-retry of crashed `:running` jobs
- `:running` cancel (kit/SSH kill)
- Native Windows
- DistSSHKitWatch
- Org account, house CI template
- General registration until there is queue code

## GitHub

Private repo. Public later can keep history.

DistSSHKit [issue #50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) is the kit-side request this package answers. It is not a DistSSHKit feature and must not stay on a kit milestone. Close #50 when this hall is public enough to point at, with a comment that the scheduler is DistSSHKitQueue, not `schedule` in the kit. Until then, that link is maintainer-only.
