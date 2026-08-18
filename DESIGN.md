# DistSSHKitQueue — design

Not a DistSSHKit.jl feature. Not a fork. Separate git repository.

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is FIFO, occupancy, and a long-lived Julia process on an always-on host. Submitters `using DistSSHKitQueue`. Queue code `using DistSSHKit` (hard dependency). Direct kit use stays valid. `go` job files do not import the kit.

Name: DataFramesMeta pattern (parent + layer). `*HPC` is a bad AutoMerge fit. A Queue submodule would share SemVer with DistSSHKit.

**Public names are placeholders.** Freeze them after the CLI feels right. Shape is pattern 2: one verb; kit kind via `--drive` / `drive=true`.

## Layers

1. DistSSHKit — one job.
2. DistSSHKitQueue — the job table is the monitor (queued / running / done).

`pmap` is not the lab queue. JACC.jl belongs in DistSSHKit/jobs, not here.

## Shape

- Head: always-on host (Mac mini, Linux box, VM). Not a sleeping laptop.
- Platforms: macOS and Linux (WSL2 Ubuntu). Not native Windows (`ssh` / `rsync`).
- Occupancy: DistSSHKit `host:N`. FIFO. No preemption, no backfill.
- SSH: new `ssh` per job, as in `go`. Keepalives only during a long run.
- Workers: `Distributed.jl` processes, not threads. Same Pkg/Manifest story as DistSSHKit.
- Control plane: Julia only. No HyperQueue / Slurm CLI, no HTTP, no third-party supervisor as the user API.
- Compat: Julia **1.12+**, DistSSHKit **0.3**. Queue work uses `dev` / git until a kit hook needs a DistSSHKit General patch (see [CONTRIBUTING.md](CONTRIBUTING.md#distsshkit-cuts)).
- House files follow DistSSHKit, slimmed. CI is `Pkg.test` on 1.12 plus Gitleaks, not a DistSSHKit clone.

## Operations

User-facing actions are Julia (`using DistSSHKitQueue`) or the same via `julia -m DistSSHKitQueue` when `@main` exists (same `[apps.*]` pattern as DistSSHKit).

Placeholder CLI (names not frozen):

```bash
julia -m DistSSHKitQueue placeholder SCRIPT.jl host:N
julia -m DistSSHKitQueue placeholder --drive SCRIPT.jl host:N
julia -m DistSSHKitQueue placeholder-list
julia -m DistSSHKitQueue placeholder-get ID
julia -m DistSSHKitQueue placeholder-slots
julia -m DistSSHKitQueue placeholder-cancel ID
julia -m DistSSHKitQueue placeholder-head
```

- `placeholder_head` — load store, `placeholder_step!` until interrupt
- `placeholder!` — enqueue (`drive=true` → DistSSHKit `drive!`, else `go!`)
- `placeholder_list` / `placeholder_get` / `placeholder_slots`
- `placeholder_cancel!` — `:queued` only
- stop — `InterruptException` on the head loop; return, do not crash the REPL

Submit is **same process** as the head. `ssh` into the host and attach a REPL (or `-m`) is still one queue. No listen socket. DistSSHKit `go!` / `drive!` run in that process.

Stopping the head does not cancel running DistSSHKit/SSH children. If the process dies, persistence rules apply.

Boot auto-restart is optional. Julia helpers may write and control a unit; users should not hand-edit those files as the primary path. `launchctl` / `systemctl` stay inside the helpers.

| OS | Auto-start (optional) |
| --- | --- |
| macOS | launchd LaunchAgent |
| Linux | systemd user unit |

## In process

`Placeholder`, `placeholder!`, `placeholder_list` / `placeholder_get`, `placeholder_cancel!`, `placeholder_step!`, `placeholder_head`, TOML `store`. Change this file if the default changes.

`-m` and OS-service helpers are the same surface, not a second protocol. The in-memory table does not depend on them.

### Job record

| Field | Meaning |
| --- | --- |
| `id` | Stable string (UUID). |
| `kind` | `:go` or `:drive`. |
| `script` | Path DistSSHKit would get. |
| `hosts` | DistSSHKit tokens (`local:2`, `user@mini:4`). |
| `state` | `:queued` / `:running` / `:done` / `:failed` / `:cancelled`. |
| `queued_at` / `started_at` / `finished_at` | UTC. |
| `error` | Short string if `:failed`. |

Kit kwargs (`args`, project, collect, …) travel as an opaque bag and are forwarded. Do not reimplement kit flags. `drive::Bool` is Queue-only and is not forwarded.

### Occupancy and FIFO

Parse `host:N` as DistSSHKit does. A job **fits** when every token’s free slots `>= N` for that host. Scan from the FIFO head; start the first job that fits. If job 1 needs 8 and 2 are free, job 2 does not jump.

Slots are held **per table job**, not per `pmap` item. `drive` + `pmap` keeps all `host:N` workers until that drive returns.

Lab work is mostly `pmap`-shaped: allocated workers stay busy and tend to finish together, so the next job sees a clean block of slots. `go` is N independent runs; a slow replica can free N-1 slots while one run continues. FIFO does not fill that hole.

### Persistence

TOML on the head (`~/.distsshkitqueue/jobs.toml` or a start path). Same default on macOS and Linux. Rewrite the table on change.

On head death: reload `:queued`; mark `:running` as `:failed` (do not guess about `ssh` children). No automatic requeue.

### Failure

A DistSSHKit throw marks `:failed`. The dispatcher takes the next fitting job. Do not stall the table on one failure.

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

- Scheduler inside DistSSHKit
- Weakdeps from Queue to DistSSHKit
- Glue package / `() -> go!(...)` callbacks
- Preemption, fair-share, priorities, reservations, backfill
- HTTP, remote submit, laptop-as-head
- Auto-retry of crashed `:running` jobs
- `:running` cancel (DistSSHKit/SSH kill)
- Native Windows
- DistSSHKitWatch
- Org account, house CI template
- General registration until there is queue code

## GitHub

Private repo. Public later can keep history.

DistSSHKit [issue #50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) is the DistSSHKit-side request this package answers. It is not a DistSSHKit feature and must not stay on a DistSSHKit milestone. Close #50 when this package is public enough to point at, with a comment that the scheduler is DistSSHKitQueue, not `schedule` in DistSSHKit. Until then, that link is maintainer-only.
