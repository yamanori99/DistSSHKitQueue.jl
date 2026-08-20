# DistSSHKitQueue — design

Not a DistSSHKit.jl feature. Not a fork. Separate git repository.

**DistSSHKit** runs one job (`go` / `drive`). **DistSSHKitQueue** is the always-on entry on the controller: FIFO (one table job at a time), a waiter, and records of where Kit wrote results. Queue does not swallow Kit. Direct kit use (bypass the queue) stays valid. `go` job files do not import the kit or the queue.

Queue code `using DistSSHKit` (hard dependency). Submitters `using DistSSHKitQueue` (and, later, may keep typing DistSSHKit names if Kit grows a thin hand-off).

Name: DataFramesMeta pattern (parent + layer). `*HPC` is a bad AutoMerge fit. A Queue submodule would share SemVer with DistSSHKit.

Queue verbs: `serve`, `status`, `submit`, `cancel`, `setup`, `service`. After `submit`, Kit’s `go` / `drive` argv.
Julia: `Queue`, `submit!(q, script, hosts...; kind=:go|:drive)`, `job` / `jobs`, `cancel!`, `serve!`.

## Containment

The long-lived process on the controller is Queue. One table job runs at a time (the Kit master). Queue is not a bigger Kit. `host:N` is what that job passes to DistSSHKit; Queue does not keep a lab-wide slot ceiling.

```text
orderer A (laptop)  ──┐
orderer B (another) ──┼── enqueue / list / cancel ──►  controller (always-on)
orderer = controller ─┘                                  Queue waiter (one table)
                                                           └── execute!(kind; detached=true)
                                                                 └── Kit child master
                                                                       └── workers (this host + others)
```

- **Controller** — always-on host where the Kit master must run (macOS or Linux, a VM is fine). Not a sleeping laptop. **One** waiter, **one** job table.
- **Orderer** — any machine that talks to that table (laptop, another workstation, the controller itself). Several orderers at once is the point. An orderer must not become the Kit master.
- **Workers** — DistSSHKit `host:N` / `local:N` on the controller and the other machines.

Jobs from every orderer share one FIFO. No per-user or per-machine queues (fair-share stays out of scope). Script paths and the **job** project tree are what the controller will pass to Kit; they are not the waiter's Julia `--project`. Orderers do not run `go!` locally.

Kit has no “master lives on that host” today: `go!` / `drive!` make the calling process the master. That is why Queue sits on the controller. A later DistSSHKit hook (`master=` or equivalent) may hide the hand-off behind Kit names. Until then, Queue is the face from every orderer; Kit remains the executor on the controller.

`pmap` is not the lab queue. JACC.jl belongs in DistSSHKit/jobs, not here.

## How the master sits under Queue

The waiter calls DistSSHKit `execute!(kind, script, hosts; detached=true)` and `wait`s. The child (`julia -m DistSSHKit go|drive`) is the Kit master. Queue does not call `go!` / `drive!` in the waiter process. Orderers enqueue by writing the store (`submit go` / `submit drive`). Same host: the REPL can `@async serve!(q)` and `submit!`.

Stopping the waiter does not cancel a running Kit/SSH tree. If the waiter dies, persistence rules apply (stale `:running` → `:failed`; no PID reattach).

## Shape

