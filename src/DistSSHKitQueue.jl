"""
DistSSHKitQueue — FIFO waiter for DistSSHKit (`go` / `drive`).

Package entry: exports, `include`s, `main` (`@main` on Julia 1.12+).
FIFO: `src/DistSSHKitQueue/`. Client CLI: `src/client/`. Queue host CLI: `src/qhost/`.
Waiter runs DistSSHKit `execute!(...; detached=true)`.
`--project=<queue-env>` loads this package; the job tree is `job_project()`.
Config: `~/.distsshkitqueue/config.toml`.

Concept and design notes: [README](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/README.md#concept).
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

include("DistSSHKitQueue/job.jl")
include("DistSSHKitQueue/store.jl")
include("DistSSHKitQueue/paths.jl")
include("DistSSHKitQueue/config.jl")
include("DistSSHKitQueue/display.jl")
include("DistSSHKitQueue/queue.jl")
include("client/qhost.jl")
include("client/submit.jl")
include("client/status.jl")
include("client/cancel.jl")
include("qhost/service.jl")
include("qhost/setup.jl")
include("qhost/teardown.jl")
include("qhost/serve.jl")

show_usage(; io::IO=stdout) = print_queue_usage(io)

"""CLI entry. Prefer `julia -m DistSSHKitQueue` (client `--qhost HOST` / queue-host `setup`)."""
function main(args::Vector{String}=copy(ARGS))::Cint
    apply_config_env!(load_config())
    qhost, gjulia, after = extract_remote_opts(args)
    if isempty(after) || after[1] in ("-h", "--help", "help")
        show_usage()
        return 0
    end
    sub, rest = String(after[1]), String[String(a) for a in after[2:end]]
    try
        reject_qhost_on_local(sub, qhost)
        if sub == "serve"
            return serve_cli(rest)
        elseif sub == "stop"
            r = maybe_remote(qhost, gjulia, "stop", rest)
            r === nothing || return r
            _, _, payload = extract_remote_opts(rest)
            return stop_cli(payload)
        elseif sub == "status"
            r = maybe_remote(qhost, gjulia, "status", rest)
            r === nothing || return r
            show_status(store_path())
            return 0
        elseif sub == "watch"
            r = maybe_remote(qhost, gjulia, "watch", rest; tty=stdout isa Base.TTY)
            r === nothing || return r
            _, _, payload = extract_remote_opts(rest)
            return watch_cli(payload)
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
            DistSSHKit.print_cli_error("unknown subcommand: $sub")
            show_usage(io=stderr)
            return 1
        end
    catch e
        e isa ArgumentError || rethrow()
        DistSSHKit.print_cli_error(e.msg)
        return 1
    end
end

if VERSION >= v"1.12"
    Base.eval(@__MODULE__, :(@main))
end

end # module DistSSHKitQueue
