# DistSSHKitQueue.jl

[English](README.md) | [日本語](README.ja.md)

[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/CI.yml?branch=main&label=Test)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHKitQueue.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/jetls.yml)
[![Aqua](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/aqua.yml?branch=main&label=Aqua)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/aqua.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKitQueue.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKitQueue.jl/actions/workflows/ssh-e2e-daily.yml)

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/requirements/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

DistSSHKitQueue runs jobs one after another on machines that several
people share. You can submit a job, check its status, and cancel.
[DistSSHKit](https://github.com/yamanori99/DistSSHKit.jl) does the run.
Supported on **macOS, Linux, and WSL2 Ubuntu** (not native Windows).

Even small labs and individuals can keep one always-on machine, add
SSH hosts, and use them together as a small set of compute nodes. Not
on General yet. Julia **1.12+**, DistSSHKit **0.4.1+**.

## Install

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

The queue host also needs **`ssh`**, **`rsync`**, and (only for git
deploys) **`git`** — `pkg> add` does not install them. Full requirements:
[Requirements](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/requirements/).

For everything else, see the
**[Documentation](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/)**.

## Usage

### Basic terms

- **Queue host** — the always-on machine that holds `~/.distsshkitqueue` and
  runs the waiter (macOS or Linux; a VM is fine). A sleeping laptop is not
  this box.
- **Client** — a dev machine that submits, lists, watches, or cancels. No
  cap. It must not become the Kit master.
- **Waiter** — the `serve` process on the queue host. It starts DistSSHKit
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

`qhost:NAME` is the SSH name of the queue host (same idea as Kit
`child:NAME`, but it names the queue host, not a worker). Already logged in
there? Omit it. One lab: `export DISTSSHKITQUEUE_HOST=…` and omit `qhost:`
(the token still wins). `--hosts` / `--julia` stay on Kit `go` / `drive`.

Placement tokens, `go` / `drive` flags, and remote setup are DistSSHKit's —
see the [kit docs](https://yamanori99.github.io/DistSSHKit.jl/stable/).

### Examples

From a **client** (job directory; Queue must be loadable from that env):

```bash
julia --project=. -m DistSSHKitQueue qhost:mini list-host
julia --project=. -m DistSSHKitQueue qhost:mini submit go child:host1:4 SCRIPT.jl
julia --project=. -m DistSSHKitQueue qhost:mini status
julia --project=. -m DistSSHKitQueue qhost:mini watch
julia --project=. -m DistSSHKitQueue qhost:mini cancel <id>
```

`submit` starts a waiter on the queue host if none is running.

On the **queue host** (once):

```bash
julia -m DistSSHKitQueue setup
julia -m DistSSHKitQueue add-host parent child:host1
julia -m DistSSHKitQueue enable --queue-env ~/.distsshkitqueue/env
```

`setup` / `serve` / `enable` / `disable` / `add-host` / `remove-host` refuse
`qhost:`. Command reference: [User Guide](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/manual/).

## Documentation

| | |
| --- | --- |
| Introduction | [Introduction](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/) |
| First Steps | [First Steps](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/requirements/) |
| User Guide | [User Guide](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/manual/) |
| API | [API](https://yamanori99.github.io/DistSSHKitQueue.jl/dev/api/) |
| News | [NEWS.md](NEWS.md) |

## Contributing

Bugs and feature requests: [Issues](https://github.com/yamanori99/DistSSHKitQueue.jl/issues).
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Source code is [MIT](LICENSE).
