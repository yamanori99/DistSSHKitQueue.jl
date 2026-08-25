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

"""Kit SSH name: `parent[:N]` / `child:NAME[:N]` → `name`, else the stripped string (`host1`)."""
function kit_ssh_name(raw::AbstractString)::String
    s = strip(String(raw))
    isempty(s) && return ""
    try
        return String(DistSSHKit.parse_placement_token(s).name)
    catch e
        e isa ArgumentError || rethrow()
        return s
    end
end

"""Kit SSH names (`parent`, `child` NAME). Missing key: allow all. Empty array: allow none.

Entries may be inventory names or placement tokens (`child:host1` → `host1`).
"""
function config_allowed_names(cfg::AbstractDict)::Union{Nothing,Set{String}}
    raw = get(cfg, "allowed", nothing)
    raw === nothing && return nothing
    raw isa AbstractVector || throw(ArgumentError("`allowed` must be an array of Kit SSH names"))
    return Set{String}(filter(!isempty, String[kit_ssh_name(String(x)) for x in raw]))
end

function sorted_kit_ssh_names(names::Set{String})::Vector{String}
    v = collect(names)
    sort!(v; by=n -> (DistSSHKit.is_parent_host_name(n) ? 0 : 1, n))
    return v
end

function toml_string_array(xs::AbstractVector{<:AbstractString})::String
    return "[" * join((repr(String(x)) for x in xs), ", ") * "]"
end

function allowed_toml_line(names::Set{String})::String
    return "allowed = " * toml_string_array(sorted_kit_ssh_names(names))
end

function _is_allowed_toml_line(row::String)::Bool
    t = lstrip(row)
    if !isempty(t) && t[1] == '#'
        t = lstrip(SubString(t, nextind(t, firstindex(t))))
    end
    startswith(t, "allowed") || return false
    rest = lstrip(chopprefix(t, "allowed"))
    return startswith(rest, "=")
end

function replace_or_insert_allowed_line(text::String, line::String)::String
    s = String(text)
    ln = String(line)
    rows = String[String(r) for r in split(s, '\n'; keepempty=true)]
    idx = findfirst(_is_allowed_toml_line, rows)
    if idx isa Int
        rows[idx] = ln
        return join(rows, '\n')
    end
    env = findfirst(r -> startswith(lstrip(r), "[env]"), rows)
    if env isa Int
        insert!(rows, env, ln)
        return join(rows, '\n')
    end
    return rstrip(s) * "\n" * ln * "\n"
end

function write_allowed_names!(path::AbstractString, names::Set{String})
    p = String(path)
    isfile(p) || write_config_template(p)
    write(p, replace_or_insert_allowed_line(read(p, String), allowed_toml_line(names)))
    return names
end

function parse_kit_ssh_names(raws)::Vector{String}
    out = String[]
    for r in raws
        n = kit_ssh_name(String(r))
        isempty(n) && throw(ArgumentError("Kit SSH name is empty"))
        push!(out, n)
    end
    return out
end

"""First `add-host` creates `allowed` (submit is no longer allow-all)."""
function add_allowed_names!(path::AbstractString, raws)
    extra = Set{String}(parse_kit_ssh_names(raws))
    isempty(extra) && throw(ArgumentError("add-host needs a Kit SSH name"))
    cur = isfile(path) ? config_allowed_names(load_config(; path=path)) : nothing
    names = cur === nothing ? extra : union(cur, extra)
    return write_allowed_names!(path, names)
end

function remove_allowed_names!(path::AbstractString, raws)
    extra = Set{String}(parse_kit_ssh_names(raws))
    isempty(extra) && throw(ArgumentError("remove-host needs a Kit SSH name"))
    isfile(path) || throw(ArgumentError("no config.toml; add-host first"))
    cur = config_allowed_names(load_config(; path=path))
    cur === nothing && throw(ArgumentError("no allowed= in config; submit accepts any Kit name"))
    for n in extra
        n in cur || throw(ArgumentError("Kit name $(repr(n)) is not on allowed"))
    end
    return write_allowed_names!(path, setdiff(cur, extra))
end

function default_config_body(; store::AbstractString=default_store_path())::String
    return """
# DistSSHKitQueue. Override with DISTSSHKITQUEUE_CONFIG / DISTSSHKITQUEUE_STORE.
store = $(repr(String(store)))
# allowed = ["parent", "host1"]   # or child:host1

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
