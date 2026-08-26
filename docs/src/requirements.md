# Requirements

Prerequisites for [Introduction](@ref DistSSHKitQueue.jl) and
[Prepare](@ref Tutorial-Prepare). DistSSHKit's own checks
([kit Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/))
still apply to workers. This page is Queue: queue host vs client.

`pkg> add DistSSHKitQueue` does not install **`ssh`**, **`rsync`**, or
**`git`**. (Pre-General: `pkg> add https://github.com/yamanori99/DistSSHKitQueue.jl#v0.1.0-beta.1`.)

## All machines

Applies to the **queue host**, each **client**, and each SSH host that
runs jobs.

- **macOS, Linux, and WSL2 Ubuntu** (not native Windows)
- **Julia 1.12+**
  - Same **major.minor** on the queue host and SSH workers (DistSSHKit
    `setup --check` fails on a mismatch unless `--ignore-julia-version`)
  - Prefer
    **[juliaup](https://github.com/JuliaLang/juliaup)** at
    `$HOME/.juliaup/bin/julia`
- **DistSSHKit 0.4.1+** from General. Do not `Pkg.develop` Kit for
  ordinary Queue work

WSL2 is Linux, with DistSSHKit's extra rules: run **inside** the distro,
keep the project on the Linux filesystem (`~/…`), not `/mnt/c/…`.

## Queue host

Always-on box (Mac mini, Linux VM). A sleeping laptop is not this
machine.

Install Queue in **`~/.distsshkitqueue/env`** (`julia --project=.` there;
pre-General: `pkg> add https://github.com/yamanori99/DistSSHKitQueue.jl#v0.1.0-beta.1`).
Client hops use that path (`--queue-env`). The table lives at
`~/.distsshkitqueue/jobs.toml`.

Also install, as in DistSSHKit (the kit parent for each job is this
machine):

- **`ssh`** — passwordless login to each worker
- **`rsync`** — collect / rsync deploy
- **`git`** — git deploy path only

Do not set `DISTSSHKITQUEUE_HOST` here (or in `config.toml` `[env]`).
That name is a **client** default for `qhost:`.

## Client

A dev laptop. Nothing is written there (no `~/.distsshkitqueue` on the
client). Queue must be loadable from the job env (`julia --project=.`).

- Passwordless SSH from the client to the **queue host** (`qhost:NAME`)
- Queue-host Julia: auto, or `--remote-julia` /
  `JULIA_DISTRIBUTED_EXE` (same detection as DistSSHKit)

`SCRIPT.jl` and placement tokens are interpreted **on the queue host**,
not on the client.

## Workers

DistSSHKit hosts. Passwordless SSH **from the queue host**, Julia
1.12+ with the same major.minor. Details:
[kit Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

## [Where files live](@id Layout)

Typical paths. `qhost:` is the SSH name of the queue host, not a
storage prefix. The table and Kit result dirs accumulate **on that
box**. Queue does not copy Kit trees. `teardown` removes
`~/.distsshkitqueue`, not a git clone or `.distsshkit/`.

One Kit clone per job on the queue host, with a unique path
(`~/org/Repo.jl`, same layout DistSSHKit uses). Queue has no extra job
name. Hop `SCRIPT.jl` is that tree on the queue host, not the laptop
cwd. Do not pin `DISTRIBUTED_REMOTE_PROJECT_ROOT` in the shared
`config.toml` `[env]`: Kit's default worker path is
`~/basename(parent)/basename(job-tree)`. Same parent name plus same
repo name collide on workers even if the queue-host absolute paths
differ. `submit` then errors (it does not rename or `setup --delete`).
Same tree may be submitted again. Run leaves (`SCRIPT_<UTC>_<id>/`) are
unique inside one tree. If Kit `setup` already filled that remote,
`go` would run whatever is there; Queue refuses the second tree first.

### Client tree

No `~/.distsshkitqueue`. The job env only needs Queue loadable for the
CLI.

```text
~/my-job/
  Project.toml          DistSSHKitQueue (CLI)
  Manifest.toml
  SCRIPT.jl             interpreted on the queue host
```

### Queue-host tree

Queue state plus **one Kit clone per job** (not the Queue env). `enable` writes an OS
unit; skip that file if you only `serve` in a terminal.

```text
~/.distsshkitqueue/
  config.toml
  jobs.toml             every row (no prune)
  jobs.toml.log
  jobs.toml.pid         while serve is up
  jobs.toml.stopped     after stop, until serve
  env/                  hop / enable default (--queue-env)
    Project.toml
    Manifest.toml

~/org/Repo.jl/          one clone per job (cwd / DISTRIBUTED_PROJECT_ROOT)
  Project.toml          compute deps
  Manifest.toml
  SCRIPT.jl
  .distsshkit/go/       result_path (allocate_output_dir)
    SCRIPT_<UTC>_<id>/
      kit.pid
      kit.result
```

`enable` unit (same `julia --project=<queue-env> -m DistSSHKitQueue serve`):

- **macOS** — `~/Library/LaunchAgents/org.distsshkitqueue.serve.plist`
- **Linux / WSL2** — `~/.config/systemd/user/distsshkitqueue.serve.service`

Both are user units (no root). `disable` removes that file. The table
and Kit dirs do not change.

### Worker tree

No Queue table. Kit default `~/parent/Repo.jl` from that clone (do not
pin `DISTRIBUTED_REMOTE_PROJECT_ROOT` in shared queue config). Collect
lands on the queue host `.distsshkit/` dir above.

```text
<remote project root>/
  Project.toml
  SCRIPT.jl
```

Next: [Prepare](@ref Tutorial-Prepare).
