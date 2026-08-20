"""User config: `~/.distsshkitqueue/config.toml`. Override: `DISTSSHKITQUEUE_CONFIG`.

Resolution: CLI / ENV > config.toml > built-in defaults.
`[env]` keys are applied with `get!` so a real ENV value wins.
"""

function default_config_path(; home::AbstractString=homedir())::String
    return joinpath(home, ".distsshkitqueue", "config.toml")
end

queue_data_dir(; home::AbstractString=homedir())::String = joinpath(home, ".distsshkitqueue")

function config_path(; home::AbstractString=homedir())::String
    env = strip(get(ENV, "DISTSSHKITQUEUE_CONFIG", ""))
    return isempty(env) ? default_config_path(; home=home) : env
end

function load_config(; path::Union{Nothing,AbstractString}=nothing)::Dict{String,Any}
    p = path === nothing ? config_path() : String(path)
    isfile(p) || return Dict{String,Any}()
    raw = TOML.parsefile(p)
    return Dict{String,Any}(String(k) => v for (k, v) in raw)
end

"""Apply `cfg["env"]` into `ENV` without overwriting keys already set."""
function apply_config_env!(cfg::AbstractDict)
    env = get(cfg, "env", nothing)
    env isa AbstractDict || return nothing
    for (k, v) in env
        v === nothing && continue
        get!(ENV, String(k), v isa AbstractString ? String(v) : string(v))
    end
    return nothing
end

function config_store_path(cfg::AbstractDict)::Union{Nothing,String}
    st = get(cfg, "store", nothing)
    st isa AbstractString || return nothing
    s = strip(String(st))
    return isempty(s) ? nothing : String(expanduser(s))
end

function default_config_body(; store::AbstractString=default_store_path())::String
    return """
# DistSSHKitQueue. Override with DISTSSHKITQUEUE_CONFIG / DISTSSHKITQUEUE_STORE.
store = $(repr(String(store)))

[env]
# DISTRIBUTED_SSH_OPTS = "-F /path/to/ssh_config"
# DISTRIBUTED_REMOTE_PROJECT_ROOT = "/home/dev/job"
# DISTSSHKIT_YES = "1"
"""
end

function write_config_template(path::AbstractString; store::AbstractString=default_store_path())::Bool
    isfile(path) && return false
    mkpath(dirname(path))
    write(path, default_config_body(; store=store))
    return true
end

function store_path()::String
    env = strip(get(ENV, "DISTSSHKITQUEUE_STORE", ""))
    isempty(env) || return env
    st = config_store_path(load_config())
    st === nothing || return st
    return default_store_path()
end
