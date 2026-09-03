"""Client `status` / `watch`. Table lives on the queue host (after ssh if `qhost:HOST`)."""

function _kit_env_on(name::AbstractString)::Bool
    return strip(get(ENV, String(name), "")) in ("1", "true", "yes", "on")
end

function _set_status_watch_mode(
    mode::Union{Nothing,Symbol},
    v::Symbol,
)::Symbol
    if mode !== nothing && mode !== v
        throw(ArgumentError("cannot combine --quiet (-q), --progress, and --verbose"))
    end
    return v
end

"""Kit verbosity for `status` / `watch`. `:quiet` hides chrome; anything else is chrome.

`--progress` / `--verbose` / `DISTSSHKIT_PROGRESS` / `DISTSSHKIT_VERBOSE` are accepted
(same exclusive rule as DistSSHKit) but Queue has no live Kit run.
"""
function peel_status_watch_verbosity(args::Vector{String})
    mode = nothing
    n = count(identity, (
        _kit_env_on("DISTSSHKIT_QUIET"),
        _kit_env_on("DISTSSHKIT_PROGRESS"),
        _kit_env_on("DISTSSHKIT_VERBOSE"),
    ))
    n > 1 && throw(ArgumentError(
        "cannot combine DISTSSHKIT_QUIET, DISTSSHKIT_PROGRESS, and DISTSSHKIT_VERBOSE",
    ))
    _kit_env_on("DISTSSHKIT_QUIET") && (mode = _set_status_watch_mode(mode, :quiet))
    (_kit_env_on("DISTSSHKIT_PROGRESS") || _kit_env_on("DISTSSHKIT_VERBOSE")) &&
        (mode = _set_status_watch_mode(mode, :chrome))
    rest = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-q", "--quiet")
            mode = _set_status_watch_mode(mode, :quiet)
            i += 1
        elseif a == "--progress"
            mode = _set_status_watch_mode(mode, :chrome)
            i += 1
        elseif a == "--verbose"
            mode = _set_status_watch_mode(mode, :chrome)
            i += 1
        else
            push!(rest, a)
            i += 1
        end
    end
    return something(mode, :chrome), rest
end

"""Remaining flags after verbosity. `default_interval === nothing` is a snapshot (`status`)."""
function peel_status_watch_interval(
    rest::Vector{String};
    verb::AbstractString,
    default_interval::Union{Nothing,Float64},
)::Tuple{Symbol,Union{Nothing,Float64}}
    interval = default_interval
    i = 1
    while i <= length(rest)
        a = rest[i]
        if a == "--interval" && i < length(rest)
            interval = parse(Float64, rest[i + 1])
            i += 2
        elseif a in ("-h", "--help")
            return :help, interval
        else
            throw(ArgumentError("unknown $verb option: $(a)"))
        end
    end
    return :run, interval
end

function show_status(
    store::AbstractString;
    io::IO=stdout,
    qhost::Union{Nothing,AbstractString}=qhost_display_from_env(),
    quiet::Bool=false,
)
    rows = isfile(store) ? read_jobs(store) : Job[]
    return print_status_table(store, rows; io=io, qhost=qhost, quiet=quiet)
end

function status_cli(args::Vector{String})::Cint
    return _status_watch_cli(args; verb="status", default_interval=nothing)
end

function _watch_redraw!(f, io::IO)
    if io isa Base.TTY
        print(io, "\e[H\e[2J")
    end
    f()
    flush(io)
    return nothing
end

function watch_ticks_from_env()::Union{Nothing,Int}
    raw = strip(get(ENV, WATCH_TICKS_ENV, ""))
    isempty(raw) && return nothing
    n = tryparse(Int, raw)
    (n === nothing || n < 1) && throw(ArgumentError("watch: $WATCH_TICKS_ENV must be >= 1"))
    return n
end

"""Live `status` table until Ctrl-C (`watch` and `status --interval`).

`ticks` / `DISTSSHQUEUE_WATCH_TICKS` are a test harness (finite frames), not
product CLI. The verb `watch` stays; a later monitor package may own that
name (Kit `kit.progress` watchers).
"""
function watch!(
    store::AbstractString;
    interval::Float64=0.5,
    ticks::Union{Nothing,Int}=nothing,
    io::IO=stdout,
    qhost::Union{Nothing,AbstractString}=qhost_display_from_env(),
    quiet::Bool=false,
)::Cint
    interval > 0 || throw(ArgumentError("watch: --interval must be > 0"))
    ticks === nothing || ticks >= 1 || throw(ArgumentError("watch: $WATCH_TICKS_ENV must be >= 1"))
    n = 0
    try
        while true
            n += 1
            rows = isfile(store) ? read_jobs(store) : Job[]
            if quiet || io isa Base.TTY
                _watch_redraw!(io) do
                    print_watch_frame(store, rows; io=io, qhost=qhost, quiet=quiet)
                end
            else
                print_watch_compact(store, rows; io=io)
            end
            ticks !== nothing && n >= ticks && break
            sleep(interval)
        end
    catch e
        e isa InterruptException || rethrow()
    end
    return 0
end

function watch_cli(args::Vector{String})::Cint
    return _status_watch_cli(args; verb="watch", default_interval=0.5)
end

function _status_watch_cli(
    args::Vector{String};
    verb::AbstractString,
    default_interval::Union{Nothing,Float64},
)::Cint
    mode, rest = peel_status_watch_verbosity(args)
    kind, interval = peel_status_watch_interval(
        rest; verb=verb, default_interval=default_interval,
    )
    kind === :help && (show_usage(); return 0)
    quiet = mode === :quiet
    if interval === nothing
        show_status(store_path(); quiet=quiet)
        return 0
    end
    return watch!(
        store_path(); interval=interval, ticks=watch_ticks_from_env(), quiet=quiet,
    )
end
