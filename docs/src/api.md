# [API](@id API)

```@meta
CurrentModule = DistSSHKitQueue
```

Julia entry points when you embed DistSSHKitQueue. Day-to-day work stays
on the CLI (`julia --project=. -m DistSSHKitQueue …`); see
[Introduction](@ref DistSSHKitQueue.jl),
[First Steps](@ref Tutorial-Prepare), and the [User Guide](@ref Manual).
REPL help also works (`?DistSSHKitQueue.submit!`).

Submitters `using DistSSHKitQueue`. Queue-host code `using DistSSHKit`.
Job files for Kit `go` still do not import DistSSHKit.

Prefer the CLI. From a client: `qhost:HOST` (not `--hosts`). Default
queue host: `DISTSSHKITQUEUE_HOST`. CLI `submit` uses `follow_config`; library
[`submit!`](@ref) uses `Queue(; allowed=…)` unless `follow_config=true`.
Config: `~/.distsshkitqueue/config.toml`.

```julia
using DistSSHKitQueue

q = Queue(; store=default_store_path(), follow_config=true)
id = submit!(q, "SCRIPT.jl", "child:host1:4"; kind=:go)
cancel!(q, id)
serve!(q)
```

## Types

```@docs
DistSSHKitQueue
Queue
Job
```

## Enqueue and cancel

```@docs
submit!
cancel!
```

## Table

```@docs
jobs
job
load!
step!
```

## serve

```@docs
serve!
```

## Paths

```@docs
job_project
```

`default_store_path()` is `~/.distsshkitqueue/jobs.toml`.
`serve` calls DistSSHKit `execute!(…; detached=true, job_id=…)`.
