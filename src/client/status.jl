"""Client `status` / `watch`. Table lives on the queue host (after ssh if `qhost:HOST`)."""

function show_status(
    store::AbstractString;
    io::IO=stdout,
    qhost::Union{Nothing,AbstractString}=qhost_display_from_env(),
)
    rows = isfile(store) ? read_jobs(store) : Job[]
    return print_status_table(store, rows; io=io, qhost=qhost)
end

function status_cli(args::Vector{String})::Cint
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown status option: $(a)"))
        end
    end
    show_status(store_path())
    return 0
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

"""Live `status` table until Ctrl-C.

`ticks` / `DISTSSHKITQUEUE_WATCH_TICKS` are a test harness (finite frames), not
product CLI. The verb `watch` is the table redraw; a later monitor package may
own that name (Kit `kit.progress` watchers).
"""
function watch!(
    store::AbstractString;
    interval::Float64=0.5,
    ticks::Union{Nothing,Int}=nothing,
    io::IO=stdout,
    qhost::Union{Nothing,AbstractString}=qhost_display_from_env(),
)::Cint
    interval > 0 || throw(ArgumentError("watch: --interval must be > 0"))
    ticks === nothing || ticks >= 1 || throw(ArgumentError("watch: $WATCH_TICKS_ENV must be >= 1"))
    n = 0
    try
        while true
            n += 1
            rows = isfile(store) ? read_jobs(store) : Job[]
            _watch_redraw!(io) do
                print_watch_frame(store, rows; io=io, qhost=qhost)
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
    interval = 0.5
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--interval" && i < length(args)
            interval = parse(Float64, args[i+1])
            i += 2
        elseif a in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown watch option: $(a)"))
        end
    end
    return watch!(store_path(); interval=interval, ticks=watch_ticks_from_env())
end
