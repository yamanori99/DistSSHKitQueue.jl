"""Client `--qhost` / `--remote-julia`: peel flags and ssh to the queue host.

`setup` / `serve` / `enable` / `disable` are not forwarded. Not Kit `host:N`.
"""

function default_remote_julia()::String
    envj = strip(get(ENV, "JULIA_DISTRIBUTED_EXE", ""))
    return isempty(envj) ? "auto" : envj
end

"""Peel leading `--qhost HOST` / `--remote-julia PATH`. `rjulia` is `nothing` if omitted."""
function extract_remote_opts(args::Vector{String})
    host = nothing
    rjulia = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--qhost" && i < length(args)
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
        throw(ArgumentError("`--qhost` given twice ($(ahost) and $(bhost))"))
    end
    host = ahost !== nothing ? String(ahost) : (bhost === nothing ? nothing : String(bhost))
    spec = ajulia !== nothing ? String(ajulia) :
           (bjulia !== nothing ? String(bjulia) : default_remote_julia())
    return host, spec
end

const QHOST_LOCAL_VERBS = ("setup", "serve", "enable", "disable", "service")

function reject_qhost_on_local(sub::AbstractString, host::Union{Nothing,AbstractString})
    host === nothing && return nothing
    sub in QHOST_LOCAL_VERBS || return nothing
    throw(ArgumentError(
        "`--qhost` is a client flag; `$sub` runs on the queue host. " *
        "Log in there and run it, or omit `--qhost` if this machine is the queue host.",
    ))
end

"""`julia -m DistSSHKitQueue <sub> <payload…>`, each token shell-quoted for ssh."""
function remote_inner(rjulia::AbstractString, sub::AbstractString, payload::Vector{String})::String
    parts = String[String(rjulia), "-m", "DistSSHKitQueue", String(sub)]
    append!(parts, payload)
    return join((sh_single_quote(p) for p in parts), " ")
end

function remote_command(
    host::AbstractString,
    rjulia::AbstractString,
    sub::AbstractString,
    payload::Vector{String};
    tty::Bool=false,
)::Cmd
    inner = remote_inner(rjulia, sub, payload)
    ssh = String["ssh"]
    tty && push!(ssh, "-t")
    append!(ssh, DistSSHKit.ssh_opts())
    push!(ssh, String(host), inner)
    return Cmd(ssh)
end

function resolve_on_julia(host::AbstractString, spec::AbstractString)::String
    found = DistSSHKit.resolve_remote_julia(String(host), spec)
    found === nothing && throw(ArgumentError(
        "no Julia on $(host) (ssh PATH is often empty; Kit tries juliaup then Homebrew). " *
        "Pass --remote-julia PATH or set JULIA_DISTRIBUTED_EXE, like Kit --julia.",
    ))
    return found
end

function remote_dispatch(
    host::AbstractString,
    rjulia::AbstractString,
    sub::AbstractString,
    payload::Vector{String};
    tty::Bool=false,
)::Cint
    jl = resolve_on_julia(host, rjulia)
    proc = run(ignorestatus(remote_command(host, jl, sub, payload; tty=tty)))
    return Cint(proc.exitcode)
end

"""If `--qhost` is set, ssh `sub` + `rest` and return the exit code; else `nothing`."""
function maybe_remote(
    qhost::Union{Nothing,AbstractString},
    gjulia::Union{Nothing,AbstractString},
    sub::AbstractString,
    rest::Vector{String};
    tty::Bool=false,
)::Union{Nothing,Cint}
    host, rjulia, payload = extract_remote_opts(rest)
    dest, spec = coalesce_remote(qhost, gjulia, host, rjulia)
    dest === nothing && return nothing
    return remote_dispatch(dest, spec, sub, payload; tty=tty)
end
