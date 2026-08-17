"""In-process hall: FIFO table + occupancy. DistSSHKit runs one job at a time per Task."""
mutable struct Hall
    lock::ReentrantLock
    capacity::Dict{String,Int}
    jobs::Vector{QueueJob}
    store::Union{Nothing,String}
    runner::Function
end

function Hall(;
    slots::AbstractVector{<:AbstractString},
    store::Union{Nothing,AbstractString}=nothing,
    runner::Function=kit_runner,
)
    return Hall(ReentrantLock(), capacity_map(slots), QueueJob[], store, runner)
end

function kit_runner(j::QueueJob)
    kw = isempty(j.kwargs) ? NamedTuple() : (; (Symbol(k) => v for (k, v) in j.kwargs)...)
    if j.kind === :go
        DistSSHKit.go!(j.script, j.hosts; kw...)
    else
        DistSSHKit.drive!(j.script, j.hosts; kw...)
    end
    return nothing
end

function _persist!(h::Hall)
    h.store === nothing && return nothing
    save_jobs(h.store, h.jobs)
    return nothing
end

function load!(h::Hall)
    lock(h.lock) do
        h.store === nothing && return nothing
        h.jobs = load_jobs(h.store)
        _persist!(h)
        return nothing
    end
end

function occupancy(h::Hall)::NamedTuple{(:capacity, :used, :free),Tuple{Dict{String,Int},Dict{String,Int},Dict{String,Int}}}
    lock(h.lock) do
        used = used_map(h.jobs, h.capacity)
        free = Dict{String,Int}(k => h.capacity[k] - get(used, k, 0) for k in keys(h.capacity))
        return (capacity=copy(h.capacity), used=used, free=free)
    end
end

function jobs(h::Hall)::Vector{QueueJob}
    lock(h.lock) do
        return QueueJob[copy(j) for j in h.jobs]
    end
end

function job(h::Hall, id::AbstractString)::QueueJob
    lock(h.lock) do
        i = findfirst(j -> j.id == id, h.jobs)
        i === nothing && throw(ArgumentError("unknown job $(repr(id))"))
        return copy(h.jobs[i])
    end
end

function _submit!(h::Hall, kind::Symbol, script::AbstractString, hosts; kwargs...)
    toks = String[String(x) for x in hosts]
    dem = demand_map(toks)
    for k in keys(dem)
        haskey(h.capacity, k) ||
            throw(ArgumentError("host $(repr(k)) is not in hall slots $(collect(keys(h.capacity)))"))
        dem[k] > h.capacity[k] &&
            throw(ArgumentError("job asks for $k:$(dem[k]) but hall only has $k:$(h.capacity[k])"))
    end
    kw = Dict{String,Any}(String(k) => v for (k, v) in pairs(kwargs))
    j = QueueJob(; kind=kind, script=script, hosts=toks, kwargs=kw)
    lock(h.lock) do
        push!(h.jobs, j)
        _persist!(h)
    end
    return j.id
end

function submit_go!(h::Hall, script::AbstractString, hosts::AbstractString...; kwargs...)
    return _submit!(h, :go, script, hosts; kwargs...)
end

function submit_go!(h::Hall, script::AbstractString, hosts::AbstractVector{<:AbstractString}; kwargs...)
    return _submit!(h, :go, script, hosts; kwargs...)
end

function submit_drive!(h::Hall, script::AbstractString, hosts::AbstractString...; kwargs...)
    return _submit!(h, :drive, script, hosts; kwargs...)
end

function submit_drive!(h::Hall, script::AbstractString, hosts::AbstractVector{<:AbstractString}; kwargs...)
    return _submit!(h, :drive, script, hosts; kwargs...)
end

function cancel!(h::Hall, id::AbstractString)::Bool
    lock(h.lock) do
        i = findfirst(j -> j.id == id, h.jobs)
        i === nothing && throw(ArgumentError("unknown job $(repr(id))"))
        j = h.jobs[i]
        j.state === :queued || return false
        j.state = :cancelled
        j.finished_at = now(UTC)
        _persist!(h)
        return true
    end
end

function _finish!(h::Hall, id::AbstractString, state::Symbol, err)
    lock(h.lock) do
        i = findfirst(j -> j.id == id, h.jobs)
        i === nothing && return nothing
        j = h.jobs[i]
        j.state === :running || return nothing
        j.state = state
        j.finished_at = now(UTC)
        j.error = err === nothing ? nothing : String(err)
        _persist!(h)
        return nothing
    end
end

function _start!(h::Hall, j::QueueJob)
    j.state = :running
    j.started_at = now(UTC)
    _persist!(h)
    runner = h.runner
    id = j.id
    snap = copy(j)
    Threads.@spawn begin
        try
            runner(snap)
            _finish!(h, id, :done, nothing)
        catch e
            _finish!(h, id, :failed, sprint(showerror, e))
        end
    end
    return nothing
end

"""Start the FIFO head while it fits. Does not skip a blocked head (no backfill)."""
function step!(h::Hall)::Int
    n = 0
    lock(h.lock) do
        while true
            q = findfirst(j -> j.state === :queued, h.jobs)
            q === nothing && break
            j = h.jobs[q]
            used = used_map(h.jobs, h.capacity)
            fits(h.capacity, used, j.hosts) || break
            _start!(h, j)
            n += 1
        end
    end
    return n
end

"""Load `store`, then `step!` until interrupt. `poll` is the idle sleep (seconds)."""
function run_head(h::Hall; poll::Real=0.2)
    load!(h)
    try
        while true
            step!(h)
            sleep(poll)
        end
    catch e
        e isa InterruptException || rethrow()
        return nothing
    end
end
