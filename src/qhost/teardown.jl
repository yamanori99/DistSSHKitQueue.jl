"""Remove queue-host state: waiter, OS unit, `dskq`, store, `~/.distsshkitqueue`.

Does not `Pkg.rm` or delete a git clone. Kit job trees (`.distsshkit/`) stay.
Needs `-y` / `--yes` (or `DISTSSHKITQUEUE_YES=1`).
"""

function teardown_yes()::Bool
    return get(ENV, "DISTSSHKITQUEUE_YES", "") == "1"
end

function teardown_store(; home::AbstractString=homedir(), config::AbstractString=config_path(; home=home))::String
    env = strip(get(ENV, "DISTSSHKITQUEUE_STORE", ""))
    isempty(env) || return env
    st = config_store_path(load_config(; path=config))
    st === nothing || return st
    return default_store_path(; home=home)
end

function teardown_targets(;
    home::AbstractString=homedir(),
    bindir::AbstractString=default_bindir(; home=home),
    config::AbstractString=config_path(; home=home),
)::Vector{String}
    st = teardown_store(; home=home, config=config)
    data = queue_data_dir(; home=home)
    wrap = wrapper_path(; bindir=bindir)
    out = String[wrap, st, store_pid_path(st), store_stop_path(st), string(st, ".log"), config, data]
    if Sys.isapple()
        push!(out, launch_agent_path(; home=home))
    elseif Sys.islinux()
        push!(out, systemd_user_path(; home=home))
    end
    seen = Set{String}()
    uniq = String[]
    for p in out
        DistSSHKit.canonical_local_path(p) in seen && continue
        push!(seen, DistSSHKit.canonical_local_path(p))
        push!(uniq, p)
    end
    return uniq
end

function teardown(;
    home::AbstractString=homedir(),
    bindir::AbstractString=default_bindir(; home=home),
    config::AbstractString=config_path(; home=home),
    yes::Bool=false,
    apply::Bool=true,
    io::IO=stdout,
)::Cint
    targets = teardown_targets(; home=home, bindir=bindir, config=config)
    existing = String[p for p in targets if ispath(p)]
    if !yes
        DistSSHKit.print_cli_error("teardown needs -y / --yes")
        DistSSHKit.print_help_section("Would remove"; io=stderr)
        for p in existing
            DistSSHKit.print_help_lines(stderr, "  $(_q_short(p))")
        end
        return 1
    end
    st = teardown_store(; home=home, config=config)
    apply && stop_waiter!(st)
    try
        service_uninstall(; apply=apply, home=home)
    catch
    end
    wrap = wrapper_path(; bindir=bindir)
    ispath(wrap) && rm(wrap; force=true)
    for extra in (st, store_pid_path(st), store_stop_path(st), string(st, ".log"), string(st, ".lock"))
        ispath(extra) && rm(extra; force=true, recursive=true)
    end
    ispath(config) && rm(config; force=true)
    data = queue_data_dir(; home=home)
    isdir(data) && rm(data; force=true, recursive=true)
    for p in existing
        print_removed(p; io=io)
    end
    return 0
end

function teardown_main(args::Vector{String})::Cint
    home = homedir()
    bindir = nothing
    config = nothing
    yes = teardown_yes()
    apply = true
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            show_usage()
            return 0
        elseif a in ("-y", "--yes")
            yes = true
            i += 1
        elseif a == "--write-only"
            apply = false
            i += 1
        elseif a == "--home" && i < length(args)
            home = args[i+1]
            i += 2
        elseif a == "--bindir" && i < length(args)
            bindir = args[i+1]
            i += 2
        elseif a == "--config" && i < length(args)
            config = args[i+1]
            i += 2
        else
            throw(ArgumentError("unknown teardown option: $(a)"))
        end
    end
    bd = bindir === nothing ? default_bindir(; home=home) : String(bindir)
    cfg = config === nothing ? config_path(; home=home) : String(config)
    return teardown(; home=home, bindir=bd, config=cfg, yes=yes, apply=apply)
end
