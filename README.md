# DistSSHQueue.jl

[English](README.md) | [日本語](README.ja.md)

[![Test](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHQueue.jl/graph/badge.svg)](https://codecov.io/gh/yamanori99/DistSSHQueue.jl)
[![Aqua](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/aqua.yml?branch=main&label=Aqua)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/aqua.yml)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/jetls.yml)
[![E2E](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/ssh-e2e.yml?branch=main&label=E2E)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/ssh-e2e.yml)

[![E2E weekly](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/ssh-e2e-weekly.yml?branch=main&label=E2E%20weekly)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/ssh-e2e-weekly.yml)
[![CI weekly](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHQueue.jl/ci-weekly.yml?branch=main&label=CI%20weekly)](https://github.com/yamanori99/DistSSHQueue.jl/actions/workflows/ci-weekly.yml)

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHQueue.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

DistSSHQueue runs jobs one after another on machines that several
people share. You can submit a job, check its status, and cancel.
[DistSSHKit](https://github.com/yamanori99/DistSSHKit.jl) does the run.
Supported on **macOS, Linux, and WSL2 Ubuntu** (not native Windows).

Even small labs and individuals can keep one always-on machine, add
SSH hosts, and use them together as a small set of compute nodes. Not
on General yet. Julia **1.12+**, DistSSHKit **0.4.2+**.

## Install

From the Julia REPL, type `]` to enter the Pkg REPL mode and run:

```julia
pkg> add https://github.com/yamanori99/DistSSHQueue.jl#v0.2.0-beta.1
```

Or, equivalently, via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add(url="https://github.com/yamanori99/DistSSHQueue.jl", rev="v0.2.0-beta.1")
```

Not on General yet. DistSSHKit **0.4.2+** comes from General with it.
Do not `Pkg.develop` Kit for ordinary Queue work. Pin `v0.2.0-beta.1`.
Git tag `v0.1.0-beta.1` is DistSSHKitQueue (old UUID); do not use it.

The queue host also needs **`ssh`**, **`rsync`**, and (only for git
deploys) **`git`** — `pkg> add` does not install them. Full requirements:
[Requirements](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/).

For everything else, see the
**[Documentation](https://yamanori99.github.io/DistSSHQueue.jl/dev/)**.

## Usage

### Basic terms

- **Queue host** — the always-on **macOS or Linux** box that holds
  `~/.distsshqueue` and runs `serve` (a VM is fine). A sleeping laptop
  is not this box. WSL2 is a client or worker, not this role.
- **Client** — a dev machine that submits, lists, watches, or cancels. No
  cap. It must not become the Kit master.
- **serve** — FIFO process on the queue host. It starts DistSSHKit
  (`execute!(…; detached=true)`). Stopping it does not cancel a
  Kit job that is already running.
- **Workers** — where the script runs. DistSSHKit tokens: `parent[:N]` on
  the queue host, `child:NAME[:N]` on SSH machines.

```text
  clients = dev machines (no cap)          one queue host (always on)
  ───────────────────────────────          ──────────────────────────
  yours / a colleague's / …                FIFO     one Kit job at a time
       │                                   table    ~/.distsshqueue
       │  julia -m DistSSHQueue         add-host / remove-host
       │    qhost:NAME                     serve    now, this terminal
       │    submit | status | list-host    enable   again after reboot
       │    watch | cancel | …
       └────────────────────────────────►  then DistSSHKit go/drive
                                           → workers (Kit tokens)
```

`qhost:NAME` is the SSH name of the queue host (same idea as Kit
`child:NAME`, but it names the queue host, not a worker). Already logged in
there? Omit it. One lab: `export DISTSSHQUEUE_HOST=…` and omit `qhost:`
(the token still wins). `--hosts` / `--julia` stay on Kit `go` / `drive`.

Placement tokens, `go` / `drive` flags, and remote setup are DistSSHKit's —
see the [kit docs](https://yamanori99.github.io/DistSSHKit.jl/stable/).

### Where files live

`qhost:` is the SSH name of the queue host, not a storage prefix. The
table and Kit result dirs stay **on that box**. The client has no
`~/.distsshqueue`. `qhost:` submit rsyncs the client job tree to
`~/.distsshqueue/stage/<id>`; Kit still copies queue host → workers.

#### Client

```text
~/my-job/
  Project.toml          DistSSHQueue (CLI)
  Manifest.toml
  SCRIPT.jl             rsync'd on qhost: submit
```

#### Queue host

`~/.distsshqueue` plus **one Kit tree per job** (`qhost:`:
`stage/<id>/`, or omit `qhost:`: unique `~/org/Repo.jl`). Not `--queue-env`.
Do
not set `DISTRIBUTED_REMOTE_PROJECT_ROOT` in shared `config.toml`.
`submit` errors if a second project would land on the same worker path.

```text
~/.distsshqueue/
  config.toml
  jobs.toml             every row (no prune)
  jobs.toml.log
  jobs.toml.pid         while serve is up
  jobs.toml.stopped     after stop, until serve
  env/                  --queue-env / enable default
    Project.toml
    Manifest.toml
  stage/<id>/           client tree after qhost: submit

~/org/Repo.jl/          omit qhost: (cwd / DISTRIBUTED_PROJECT_ROOT)
  Project.toml          compute deps
  SCRIPT.jl
  .distsshkit/go/
    SCRIPT_<UTC>_<id>/  result_path
      kit.pid
      kit.result
```

`enable` (optional; skip if you only `serve` in a terminal):

- **macOS** — `~/Library/LaunchAgents/org.distsshqueue.serve.plist`
- **Linux / WSL2** — `~/.config/systemd/user/distsshqueue.serve.service`

User units (no root). Same command: `julia --project=<queue-env> -m DistSSHQueue serve`.

#### Workers

No Queue table. Kit default `~/parent/Repo.jl` (not a shared `[env]`
remote).
Collect lands in the queue-host `.distsshkit/` dir above.

```text
<remote project root>/
  Project.toml
  SCRIPT.jl
```

### Examples

From a **client** (job directory; Queue must be loadable from that env):

```bash
julia --project=. -m DistSSHQueue qhost:mini list-host
julia --project=. -m DistSSHQueue qhost:mini submit go child:host1:4 SCRIPT.jl
julia --project=. -m DistSSHQueue qhost:mini status
julia --project=. -m DistSSHQueue qhost:mini watch
julia --project=. -m DistSSHQueue qhost:mini cancel <id>
```

`submit` starts `serve` on the queue host if none is running. Job ids are a
bare stdout line; stderr shows `Queued  N` unless `DISTSSHKIT_QUIET` is set.

On the **queue host** (once):

```bash
cd ~/.distsshqueue/env
julia --project=. -m DistSSHQueue setup
julia --project=. -m DistSSHQueue add-host parent child:host1
julia --project=. -m DistSSHQueue enable --queue-env ~/.distsshqueue/env
```

`setup` / `serve` / `enable` / `disable` / `add-host` / `remove-host` refuse
`qhost:`. Command reference: [User Guide](https://yamanori99.github.io/DistSSHQueue.jl/dev/manual/).

## Documentation

| | |
| --- | --- |
| Introduction | [Introduction](https://yamanori99.github.io/DistSSHQueue.jl/dev/) |
| First Steps | [First Steps](https://yamanori99.github.io/DistSSHQueue.jl/dev/requirements/) |
| User Guide | [User Guide](https://yamanori99.github.io/DistSSHQueue.jl/dev/manual/) |
| API | [API](https://yamanori99.github.io/DistSSHQueue.jl/dev/api/) |
| News | [NEWS.md](NEWS.md) |

## Contributing

Bugs and feature requests: [Issues](https://github.com/yamanori99/DistSSHQueue.jl/issues).
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Source code is [MIT](LICENSE).
