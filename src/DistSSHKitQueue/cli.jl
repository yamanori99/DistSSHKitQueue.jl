function show_usage(; io::IO=stdout)
    println(io, "DistSSHKitQueue — FIFO waiter for DistSSHKit go / drive")
    println(io)
    println(io, "  dskq setup [--service] [--bindir DIR]")
    println(io, "  dskq serve")
    println(io, "  dskq --on HOST status")
    println(io, "  dskq --on HOST submit go [DistSSHKit go argv]")
    println(io, "  dskq --on HOST submit drive [DistSSHKit drive argv]")
    println(io, "  dskq --on HOST cancel <id>")
    println(io, "  dskq service install")
    println(io, "  dskq service uninstall")
    println(io)
    println(io, "Same verbs as `julia --project=<queue-env> -m DistSSHKitQueue …`.")
    println(io, "`--on HOST` before the verb picks the controller (several clusters: pass it")
    println(io, "every time). `status` is an orderer command:")
    println(io, "  julia --project=. -m DistSSHKitQueue --on HOST status")
    println(io, "Remote Julia is Kit auto-detect; `--remote-julia` / JULIA_DISTRIBUTED_EXE override.")
    println(io, "`setup` writes ~/.local/bin/dskq and a config.toml if missing.")
    println(io, "Orderer: ssh controller ~/.local/bin/dskq submit go SCRIPT.jl local:1")
    println(io, "Like Kit: `submit` starts a waiter itself if none is running (opt out:")
    println(io, "DISTSSHKITQUEUE_NO_AUTOSERVE=1). `serve` / `service install` stay for a")
    println(io, "long-lived controller. `submit` / `cancel` write the table and exit.")
    println(io, "The job tree is cwd / DISTRIBUTED_PROJECT_ROOT, not the waiter --project.")
    println(io, "Bare `go` / `drive` alias `submit go` / `submit drive`.")
    println(io, "Ctrl-C leaves the waiter; running Kit is not killed.")
    println(io, "Config: $(default_config_path())   override: DISTSSHKITQUEUE_CONFIG")
    println(io, "Store: $(default_store_path())   override: DISTSSHKITQUEUE_STORE / config store=")
    return nothing
end

function store_path()::String
    env = strip(get(ENV, "DISTSSHKITQUEUE_STORE", ""))
    isempty(env) || return env
    st = config_store_path(load_config())
    st === nothing || return st
    return default_store_path()
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

"""Like Kit `go!`/`drive!`: no separate "start the server" step. If no `serve` is
watching `store`, spawn one detached (log next to the store). Opt out with
`DISTSSHKITQUEUE_NO_AUTOSERVE=1` (tests, or a harness that manages `serve` itself).
"""
function ensure_waiter!(store::AbstractString)::Bool
    get(ENV, "DISTSSHKITQUEUE_NO_AUTOSERVE", "") == "1" && return false
    waiter_alive(store) && return false
    julia = default_julia_bin()
    project = default_queue_env()
    log = string(store, ".log")
    mkpath(dirname(log))
    io = open(log, "a")
    cmd = `$julia --startup-file=no --project=$project -m DistSSHKitQueue serve`
    run(pipeline(detach(cmd); stdout=io, stderr=io); wait=false)
    println(stderr, "submit: no waiter running; started one (log: $log)")
    return true
end

function default_remote_julia()::String
    envj = strip(get(ENV, "JULIA_DISTRIBUTED_EXE", ""))
    return isempty(envj) ? "auto" : envj
end

"""Peel leading `--on HOST` / `--remote-julia PATH`. `rjulia` is `nothing` if omitted."""
function extract_remote_opts(args::Vector{String})
    host = nothing
    rjulia = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--on" && i < length(args)
            host = args[i+1]
            i += 2
        elseif a == "--remote-julia" && i < length(args)
            rjulia = args[i+1]
            i += 2
        else
            break
        end
    end
    return host, rjulia, args[i:end]
