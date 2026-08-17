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
- CI later via PkgTemplates, not a copy of DistSSHKit `.github` workflows, slots, bake, or E2E.

## Non-goals (v1)

- Scheduler inside DistSSHKit (`schedule` CLI, in-kit daemon).
- Weakdeps from Queue to Kit (Kit is the engine, not optional glue).
- Third glue package. Callbacks `() -> go!(...)` can wait.
- Org account, house CI template (undecided).
- Public General registration until there is queue code.

## GitHub

Private repo with a package shell. Public later can keep history. DistSSHKit issue #50 is **not** “implement a scheduler in the kit”; do not rewrite #50 as a Queue milestone.
