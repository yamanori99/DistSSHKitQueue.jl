function print_queue_usage(; io::IO=stdout)
    println(io, "DistSSHKitQueue — FIFO waiter for DistSSHKit go / drive")
    println(io)
    println(io, "  julia --project=. -m DistSSHKitQueue serve")
    println(io, "  julia --project=. -m DistSSHKitQueue status")
    println(io, "  julia --project=. -m DistSSHKitQueue go [same argv as DistSSHKit go]")
    println(io, "  julia --project=. -m DistSSHKitQueue drive [same argv as DistSSHKit drive]")
    println(io)
    println(io, "No subcommand prints this help. `serve` is the waiter. Ctrl-C leaves it; running Kit is not killed.")
    println(io, "Store: $(default_store_path())   override: DISTSSHKITQUEUE_STORE")
    return nothing
end

function cli_store_path()::String
    env = strip(get(ENV, "DISTSSHKITQUEUE_STORE", ""))
    return isempty(env) ? default_store_path() : env
end

function print_status(store::AbstractString; io::IO=stdout)
    jobs = isfile(store) ? load_jobs_raw(store) : PlaceholderJob[]
    println(io, "store: $store")
    isempty(jobs) && (println(io, "(empty)"); return nothing)
    for j in jobs
        extra = j.result_path === nothing ? "" : "  $(j.result_path)"
        println(io, "$(j.id)  $(j.state)  $(j.kind)  $(j.script)  $(join(j.hosts, ','))$extra")
    end
    return nothing
end

function toml_kw(d::Dict{String,Any})
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

function drive_job_hosts(parsed)::Vector{String}
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

function enqueue_cli!(store::AbstractString, kind::Symbol, script::AbstractString, hosts, kw::Dict{String,Any})
    h = Placeholder(; store=store)
    nt = isempty(kw) ? NamedTuple() : (; (Symbol(k) => v for (k, v) in kw)...)
    id = placeholder!(h, String(script), String[String(x) for x in hosts]; drive=(kind === :drive), nt...)
    println(id)
    return 0
end

cli_script_path(::Nothing, verb::AbstractString) = throw(ArgumentError("$verb: missing SCRIPT.jl"))
cli_script_path(path::AbstractString, ::AbstractString) = String(path)

function cli_go(args::Vector{String})::Cint
    parsed = DistSSHKit.parse_go_args(args)
    parsed.help && (DistSSHKit.show_go_usage(); return 0)
    parsed.show_version && (DistSSHKit.println_kit_version(); return 0)
    script = cli_script_path(parsed.script_path, "go")
    hosts = String[String(h) for h in parsed.hosts]
    isempty(hosts) && (hosts = String["local"])
    kw = toml_kw(Dict{String,Any}(
        "args" => parsed.script_args,
        "output_dir" => parsed.output_dir,
        "julia" => parsed.julia,
        "sync" => parsed.sync,
        "quiet" => parsed.cli_session.quiet,
        "yes" => true,
    ))
    return enqueue_cli!(cli_store_path(), :go, script, hosts, kw)
end

function cli_drive(args::Vector{String})::Cint
    parsed = DistSSHKit.parse_drive_args(args)
    parsed.help && (DistSSHKit.show_drive_requirements(); return 0)
    parsed.show_version && (DistSSHKit.println_kit_version(); return 0)
    script = cli_script_path(parsed.script_path, "drive")
    kw = toml_kw(Dict{String,Any}(
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
    return enqueue_cli!(cli_store_path(), :drive, script, drive_job_hosts(parsed), kw)
end

"""CLI entry. Prefer `julia -m DistSSHKitQueue serve`."""
function main(args::Vector{String}=copy(ARGS))::Cint
    if isempty(args) || args[1] in ("-h", "--help", "help")
        print_queue_usage()
        return 0
    end
    sub, rest = String(args[1]), String[String(a) for a in args[2:end]]
    if sub == "serve"
        poll = 0.2
        i = 1
        while i <= length(rest)
            if rest[i] == "--poll" && i < length(rest)
                poll = parse(Float64, rest[i+1])
                i += 2
            elseif rest[i] in ("-h", "--help")
                print_queue_usage()
                return 0
            else
                throw(ArgumentError("unknown serve option: $(rest[i])"))
            end
        end
        serve(; store=cli_store_path(), poll=poll)
        return 0
    elseif sub == "status"
        print_status(cli_store_path())
        return 0
    elseif sub == "go"
        return cli_go(rest)
    elseif sub == "drive"
        return cli_drive(rest)
    else
        println(stderr, "unknown subcommand: $sub")
        print_queue_usage(io=stderr)
        return 1
    end
end