- Platforms: macOS and Linux (WSL2 Ubuntu). Not native Windows (`ssh` / `rsync`).
- Occupancy / lab-wide `host:N` ceilings: Kit (`size!`, job tokens). Queue is FIFO, one table job.
- SSH to workers: new `ssh` per job, as in `go`. Keepalives only during a long run.
- Workers: `Distributed.jl` processes, not threads. Same Pkg/Manifest story as DistSSHKit.
- Control plane: Julia only. No HyperQueue / Slurm CLI, no HTTP, no third-party supervisor as the user API.
- Compat: Julia **1.12+**, DistSSHKit **0.3.2+**. Queue sits on Kit `execute!` / `KitRunResult` (see [CONTRIBUTING.md](CONTRIBUTING.md#distsshkit-cuts)).
- House files follow DistSSHKit, slimmed. CI is `Pkg.test`, JETLS, PR SSH E2E on 1.12, Gitleaks, and schedule-only E2E daily (no Julia slots).

## Operations

Day-to-day: Kit-shaped arguments (`script`, `host:N…`, kit kwargs). Queue adds wait, order, list, cancel-queued, and pointers to Kit output. Job files stay unchanged.

User-facing actions are Julia (`using DistSSHKitQueue`) or `dskq` (shim from `setup`, or `julia -m DistSSHKitQueue`).

```bash
# controller, once
julia --project=<queue-env> -m DistSSHKitQueue setup --service

# orderer: write the table (does not run Kit). Non-interactive ssh: use the absolute path.
ssh controller 'cd /work/Thesis.jl && ~/.local/bin/dskq submit go SCRIPT.jl worker:4'
ssh controller 'cd /work/Other.jl && ~/.local/bin/dskq submit drive local:2 SCRIPT.jl'
ssh controller '~/.local/bin/dskq cancel <id>'
ssh controller '~/.local/bin/dskq status'
```

`<queue-env>` loads Queue. The **job** tree is Kit’s (`job_project()`: `pwd` / `DISTRIBUTED_PROJECT_ROOT`), stored on the row. Students keep separate projects; Queue is not a dependency of each job.

Config: `~/.distsshkitqueue/config.toml` (`DISTSSHKITQUEUE_CONFIG`). `store` and `[env]` (applied with `get!` so ENV wins). Store default `~/.distsshkitqueue/jobs.toml` (`DISTSSHKITQUEUE_STORE` > config `store=`). Whole-file rewrite under a directory lock. No listen socket, no HTTP, no `stop` subcommand (Ctrl-C / OS unit). Empty `-m DistSSHKitQueue` prints help; `serve` starts the waiter. Ctrl-C leaves the waiter; running Kit is not killed.

`setup` writes `~/.local/bin/dskq` (julia absolute path + `--project=<queue-env>` + `--startup-file=no`). Julia 1.12 Pkg Apps (`[apps] dskq`) is an optional second path (`pkg> app add .` → `~/.julia/bin/dskq`). Neither PATH is guaranteed in non-interactive ssh.

`serve` / `status` / `submit` / `cancel` are Queue. After `submit`, `go` / `drive` are Kit's CLI, stored as a table row. Bare `go` / `drive` remain aliases of `submit`. DistSSHKit **0.3.2** `execute!` is the waiter’s Kit seam ([issue #129](https://github.com/yamanori99/DistSSHKit.jl/issues/129)). Orderer `go!(…; master="controller")` is still a later Kit hook, not a scheduler inside DistSSHKit.

- `setup` — write `dskq` + config.toml if missing (`--service` also installs the OS unit)
- `serve` / `serve!` — load store, one FIFO job at a time until interrupt (`serve --interval`)
- `status` — print the table
- CLI `submit go` / `submit drive` — enqueue (Kit parsers). Bare `go` / `drive` are aliases.
- `submit!(q, …; kind=:drive)` — Julia enqueue
- `cancel` / `cancel!` — `:queued` only (reloads the store; not `load!`)

Boot auto-restart is optional. Julia helpers may write and control a unit; users should not hand-edit those files as the primary path. `launchctl` / `systemctl` stay inside the helpers.

| OS | Auto-start (optional helper) |
| --- | --- |
| macOS | `service install` → `~/Library/LaunchAgents/org.distsshkitqueue.serve.plist` |
| Linux | `service install` → `~/.config/systemd/user/distsshkitqueue.serve.service` |

## In process

`Queue`, `Job`, `submit!`, `serve!` / `serve`, `status` / `cancel` CLI, TOML `store`. The waiter’s Kit call is `execute!(…; detached=true)`. Change this file if the default changes.

`-m` and OS-service helpers are the same surface, not a second protocol. The in-memory table does not depend on them.

First-slice tests and the controller REPL still pass an explicit `Queue` handle. The human-facing shape is Kit’s `script, hosts...; kwargs...` (handle optional / default queue on the controller).

### Job record

| Field | Meaning |
| --- | --- |
| `id` | Stable string (UUID). |
| `kind` | `:go` or `:drive`. |
| `script` | Path DistSSHKit would get (absolute at `submit` time). |
| `hosts` | DistSSHKit tokens (`local:2`, `user@box:4`). |
| `state` | `:queued` / `:running` / `:done` / `:failed` / `:cancelled`. |
| `queued_at` / `started_at` / `finished_at` | UTC. |
| `error` | Short string if `:failed`. |
| `result_path` | Where Kit already wrote (go batch root / drive `output_dir`). Queue records the path; it does not invent a second collect tree. |

Kit kwargs (`args`, `project`, `output_dir`, …) travel as an opaque bag. The waiter forwards the DistSSHKit `execute!(...; detached=true)` allow-list (`yes=true`). Do not reimplement kit flags. Names Kit rejects (`path_anchor`, …) are dropped.

### FIFO

One table job at a time. `host:N` on the job is forwarded to DistSSHKit; Queue does not keep a lab-wide slot map. No backfill, no packing.

### Persistence

TOML on the controller (`~/.distsshkitqueue/jobs.toml` or a start path). Same default on macOS and Linux. Rewrite the table on change, with an exclusive lock so several orderer machines can enqueue. Remote enqueue in the first slice is “write this table on the controller,” not a second protocol.

On waiter death: reload `:queued`; mark `:running` as `:failed` (do not guess about `ssh` children). No automatic requeue.

### Failure

A DistSSHKit throw or `KitRunResult` with `ok=false` (including a non-zero child exit) marks `:failed`. The dispatcher takes the next queued job. Do not stall the table on one failure.

### Public names

Job files must not `using DistSSHKit` or `using DistSSHKitQueue`.

- CLI: `setup` / `serve` / `status` / `submit go` / `submit drive` / `cancel` / `service install` / `service uninstall`
- Julia: `Queue`, `Job`, `submit!`, `job` / `jobs`, `cancel!`, `step!`, `load!`, `serve!` / `serve`

### Tests

`Pkg.test` needs no SSH (`test/unit/`). SSH E2E is this repo’s `testenv/docker-ssh` (`up.sh --e2e` / `test/e2e.jl`). CLI E2E (`DSKQ_CLI_E2E=1 julia --project=. test/cli_e2e.jl`) is `dskq` + `local:1`, not Docker. PR CI uploads Codecov flags `pkgtest` and `e2e` (OIDC, carryforward). Daily E2E (Linux / macOS / WSL) does not upload coverage. JETLS is `.github/jetls-check.sh`. Aqua is local `.github/aqua-check.sh` until CI.

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
