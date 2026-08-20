"""Write the `dskq` shim and (if missing) `config.toml`. Optional OS unit via `--service`."""

function default_bindir(; home::AbstractString=homedir())::String
    return joinpath(home, ".local", "bin")
end

function wrapper_path(; bindir::AbstractString=default_bindir())::String
    return joinpath(bindir, "dskq")
end

function sh_single_quote(s::AbstractString)::String
    return string('\'', replace(String(s), "'" => "'\\''"), '\'')
end

function wrapper_body(julia::AbstractString, project::AbstractString)::String
    j = sh_single_quote(julia)
    p = sh_single_quote(project)
    return """
#!/bin/sh
exec $j --startup-file=no --project=$p -m DistSSHKitQueue \"\$@\"
"""
end

function install_wrapper(;
    julia::AbstractString=default_julia_bin(),
    project::AbstractString=default_queue_env(),
    bindir::AbstractString=default_bindir(),
)::String
    jl = DistSSHKit.canonical_local_path(julia)
    proj = DistSSHKit.canonical_local_path(project)
    isfile(jl) || throw(ArgumentError("setup: julia not found at $(repr(jl))"))
    isfile(joinpath(proj, "Project.toml")) || throw(ArgumentError("setup: no Project.toml in $(repr(proj))"))
    path = wrapper_path(; bindir=bindir)
    mkpath(dirname(path))
    write(path, wrapper_body(jl, proj))
    chmod(path, 0o755)
    return path
end

function path_has_dir(bindir::AbstractString)::Bool
    want = DistSSHKit.canonical_local_path(bindir)
    for part in split(get(ENV, "PATH", ""), ':')
        isempty(part) && continue
        DistSSHKit.canonical_local_path(part) == want && return true
    end
    return false
end

function setup(;
    julia::AbstractString=default_julia_bin(),
    project::AbstractString=default_queue_env(),
    bindir::AbstractString=default_bindir(),
    config::AbstractString=config_path(),
    service::Bool=false,
    apply::Bool=true,
)
    wrap = install_wrapper(; julia=julia, project=project, bindir=bindir)
    wrote = write_config_template(config)
    println(wrap)
    wrote && println(config)
    path_has_dir(bindir) || println(stderr, "setup: $(bindir) is not on PATH; use the absolute path or add it")
    if service
        return service_install(; julia=julia, project=project, apply=apply)
    end
    return 0
end

function setup_main(args::Vector{String})::Cint
    julia = default_julia_bin()
    project = default_queue_env()
    bindir = default_bindir()
    config = config_path()
    service = false
    apply = true
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            show_usage()
            return 0
        elseif a == "--julia" && i < length(args)
            julia = args[i+1]
            i += 2
        elseif a == "--project" && i < length(args)
            project = args[i+1]
            i += 2
        elseif a == "--bindir" && i < length(args)
            bindir = args[i+1]
            i += 2
        elseif a == "--config" && i < length(args)
            config = args[i+1]
            i += 2
        elseif a == "--service"
            service = true
            i += 1
        elseif a == "--write-only"
            apply = false
            i += 1
        else
            throw(ArgumentError("unknown setup option: $(a)"))
        end
    end
    return setup(; julia=julia, project=project, bindir=bindir, config=config, service=service, apply=apply)
end
