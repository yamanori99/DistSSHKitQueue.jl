"""Write `config.toml` if missing. Optional OS unit via `--service`."""

function default_bindir(; home::AbstractString=homedir())::String
    return joinpath(home, ".local", "bin")
end

"""Path of a leftover `dskq` shim (no longer installed). `teardown` still removes it."""
function wrapper_path(; bindir::AbstractString=default_bindir())::String
    return joinpath(bindir, "dskq")
end

function setup(;
    julia::AbstractString=default_julia_bin(),
    project::AbstractString=default_queue_env(),
    config::AbstractString=config_path(),
    service::Bool=false,
    force::Bool=false,
    apply::Bool=true,
)
    if force && isfile(config)
        rm(config; force=true)
    end
    wrote = write_config_template(config)
    wrote ? print_wrote(config) : print_present(config)
    if service
        return service_install(; julia=julia, project=project, apply=apply)
    end
    return 0
end

function setup_main(args::Vector{String})::Cint
    julia = default_julia_bin()
    project = default_queue_env()
    config = config_path()
    service = false
    force = false
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
        elseif a == "--config" && i < length(args)
            config = args[i+1]
            i += 2
        elseif a == "--service"
            service = true
            i += 1
        elseif a == "--force"
            force = true
            i += 1
        elseif a == "--write-only"
            apply = false
            i += 1
        else
            throw(ArgumentError("unknown setup option: $(a)"))
        end
    end
    return setup(; julia=julia, project=project, config=config, service=service, force=force, apply=apply)
end
