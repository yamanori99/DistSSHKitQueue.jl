"""Client `submit go` / `submit drive` (Kit parsers). Runs on the queue host after ssh."""

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
        push!(out, "parenthost:$(parsed.local_workers)")
    end
    for (host, n) in parsed.hosts
        DistSSHKit.is_local_host_name(host) && continue
        push!(out, n === nothing ? String(host) : string(host, ":", n))
    end
    isempty(out) && push!(out, "parenthost")
    return out
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
function script_arg(path::AbstractString, ::AbstractString)::String
    resolved = resolve_script(path)
    isfile(resolved) && return resolved
    throw(ArgumentError(
        DistSSHKit.explain_script_not_found(resolved, job_project(); surface=:cli),
    ))
end

function submit_go(args::Vector{String})::Cint
    parsed = DistSSHKit.parse_go_args(args)
    parsed.help && (DistSSHKit.show_go_usage(); return 0)
    parsed.show_version && (DistSSHKit.println_kit_version(); return 0)
    hosts = String[String(h) for h in parsed.hosts]
    isempty(hosts) && (hosts = String["parenthost"])
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
