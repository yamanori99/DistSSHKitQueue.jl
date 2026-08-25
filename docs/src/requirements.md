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

Install Queue in the **default** env (`pkg> add DistSSHKitQueue`;
pre-General: `pkg> add https://github.com/yamanori99/DistSSHKitQueue.jl#v0.1.0-beta.1`).
The table lives at `~/.distsshkitqueue/jobs.toml`.

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

Next: [Prepare](@ref Tutorial-Prepare).
