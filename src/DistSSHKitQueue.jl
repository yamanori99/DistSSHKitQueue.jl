"""
DistSSHKitQueue — FIFO waiter for DistSSHKit (`go` / `drive`).

Package entry: exports, `include`s, `main` (`@main` on Julia 1.12+).
FIFO: `src/DistSSHKitQueue/`. Client CLI: `src/client/`. Queue host CLI: `src/qhost/`.
Waiter runs DistSSHKit `execute!(...; detached=true)`.
`--project=<queue-env>` loads this package; the job tree is `job_project()`.
`dskq` is a shim from `setup` (or Pkg Apps). Config: `~/.distsshkitqueue/config.toml`.

Design: [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md).
"""
module DistSSHKitQueue

using Dates
using DistSSHKit
using TOML

export Queue
export Job
export submit!
export cancel!
export jobs
export job
export step!
export load!
export serve!
export serve
export job_project
export default_store_path
export main

include("DistSSHKitQueue/job.jl")
include("DistSSHKitQueue/store.jl")
include("DistSSHKitQueue/paths.jl")
include("DistSSHKitQueue/config.jl")
include("DistSSHKitQueue/queue.jl")
include("client/qhost.jl")
include("client/submit.jl")
include("client/status.jl")
include("client/cancel.jl")
include("qhost/service.jl")
include("qhost/setup.jl")
include("qhost/teardown.jl")
include("qhost/serve.jl")

function show_usage(; io::IO=stdout)
    println(io, "DistSSHKitQueue — FIFO waiter for DistSSHKit go / drive")
    println(io)
    println(io, "Client (dev laptop). Queue in --project=.; no files written here.")
    println(io, "  julia --project=. -m DistSSHKitQueue --qhost HOST status")
    println(io, "  julia --project=. -m DistSSHKitQueue --qhost HOST submit go [Kit go argv]")
    println(io, "  julia --project=. -m DistSSHKitQueue --qhost HOST submit drive [Kit drive argv]")
    println(io, "  julia --project=. -m DistSSHKitQueue --qhost HOST cancel <id>")
    println(io, "  julia --project=. -m DistSSHKitQueue --qhost HOST teardown -y")
    println(io)
    println(io, "Queue host (always-on). Default env has Queue. Store and waiter live here.")
    println(io, "  julia -m DistSSHKitQueue setup [--service]")
    println(io, "  julia -m DistSSHKitQueue serve")
    println(io, "  julia -m DistSSHKitQueue service install|uninstall")
    println(io, "  julia -m DistSSHKitQueue teardown -y")
    println(io)
    println(io, "Same machine as the queue host: omit `--qhost` on client verbs.")
    println(io, "`--qhost HOST` is client-only (several clusters: pass it every time).")
    println(io, "Do not pass `--qhost` to setup / serve / service.")
    println(io, "Remote Julia is Kit auto-detect; `--remote-julia` / JULIA_DISTRIBUTED_EXE override.")
    println(io, "`teardown -y` stops the waiter and removes dskq, the OS unit, and ~/.distsshkitqueue.")
    println(io, "Like Kit: `submit` starts a waiter if none is running (opt out:")
    println(io, "DISTSSHKITQUEUE_NO_AUTOSERVE=1). Bare `go` / `drive` alias `submit go` / `submit drive`.")
    println(io, "The job tree is cwd / DISTRIBUTED_PROJECT_ROOT, not the waiter --project.")
    println(io, "Ctrl-C leaves the waiter; running Kit is not killed.")
    println(io, "Config: $(default_config_path())   override: DISTSSHKITQUEUE_CONFIG")
    println(io, "Store: $(default_store_path())   override: DISTSSHKITQUEUE_STORE / config store=")
    return nothing
end

"""CLI entry. Prefer `julia -m DistSSHKitQueue` (client `--qhost HOST` / queue-host `setup`)."""
function main(args::Vector{String}=copy(ARGS))::Cint
    apply_config_env!(load_config())
    qhost, gjulia, after = extract_remote_opts(args)
    if isempty(after) || after[1] in ("-h", "--help", "help")
        show_usage()
        return 0
    end
    sub, rest = String(after[1]), String[String(a) for a in after[2:end]]
    reject_qhost_on_local(sub, qhost)
    if sub == "serve"
        return serve_cli(rest)
    elseif sub == "status"
        r = maybe_remote(qhost, gjulia, "status", rest)
        r === nothing || return r
        show_status(store_path())
        return 0
    elseif sub == "submit"
        r = maybe_remote(qhost, gjulia, "submit", rest)
        r === nothing || return r
        _, _, payload = extract_remote_opts(rest)
        return submit_main(payload)
    elseif sub == "go"
        r = maybe_remote(qhost, gjulia, "go", rest)
        r === nothing || return r
        return submit_go(rest)
    elseif sub == "drive"
        r = maybe_remote(qhost, gjulia, "drive", rest)
        r === nothing || return r
        return submit_drive(rest)
    elseif sub == "cancel"
        r = maybe_remote(qhost, gjulia, "cancel", rest)
        r === nothing || return r
        _, _, payload = extract_remote_opts(rest)
        return cancel_cli(payload)
    elseif sub == "teardown"
        r = maybe_remote(qhost, gjulia, "teardown", rest)
        r === nothing || return r
        _, _, payload = extract_remote_opts(rest)
        return teardown_main(payload)
    elseif sub == "service"
        return service_main(rest)
    elseif sub == "setup"
        return setup_main(rest)
    else
        println(stderr, "unknown subcommand: $sub")
        show_usage(io=stderr)
        return 1
    end
end

if VERSION >= v"1.12"
    Base.eval(@__MODULE__, :(@main))
end

end # module DistSSHKitQueue