end

function coalesce_remote(
    ahost::Union{Nothing,AbstractString},
    ajulia::Union{Nothing,AbstractString},
    bhost::Union{Nothing,AbstractString},
    bjulia::Union{Nothing,AbstractString},
)
    if ahost !== nothing && bhost !== nothing && String(ahost) != String(bhost)
        throw(ArgumentError("`--on` given twice ($(ahost) and $(bhost))"))
    end
    host = ahost !== nothing ? String(ahost) : (bhost === nothing ? nothing : String(bhost))
    spec = ajulia !== nothing ? String(ajulia) :
           (bjulia !== nothing ? String(bjulia) : default_remote_julia())
    return host, spec
end

"""`julia -m DistSSHKitQueue <sub> <payload…>`, each token shell-quoted for ssh."""
function remote_inner(rjulia::AbstractString, sub::AbstractString, payload::Vector{String})::String
    parts = String[String(rjulia), "-m", "DistSSHKitQueue", String(sub)]
    append!(parts, payload)
    return join((sh_single_quote(p) for p in parts), " ")
end

function remote_command(host::AbstractString, rjulia::AbstractString, sub::AbstractString, payload::Vector{String})::Cmd
    inner = remote_inner(rjulia, sub, payload)
    return Cmd(vcat(["ssh"], collect(DistSSHKit.ssh_opts()), [String(host), inner]))
end

function resolve_on_julia(host::AbstractString, spec::AbstractString)::String
    found = DistSSHKit.resolve_remote_julia(String(host), spec)
    found === nothing && throw(ArgumentError(
        "no Julia on $(host) (ssh PATH is often empty; Kit tries juliaup then Homebrew). " *
        "Pass --remote-julia PATH or set JULIA_DISTRIBUTED_EXE, like Kit --julia.",
    ))
    return found
end

function remote_dispatch(host::AbstractString, rjulia::AbstractString, sub::AbstractString, payload::Vector{String})::Cint
    jl = resolve_on_julia(host, rjulia)
    proc = run(ignorestatus(remote_command(host, jl, sub, payload)))
    return Cint(proc.exitcode)
end

function submit_cli(store::AbstractString, kind::Symbol, script::AbstractString, hosts, kw::Dict{String,Any})
    q = Queue(; store=store)
    nt = isempty(kw) ? NamedTuple() : (; (Symbol(k) => v for (k, v) in kw)...)
    id = submit!(q, String(script), String[String(x) for x in hosts]; kind=kind, nt...)
    ensure_waiter!(store)
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

"""CLI entry. Prefer `dskq serve` / `submit` / `cancel` (or `julia -m DistSSHKitQueue`)."""
function main(args::Vector{String}=copy(ARGS))::Cint
    apply_config_env!(load_config())
    ghost, gjulia, after = extract_remote_opts(args)
    if isempty(after) || after[1] in ("-h", "--help", "help")
        show_usage()
        return 0
    end
    sub, rest = String(after[1]), String[String(a) for a in after[2:end]]
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
        host, rjulia, payload = extract_remote_opts(rest)
        dest, spec = coalesce_remote(ghost, gjulia, host, rjulia)
        dest === nothing || return remote_dispatch(dest, spec, "status", payload)
        show_status(store_path())
        return 0
    elseif sub == "submit"
        host, rjulia, payload = extract_remote_opts(rest)
        dest, spec = coalesce_remote(ghost, gjulia, host, rjulia)
        dest === nothing || return remote_dispatch(dest, spec, "submit", payload)
        return submit_main(payload)
    elseif sub == "go"
        return submit_go(rest)
    elseif sub == "drive"
        return submit_drive(rest)
    elseif sub == "cancel"
        host, rjulia, payload = extract_remote_opts(rest)
        dest, spec = coalesce_remote(ghost, gjulia, host, rjulia)
        dest === nothing || return remote_dispatch(dest, spec, "cancel", payload)
        return cancel_cli(payload)
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
