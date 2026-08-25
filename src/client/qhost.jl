"""Client `qhost:NAME` / `--remote-julia`: peel flags and `run_on_host` to the queue host.

Kit `--hosts` / `--julia` stay on `go` / `drive`. `setup` / `serve` /
`enable` / `disable` / `add-host` / `remove-host` are not forwarded.
Not a Kit placement token.
"""

function default_remote_julia()::String
    envj = strip(get(ENV, "JULIA_DISTRIBUTED_EXE", ""))
    return isempty(envj) ? "auto" : envj
end

"""SSH name from a `qhost:NAME` token."""
function parse_qhost_token(raw::AbstractString)::String
    s = strip(String(raw))
    startswith(s, "qhost:") || throw(ArgumentError("queue host is `qhost:NAME`, not $(repr(s))"))
    name = strip(chopprefix(s, "qhost:"))
    isempty(name) && throw(ArgumentError("`qhost:` needs an SSH name"))
    return String(name)
end

"""SSH name shown on `status` / `watch`. Set by the client hop; not a CLI flag."""
const QHOST_DISPLAY_ENV = "DISTSSHKITQUEUE_QHOST"

function qhost_display_from_env()::Union{Nothing,String}
    v = strip(get(ENV, QHOST_DISPLAY_ENV, ""))
    return isempty(v) ? nothing : String(v)
end

function _set_qhost(cur::Union{Nothing,String}, next::AbstractString)::String
    n = String(next)
    if cur !== nothing && cur != n
        throw(ArgumentError("queue host given twice ($cur and $n)"))
    end
    return n
end

"""Peel leading `qhost:NAME` / `--remote-julia PATH`. `rjulia` is `nothing` if omitted."""
function extract_remote_opts(args::Vector{String})
    host = nothing
    rjulia = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--qhost"
            throw(ArgumentError("use `qhost:NAME`, not `--qhost`"))
        elseif startswith(a, "qhost:")
            host = _set_qhost(host, parse_qhost_token(a))
            i += 1
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
        throw(ArgumentError("queue host given twice ($(ahost) and $(bhost))"))
    end
    host = ahost !== nothing ? String(ahost) : (bhost === nothing ? nothing : String(bhost))
    spec = ajulia !== nothing ? String(ajulia) :
           (bjulia !== nothing ? String(bjulia) : default_remote_julia())
    return host, spec
end

const QHOST_LOCAL_VERBS = ("setup", "serve", "enable", "disable", "service", "add-host", "remove-host")

"""Queue CLI verbs. Anything else with a `.jl` is Kit `go` argv (DistSSHKit shorthand)."""
const QUEUE_CLI_VERBS = (
    QHOST_LOCAL_VERBS...,
    "stop",
    "status",
    "list-host",
    "size",
    "watch",
    "submit",
    "go",
    "drive",
    "cancel",
    "teardown",
)

"""True when `after` is DistSSHKit go argv, not a Queue verb (`--hosts … SCRIPT.jl`)."""
function looks_like_kit_go_argv(after::Vector{String})::Bool
    isempty(after) && return false
    a = after[1]
    a in QUEUE_CLI_VERBS && return false
    a in ("-h", "--help", "help") && return false
    return any(endswith(String(x), ".jl") for x in after)
end

function reject_qhost_on_local(sub::AbstractString, host::Union{Nothing,AbstractString})
    host === nothing && return nothing
    sub in QHOST_LOCAL_VERBS || return nothing
    throw(ArgumentError(
        "`qhost:NAME` is a client token; `$sub` runs on the queue host. " *
        "Log in there and run it, or omit `qhost:` if this machine is the queue host.",
    ))
end

function remote_dispatch(
    host::AbstractString,
    rjulia::AbstractString,
    sub::AbstractString,
    payload::Vector{String};
    tty::Bool=false,
    qhost_display::Union{Nothing,AbstractString}=nothing,
)::Cint
    label = qhost_display === nothing ? nothing : strip(String(qhost_display))
    if label !== nothing && !isempty(label)
        args = String[String(sub)]
        append!(args, String[String(a) for a in payload])
        expr = "ENV[$(repr(QHOST_DISPLAY_ENV))] = $(repr(label)); exit(Int(DistSSHKitQueue.main($(repr(args)))))"
        argv = String["-e", "using DistSSHKitQueue; " * expr]
    else
        argv = String["-m", "DistSSHKitQueue", String(sub)]
        append!(argv, payload)
    end
    spec = strip(String(rjulia))
    auto = isempty(spec) || spec == "auto"
    proc = DistSSHKit.run_on_host(
        host,
        argv;
        julia=auto ? nothing : spec,
        detect=auto,
        tty=tty,
    )
    code = Int(something(proc.exitcode, 1))
    if code == 127
        throw(ArgumentError(
            "no Julia on $(host) (ssh PATH is often empty; Kit tries juliaup then Homebrew). " *
            "Pass --remote-julia PATH or set JULIA_DISTRIBUTED_EXE, like Kit --julia.",
        ))
    end
    return Cint(code)
end

"""If a queue host is set, ssh `sub` + `rest` and return the exit code; else `nothing`.

`label_qhost`: remote `status` / `watch` print the client token via
`DISTSSHKITQUEUE_QHOST` (not a CLI flag; re-passing `qhost:` would recurse).
"""
function maybe_remote(
    qhost::Union{Nothing,AbstractString},
    gjulia::Union{Nothing,AbstractString},
    sub::AbstractString,
    rest::Vector{String};
    tty::Bool=false,
    label_qhost::Bool=false,
)::Union{Nothing,Cint}
    host, rjulia, payload = extract_remote_opts(rest)
    dest, spec = coalesce_remote(qhost, gjulia, host, rjulia)
    dest === nothing && return nothing
    disp = label_qhost ? dest : nothing
    return remote_dispatch(dest, spec, sub, payload; tty=tty, qhost_display=disp)
end
