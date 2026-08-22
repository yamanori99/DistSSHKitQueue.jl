"""Like Kit `go!`/`drive!`: no separate "start the server" step. If no `serve` is
watching `store`, spawn one detached (log next to the store). Opt out with
`DISTSSHKITQUEUE_NO_AUTOSERVE=1` (tests, or a harness that manages `serve` itself).
A prior `stop` also holds it off until an explicit `serve` clears the latch.
"""
function ensure_waiter!(store::AbstractString)::Bool
    get(ENV, "DISTSSHKITQUEUE_NO_AUTOSERVE", "") == "1" && return false
    waiter_stopped(store) && return false
    waiter_alive(store) && return false
    julia = default_julia_bin()
    project = default_queue_env()
    log = string(store, ".log")
    mkpath(dirname(log))
    spawn_detached_serve!(julia, project, log)
    print_waiter_started(log)
    return true
end

"""Start `serve` so this Julia process can still exit.

`run(...; wait=false)` keeps a libuv handle. `submit` then never exits, so
client `--qhost` ssh hangs after `Started waiter`. A short-lived `sh -c ... &`
lets the waiter outlive `submit` without that handle. Windows has no waiter
unit; keep the Julia spawn there.
"""
function spawn_detached_serve!(julia::AbstractString, project::AbstractString, log::AbstractString)
    if Sys.iswindows()
        io = open(log, "a")
        cmd = `$julia --startup-file=no --project=$project -m DistSSHKitQueue serve`
        run(pipeline(detach(cmd); stdin=devnull, stdout=io, stderr=io); wait=false)
        close(io)
        return nothing
    end
    jl = sh_single_quote(julia)
    proj = sh_single_quote(project)
    lg = sh_single_quote(log)
    script = "nohup $jl --startup-file=no --project=$proj -m DistSSHKitQueue serve </dev/null >>$lg 2>&1 &"
    run(`/bin/sh -c $script`)
    return nothing
end

function serve_cli(args::Vector{String})::Cint
    interval = 0.2
    i = 1
    while i <= length(args)
        if args[i] == "--interval" && i < length(args)
            interval = parse(Float64, args[i+1])
            i += 2
        elseif args[i] in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown serve option: $(args[i])"))
        end
    end
    serve(; store=store_path(), interval=interval)
    return 0
end

"""Stop the waiter and latch it off. Keeps config / store / OS unit.
`submit` will not auto-serve until an explicit `serve` clears the latch."""
function stop_cli(args::Vector{String})::Cint
    for a in args
        a in ("-h", "--help") && (show_usage(); return 0)
        throw(ArgumentError("unknown stop option: $(a)"))
    end
    store = store_path()
    was_running = stop_waiter!(store)
    set_stopped!(store)
    print_waiter_stopped(store, was_running)
    return 0
end
