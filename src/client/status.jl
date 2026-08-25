"""Client `status` / `watch`. Table lives on the queue host (after ssh if `qhost:HOST`)."""

function show_status(
    store::AbstractString;
    io::IO=stdout,
    via::Union{Nothing,AbstractString}=nothing,
)
    rows = isfile(store) ? read_jobs(store) : Job[]
    return print_status_table(store, rows; io=io, via=via)
end

function status_cli(args::Vector{String})::Cint
    via = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--via" && i < length(args)
            via = args[i+1]
            i += 2
        elseif a in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown status option: $(a)"))
        end
    end
    show_status(store_path(); via=via)
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

function watch!(
    store::AbstractString;
    interval::Float64=0.5,
    ticks::Union{Nothing,Int}=nothing,
    io::IO=stdout,
    via::Union{Nothing,AbstractString}=nothing,
)::Cint
    interval > 0 || throw(ArgumentError("watch: --interval must be > 0"))
    ticks === nothing || ticks >= 1 || throw(ArgumentError("watch: --ticks must be >= 1"))
    n = 0
    try
        while true
            n += 1
            rows = isfile(store) ? read_jobs(store) : Job[]
            _watch_redraw!(io) do
                print_watch_frame(store, rows; io=io, via=via)
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
    ticks = nothing
    via = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--interval" && i < length(args)
            interval = parse(Float64, args[i+1])
            i += 2
        elseif a == "--ticks" && i < length(args)
            ticks = parse(Int, args[i+1])
            i += 2
        elseif a == "--via" && i < length(args)
            via = args[i+1]
            i += 2
        elseif a in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown watch option: $(a)"))
        end
    end
    return watch!(store_path(); interval=interval, ticks=ticks, via=via)
end
