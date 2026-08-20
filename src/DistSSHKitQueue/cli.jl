function show_usage(; io::IO=stdout)
    println(io, "DistSSHKitQueue — FIFO waiter for DistSSHKit go / drive")
    println(io)
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue serve")
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue status")
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue submit go [DistSSHKit go argv]")
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue submit drive [DistSSHKit drive argv]")
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue cancel <id>")
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue service install")
    println(io, "  julia --project=<queue-env> -m DistSSHKitQueue service uninstall")
    println(io)
    println(io, "`serve` waits. `submit` / `cancel` write the table and exit (do not run Kit).")
    println(io, "`--project=<queue-env>` loads Queue. The job tree is cwd / DISTRIBUTED_PROJECT_ROOT.")
    println(io, "Bare `go` / `drive` alias `submit go` / `submit drive`.")
    println(io, "Ctrl-C leaves the waiter; running Kit is not killed.")
    println(io, "Store: $(default_store_path())   override: DISTSSHKITQUEUE_STORE")
    return nothing
end

function store_path()::String
    env = strip(get(ENV, "DISTSSHKITQUEUE_STORE", ""))
    return isempty(env) ? default_store_path() : env
end

function show_status(store::AbstractString; io::IO=stdout)
    rows = isfile(store) ? read_jobs(store) : Job[]
    println(io, "store: $store")
    isempty(rows) && (println(io, "(empty)"); return nothing)
    for j in rows
        parts = String[j.id, String(j.state), String(j.kind), j.script, join(j.hosts, ',')]
        proj = get(j.kwargs, "project", nothing)
        proj === nothing || push!(parts, String(proj))
        j.result_path === nothing || push!(parts, j.result_path)
        println(io, join(parts, "  "))
    end
    return nothing
end

function drop_nothing(d::Dict{String,Any})
    out = Dict{String,Any}()
    for (k, v) in d
        v === nothing && continue
        if v isa Symbol
            out[k] = String(v)
        elseif v isa AbstractVector && isempty(v)
            continue
        else
            out[k] = v
        end
    end
    return out
end

function drive_hosts(parsed)::Vector{String}
    out = String[]
    if parsed.local_workers > 0
        push!(out, "local:$(parsed.local_workers)")
    end
    for (host, n) in parsed.hosts
        DistSSHKit.is_local_host_name(host) && continue
        push!(out, n === nothing ? String(host) : string(host, ":", n))
    end
    isempty(out) && push!(out, "local")
    return out
end

function submit_cli(store::AbstractString, kind::Symbol, script::AbstractString, hosts, kw::Dict{String,Any})
    q = Queue(; store=store)
    nt = isempty(kw) ? NamedTuple() : (; (Symbol(k) => v for (k, v) in kw)...)
    id = submit!(q, String(script), String[String(x) for x in hosts]; kind=kind, nt...)
    println(id)
    return 0
end

script_arg(::Nothing, verb::AbstractString) = throw(ArgumentError("$verb: missing SCRIPT.jl"))
script_arg(path::AbstractString, ::AbstractString) = resolve_script(path)

function submit_go(args::Vector{String})::Cint
    parsed = DistSSHKit.parse_go_args(args)
    parsed.help && (DistSSHKit.show_go_usage(); return 0)
    parsed.show_version && (DistSSHKit.println_kit_version(); return 0)
    hosts = String[String(h) for h in parsed.hosts]
    isempty(hosts) && (hosts = String["local"])
    kw = drop_nothing(Dict{String,Any}(
        "args" => parsed.script_args,
        "output_dir" => parsed.output_dir,
        "julia" => parsed.julia,
        "sync" => parsed.sync,
        "quiet" => parsed.cli_session.quiet,
        "yes" => true,
    ))
    return submit_cli(store_path(), :go, script_arg(parsed.script_path, "go"), hosts, kw)
end

function submit_drive(args::Vector{String})::Cint
    parsed = DistSSHKit.parse_drive_args(args)
    parsed.help && (DistSSHKit.show_drive_requirements(); return 0)
    parsed.show_version && (DistSSHKit.println_kit_version(); return 0)
    kw = drop_nothing(Dict{String,Any}(
        "args" => parsed.script_args,
        "output_dir" => parsed.output_dir,
        "log_dir" => parsed.log_dir,
        "julia" => parsed.julia,
        "sync" => parsed.sync_mode,
        "skip_hash_check" => parsed.skip_hash_check,
        "require_all_hosts" => parsed.require_all_hosts,
        "quiet" => parsed.cli_session.quiet,
        "yes" => true,
    ))
    return submit_cli(
        store_path(),
        :drive,
        script_arg(parsed.script_path, "drive"),
        drive_hosts(parsed),
        kw,
    )
end

function submit_main(args::Vector{String})::Cint
    isempty(args) && throw(ArgumentError("submit: need `go` or `drive`"))
    kit, rest = String(args[1]), String[String(a) for a in args[2:end]]
    kit in ("-h", "--help") && (show_usage(); return 0)
    kit == "go" && return submit_go(rest)
    kit == "drive" && return submit_drive(rest)
    throw(ArgumentError("submit: unknown kit command $(repr(kit)) (want go or drive)"))
end

function cancel_cli(args::Vector{String})::Cint
    isempty(args) && throw(ArgumentError("cancel: need a job id"))
    args[1] in ("-h", "--help") && (show_usage(); return 0)
    length(args) == 1 || throw(ArgumentError("cancel: extra arguments"))
    id = String(args[1])
    q = Queue(; store=store_path())
    if cancel!(q, id)
        println(id)
        return 0
    end
    println(stderr, "cancel: job $(repr(id)) is not queued")
    return 1
end

"""CLI entry. Prefer `julia -m DistSSHKitQueue serve` / `submit` / `cancel`."""
function main(args::Vector{String}=copy(ARGS))::Cint
    if isempty(args) || args[1] in ("-h", "--help", "help")
        show_usage()
        return 0
    end
    sub, rest = String(args[1]), String[String(a) for a in args[2:end]]
    if sub == "serve"
        interval = 0.2
        i = 1
        while i <= length(rest)
            if rest[i] == "--interval" && i < length(rest)
                interval = parse(Float64, rest[i+1])
                i += 2
            elseif rest[i] in ("-h", "--help")
                show_usage()
                return 0
            else
                throw(ArgumentError("unknown serve option: $(rest[i])"))
            end
        end
        serve(; store=store_path(), interval=interval)
        return 0
    elseif sub == "status"
        show_status(store_path())
        return 0
    elseif sub == "submit"
        return submit_main(rest)
    elseif sub == "go"
        return submit_go(rest)
    elseif sub == "drive"
        return submit_drive(rest)
    elseif sub == "cancel"
        return cancel_cli(rest)
    elseif sub == "service"
        return service_main(rest)
    else
        println(stderr, "unknown subcommand: $sub")
        show_usage(io=stderr)
        return 1
    end
end
