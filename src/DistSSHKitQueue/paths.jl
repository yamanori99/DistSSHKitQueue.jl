"""Local paths shared by the waiter, `setup`, and `service`.

Not CLI parsing. `queue_data_dir` lives in `config.jl`.
"""

function sh_single_quote(s::AbstractString)::String
    return string('\'', replace(String(s), "'" => "'\\''"), '\'')
end

function default_julia_bin()::String
    exe = Base.julia_cmd().exec[1]
    isfile(exe) && return DistSSHKit.canonical_local_path(exe)
    w = Sys.which("julia")
    w !== nothing && isfile(w) && return DistSSHKit.canonical_local_path(w)
    return joinpath(Sys.BINDIR, Sys.iswindows() ? "julia.exe" : "julia")
end

"""`~/.distsshkitqueue/env`, a Queue environment independent of any dev checkout.

Not created automatically (that would mean running `Pkg` network operations as a
side effect of `setup`); see README for the one-time `Pkg.develop` / `Pkg.add`.
"""
function default_queue_env_dir(; home::AbstractString=homedir())::String
    return joinpath(home, ".distsshkitqueue", "env")
end

"""The `--project` `setup`/`service` bake in by default: the dedicated env dir if
it has been set up, else the currently active project (e.g. a dev checkout).
"""
function default_queue_env(; dedicated::AbstractString=default_queue_env_dir())::String
    isfile(joinpath(dedicated, "Project.toml")) && return dedicated
    proj = Base.active_project()
    proj === nothing && throw(ArgumentError("service: no active project; pass --project"))
    return DistSSHKit.canonical_local_path(dirname(proj))
end
