"""In-process table: FIFO + slots. DistSSHKit runs one job at a time per Task."""
mutable struct Placeholder
    lock::ReentrantLock
    capacity::Dict{String,Int}
    jobs::Vector{PlaceholderJob}
    store::Union{Nothing,String}
    runner::Function
end

function Placeholder(;
    slots::AbstractVector{<:AbstractString},
    store::Union{Nothing,AbstractString}=nothing,
    runner::Function=kit_runner,
)
    return Placeholder(ReentrantLock(), capacity_map(slots), PlaceholderJob[], store, runner)
end

function kit_runner(j::PlaceholderJob)
    kw = isempty(j.kwargs) ? NamedTuple() : (; (Symbol(k) => v for (k, v) in j.kwargs)...)
    if j.kind === :go
        DistSSHKit.go!(j.script, j.hosts; kw...)
    else
        DistSSHKit.drive!(j.script, j.hosts; kw...)
    end
    return nothing
end

function _persist!(h::Placeholder)
    h.store === nothing && return nothing
    save_jobs(h.store, h.jobs)
    return nothing
end

function placeholder_load!(h::Placeholder)
    lock(h.lock) do
        h.store === nothing && return nothing
        h.jobs = load_jobs(h.store)
        _persist!(h)
        return nothing
    end
end

function placeholder_slots(h::Placeholder)::NamedTuple{(:capacity, :used, :free),Tuple{Dict{String,Int},Dict{String,Int},Dict{String,Int}}}
    lock(h.lock) do
        used = used_map(h.jobs, h.capacity)
        free = Dict{String,Int}(k => h.capacity[k] - get(used, k, 0) for k in keys(h.capacity))
        return (capacity=copy(h.capacity), used=used, free=free)
    end
end

function placeholder_list(h::Placeholder)::Vector{PlaceholderJob}
    lock(h.lock) do
        return PlaceholderJob[copy(j) for j in h.jobs]
    end
end

function placeholder_get(h::Placeholder, id::AbstractString)::PlaceholderJob
    lock(h.lock) do
        i = findfirst(j -> j.id == id, h.jobs)
        i === nothing && throw(ArgumentError("unknown job $(repr(id))"))
        return copy(h.jobs[i])
    end
end

function _submit!(h::Placeholder, kind::Symbol, script::AbstractString, hosts; kwargs...)
    toks = String[String(x) for x in hosts]
    dem = demand_map(toks)
    for k in keys(dem)
        haskey(h.capacity, k) ||
            throw(ArgumentError("host $(repr(k)) is not in slots $(collect(keys(h.capacity)))"))
        dem[k] > h.capacity[k] &&
            throw(ArgumentError("job asks for $k:$(dem[k]) but only $k:$(h.capacity[k]) is configured"))
    end
    kw = Dict{String,Any}(String(k) => v for (k, v) in pairs(kwargs))
    j = PlaceholderJob(; kind=kind, script=script, hosts=toks, kwargs=kw)
    lock(h.lock) do
        push!(h.jobs, j)
        _persist!(h)
    end
    return j.id
end

"""Enqueue. `drive=true` means DistSSHKit `drive!`; default is `go!`. Name is a placeholder."""
function placeholder!(h::Placeholder, script::AbstractString, hosts::AbstractString...; drive::Bool=false, kwargs...)
    return _submit!(h, drive ? :drive : :go, script, hosts; kwargs...)
end

function placeholder!(h::Placeholder, script::AbstractString, hosts::AbstractVector{<:AbstractString}; drive::Bool=false, kwargs...)
    return _submit!(h, drive ? :drive : :go, script, hosts; kwargs...)
end

function placeholder_cancel!(h::Placeholder, id::AbstractString)::Bool
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

function _finish!(h::Placeholder, id::AbstractString, state::Symbol, err)
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

function _start!(h::Placeholder, j::PlaceholderJob)
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
function placeholder_step!(h::Placeholder)::Int
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

"""Load `store`, then `placeholder_step!` until interrupt. `poll` is the idle sleep (seconds)."""
function placeholder_head(h::Placeholder; poll::Real=0.2)
    placeholder_load!(h)
    try
        while true
            placeholder_step!(h)
            sleep(poll)
        end
    catch e
        e isa InterruptException || rethrow()
        return nothing
    end
end
