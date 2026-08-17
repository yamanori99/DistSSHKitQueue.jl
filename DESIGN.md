# DistSSHKitQueue — design

Not a DistSSHKit.jl feature. Not a fork. Separate git repository.

**DistSSHKit** runs **one** job (`go` / `drive`). **DistSSHKitQueue** is the hall: FIFO, occupancy, and a long-lived Julia process on an always-on Mac mini. Submitters `using DistSSHKitQueue`. Queue code `using DistSSHKit` (hard dependency). Direct kit use stays valid. `go` job files still do not import the kit.

General registry: names ending in lowercase are preferred (`*HPC` is a bad AutoMerge fit). `DistSSHQueue` looks like a sibling of Kit. `DistSSHKit.Queue` as a submodule shares SemVer with the kitchen. **DistSSHKitQueue** follows DataFramesMeta (parent name + layer). Later monitor: **DistSSHKitWatch**.

## Layers

1. DistSSHKit — kitchen, one job.
2. DistSSHKitQueue — hall. First “monitor” is the job table (queued / running / done).
3. DistSSHKitWatch (later) — host liveness, load, GPU. Hard-dep Kit; weak-dep Queue if overlaying the job table.

`pmap` is not the lab queue. JACC.jl belongs in Kit/jobs (Kit would use weakdeps), not in the queue.

## Shape

- Head node: always-on mini. MacBook is not the queue (sleeps, moves).
- Occupancy: `host:N` from DistSSHKit. FIFO. No preemption in v1.
- SSH: new `ssh` per job, same as current `go`. Keepalives only during a long run.
- Processes (`Distributed.jl`), not threads. Same Pkg/Manifest story as the kit.
- No HyperQueue / Slurm CLI. Julia in, Julia out.
- House files (LICENSE, docs stub, issue templates) follow DistSSHKit, slimmed.
- Minimal CI: `Pkg.test` on Julia 1.12 and Gitleaks. Not a copy of DistSSHKit slots, bake, or E2E.

## v1 implementation boundary

Code is not written yet. These choices are the default unless a later DESIGN edit says otherwise.

### Head process

One long-lived Julia process on the always-on mini. DistSSHKit `go!` / `drive!` run **in that process** (same as calling them from a REPL). Not HTTP, not a systemd-unrelated daemon protocol, not a MacBook.

v1 submit is from that same process (`using DistSSHKitQueue`). `julia -m DistSSHKitQueue` can wait. Remote submit from a sleeping MacBook is v2 (needs a listen path). The MacBook may `ssh` into the mini and attach a REPL; that is still “same process”, not a second queue.

Start/stop: a blocking `run_head()` (name TBD) is enough. Auto-restart on boot is an OS concern (`launchd`), not this package.

### Job record

Each row in the job table:

| Field | Meaning |
| --- | --- |
| `id` | Stable string (UUID). |
| `kind` | `:go` or `:drive`. |
| `script` | Path the kit would get. |
| `hosts` | DistSSHKit tokens (`local:2`, `user@mini:4`). |
| `state` | `:queued` / `:running` / `:done` / `:failed` / `:cancelled`. |
| `queued_at` / `started_at` / `finished_at` | UTC. |
| `error` | Short string if `:failed`. |

Kit kwargs (`args`, project, collect, …) travel with the row as an opaque bag and are forwarded to `go!` / `drive!`. Do not reimplement kit flags here.

### Occupancy and FIFO

Parse `host:N` the same way DistSSHKit does. A job **fits** when every token’s free slots `>= N` for that host (no packing across unrelated hosts beyond what the job asked for). Scan the FIFO from the head; start the first job that fits. No backfill that skips a blocked job in v1 (true FIFO: if job 1 needs 8 slots and only 2 are free, job 2 does not jump). No preemption.

The hall releases slots **per job**, not per `pmap` item. `drive` + `pmap` still holds all `host:N` workers until that drive returns.

Why true FIFO is the v1 default: lab work is expected to be mostly `pmap`-shaped. Items are farmed onto the allocated workers, so those workers stay busy and tend to finish together. The next hall job then sees a clean block of free slots, not a ragged hole.

`go` is different. `host:N` is N independent full runs. One slow replica can free N-1 slots while the last run is still going. True FIFO will not start a later smaller job in that hole. Backfill would; v1 does not. Holes show up when differently long `go` jobs share the minis, not inside a well-sized `pmap`.

### Persistence

A JSON file on the head (`~/.distsshkitqueue/jobs.json` or a path the head is started with). Rewrite the whole table on change. SQLite can wait.

If the head process dies: `:queued` rows reload; `:running` rows become `:failed` (do not guess whether `ssh` children finished). No automatic requeue in v1.

### Public Julia surface (intended)

Names can move; the split should not.

- `submit_go!(script, hosts...; kwargs...)` / `submit_drive!(script, hosts...; kwargs...)` — enqueue, return `id`.
- `jobs()` — snapshot of the table.
- `job(id)` — one row.
- `cancel!(id)` — `:queued` only in v1 (`:running` cancel is kit/SSH later).
- `run_head(; store=...)` — load table, dispatch loop until interrupt.

Job files passed to `go` still must not `using DistSSHKit` or `using DistSSHKitQueue`.

### Failure

A kit throw marks the job `:failed` and the dispatcher takes the next fitting job. Do not pause the whole hall on one failure.

## Non-goals (v1)

- Scheduler inside DistSSHKit (`schedule` CLI, in-kit daemon).
- Weakdeps from Queue to Kit (Kit is the engine, not optional glue).
- Third glue package. Callbacks `() -> go!(...)` can wait.
- Preemption, fair-share, priorities, reservations.
- HTTP API, MacBook-as-head, auto-retry of crashed `:running` jobs.
- Org account, house CI template (undecided).
- Public General registration until there is queue code.
- DistSSHKitWatch.

## GitHub

Private repo with a package shell. Public later can keep history.

DistSSHKit [issue #50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) (“Simple scheduler… handful of machines”) is the kit-side request this package answers. It is **not** a DistSSHKit feature and must not stay on a kit release milestone. Close #50 later, when this hall exists enough to point at (package + DESIGN), with a comment that the scheduler is DistSSHKitQueue, not `schedule` inside the kit. Until this repo is public, that link is maintainer-only.
