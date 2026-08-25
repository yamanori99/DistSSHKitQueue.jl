# [DistSSHKitQueue.jl](@id DistSSHKitQueue.jl)

DistSSHKitQueue runs jobs one after another on machines that several
people share. You can submit a job, check its status, and cancel.
[DistSSHKit](https://github.com/yamanori99/DistSSHKit.jl) does the run.
Supported on **macOS, Linux, and WSL2 Ubuntu** (not native Windows).

Even small labs and individuals can keep one always-on machine, add
SSH hosts, and use them together as a small set of compute nodes. Not
on General yet. Julia **1.12+**, DistSSHKit **0.4.1+**. Placement tokens
(`parent[:N]` / `child:NAME[:N]`) stay DistSSHKit's — see the
[kit docs](https://yamanori99.github.io/DistSSHKit.jl/stable/).

## What is DistSSHKitQueue?

Day to day you **submit** from a client (`qhost:HOST`). If no waiter is up,
`submit` starts one on the queue host. You do not need `setup`, `serve`, or
`enable` for a job to run.

How you call it:

- **CLI** — `julia --project=. -m DistSSHKitQueue qhost:HOST submit go …`
- **Julia API** — `submit!` / `cancel!` / `serve!` on a [`Queue`](@ref)
  ([API](@ref API))

`qhost:NAME` names the queue host (like Kit `child:NAME`, but not a worker).
`--hosts` / `--julia` stay on Kit `go` / `drive`. Queue-host Julia is
`--remote-julia` / `JULIA_DISTRIBUTED_EXE`.

## Installation

From the Julia REPL, type `]` to enter the Pkg REPL mode and run:

```julia
pkg> add https://github.com/yamanori99/DistSSHKitQueue.jl#v0.1.0-beta.1
```

Or, equivalently, via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add(url="https://github.com/yamanori99/DistSSHKitQueue.jl", rev="v0.1.0-beta.1")
```

Not on General yet, so pin the beta tag by URL. DistSSHKit **0.4.1+** comes from
General with it. Do not `Pkg.develop` Kit for ordinary Queue work.

Also needs **`ssh`**, **`rsync`**, and **`git`** (git deploy only);
`pkg> add` does not install them. [Requirements](@ref).

## Basic terms

- **Queue host** — the always-on machine that holds `~/.distsshkitqueue`
  and runs the waiter. A sleeping laptop is not this box.
- **Client** — a dev machine that submits, lists, watches, or cancels. No
  cap. It must not become the Kit master.
- **Waiter** — `serve` on the queue host. It starts DistSSHKit
  (`execute!(…; detached=true)`) and waits. Stopping it does not cancel a
  Kit job that is already running.
- **Workers** — where the script runs. DistSSHKit tokens: `parent[:N]` on
  the queue host, `child:NAME[:N]` on SSH machines.

```text
  clients = dev machines (no cap)          one queue host (always on)
  ───────────────────────────────          ──────────────────────────
  yours / a colleague's / …                waiter   one Kit job at a time
       │                                   table    ~/.distsshkitqueue
       │  julia -m DistSSHKitQueue         add-host / remove-host
       │    qhost:NAME                     serve    now, this terminal
       │    submit | status | list-host    enable   again after reboot
       │    watch | cancel | …
       └────────────────────────────────►  then DistSSHKit go/drive
                                           → workers (Kit tokens)
```

Queue is not a bigger Kit and does not keep a lab-wide slot ceiling.
`serve` is “run the process”. `enable` is “register that process with the
OS”. They are not two ways to start the same thing.

## Next

Start at **[Requirements](@ref)**, then **[Prepare](@ref Tutorial-Prepare)**
(queue host, once) and **[First job](@ref Tutorial-Client)** (from a
laptop).

Later: [`submit`](@ref Manual-submit), [`status`](@ref Manual-status), and
the rest of the [User Guide](@ref Manual); or the **[API](@ref API)** to
embed from Julia.

## Contributing

Bugs and feature requests:
[Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See
[CONTRIBUTING.md](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/CONTRIBUTING.md).

## License

Source code is
[MIT](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/LICENSE).
