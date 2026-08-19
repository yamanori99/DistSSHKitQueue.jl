"""Waiter: one FIFO, one DistSSHKit job at a time. `host:N` is Kit's, not a Queue ceiling."""
mutable struct Placeholder
    lock::ReentrantLock
    jobs::Vector{PlaceholderJob}
    store::Union{Nothing,String}
    runner::Function
    live_id::Union{Nothing,String}
end

function Placeholder(;
    store::Union{Nothing,AbstractString}=nothing,
    runner::Function=kit_runner,
)
    st = store === nothing ? nothing : String(store)
    return Placeholder(ReentrantLock(), PlaceholderJob[], st, runner, nothing)
end

function kit_kwargs(d::Dict{String,Any})
    isempty(d) && return NamedTuple()
    acc = Pair{Symbol,Any}[]
    for (k, v) in d
        key = Symbol(k)
        if key === :sync && v isa AbstractString && (v == "sync" || v == "rsync")
            v = Symbol(v)
        elseif key === :args && v isa AbstractVector
            v = String[String(x) for x in v]
        end
        push!(acc, key => v)
    end
    return (; acc...)
end

function kit_result_path(result)::Union{Nothing,String}
    if hasproperty(result, :output_dir)
        p = getproperty(result, :output_dir)
        p === nothing && return nothing
        s = strip(String(p))
        return isempty(s) ? nothing : s
    end
    return nothing
end

function kit_result_path(j::PlaceholderJob, result)::Union{Nothing,String}
    p = kit_result_path(result)
    p !== nothing && return p
    od = get(j.kwargs, "output_dir", nothing)
    od === nothing && return nothing
    s = strip(String(od))
    return isempty(s) ? nothing : s
end

function require_kit_ok(kind::Symbol, result)
    hasproperty(result, :ok) || return nothing
    getproperty(result, :ok) && return nothing
    throw(ErrorException("DistSSHKit $kind failed (ok=false)"))
end

function kit_runner(j::PlaceholderJob)
    kw = kit_kwargs(j.kwargs)
    result = if j.kind === :go
        DistSSHKit.go!(j.script, j.hosts; kw...)
    else
        DistSSHKit.drive!(j.script, j.hosts; kw...)
    end
    require_kit_ok(j.kind, result)
    return kit_result_path(j, result)
end

function _persist!(h::Placeholder)
    return _persist!(h, h.store)
end
_persist!(::Placeholder, ::Nothing) = nothing
_persist!(h::Placeholder, store::String) = save_jobs(store, h.jobs)

function _with_store(f, h::Placeholder)
    return _with_store(f, h.store)
end
_with_store(f, ::Nothing) = f()
_with_store(f, store::String) = with_store_lock(f, store)

function _running(h::Placeholder)::Bool
    return any(j -> j.state === :running, h.jobs)
end

function placeholder_load!(h::Placeholder)
    _with_store(h) do
        lock(h.lock) do
            _load_from_store!(h, h.store)
            return nothing
        end
    end
end
_load_from_store!(::Placeholder, ::Nothing) = nothing
function _load_from_store!(h::Placeholder, store::String)
    h.jobs = load_jobs(store)
    _persist!(h)
    return nothing
end

function reload_keep_live!(h::Placeholder)
    return reload_keep_live!(h, h.store)
end
reload_keep_live!(::Placeholder, ::Nothing) = nothing
function reload_keep_live!(h::Placeholder, store::String)
    disk = load_jobs_raw(store)
    live = h.live_id
    live_job = nothing
    if live !== nothing
        i = findfirst(j -> j.id == live, h.jobs)
        if i !== nothing && h.jobs[i].state === :running
            live_job = h.jobs[i]
        end
    end
    out = PlaceholderJob[]
    seen = false
    for d in disk
        if live_job !== nothing && d.id == live
            push!(out, live_job)
            seen = true
        else
            push!(out, d)
        end
    end
    if live_job !== nothing && !seen
        push!(out, live_job)
    end
    h.jobs = out
    return nothing
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
    kw = Dict{String,Any}(String(k) => v for (k, v) in pairs(kwargs))
    j = PlaceholderJob(; kind=kind, script=script, hosts=toks, kwargs=kw)
    _with_store(h) do
        lock(h.lock) do
            reload_keep_live!(h)
            push!(h.jobs, j)
            _persist!(h)
        end
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
    return _with_store(h) do
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
end

function _finish!(h::Placeholder, id::AbstractString, state::Symbol, err; result_path=nothing)
    _with_store(h) do
        lock(h.lock) do
            i = findfirst(j -> j.id == id, h.jobs)
            i === nothing && return nothing
            j = h.jobs[i]
            j.state === :running || return nothing
            j.state = state
            j.finished_at = now(UTC)
            j.error = err === nothing ? nothing : String(err)
            if result_path !== nothing
                j.result_path = String(result_path)
            end
            h.live_id == id && (h.live_id = nothing)
            _persist!(h)
            return nothing
        end
    end
end

function _start!(h::Placeholder, j::PlaceholderJob)
    j.state = :running
    j.started_at = now(UTC)
    h.live_id = j.id
    _persist!(h)
    runner = h.runner
    id = j.id
    snap = copy(j)
    Threads.@spawn begin
        try
            out = runner(snap)
            path = out isa AbstractString ? String(out) : nothing
            if path === nothing
                od = get(snap.kwargs, "output_dir", nothing)
                path = od === nothing ? nothing : String(od)
            end
            _finish!(h, id, :done, nothing; result_path=path)
        catch e
            _finish!(h, id, :failed, sprint(showerror, e))
        end
    end
    return nothing
end

"""Start the FIFO head if nothing is `:running`. At most one Kit job."""
function placeholder_step!(h::Placeholder)::Int
    return _with_store(h) do
        lock(h.lock) do
            reload_keep_live!(h)
            _running(h) && return 0
            q = findfirst(j -> j.state === :queued, h.jobs)
            q === nothing && return 0
            _start!(h, h.jobs[q])
            return 1
        end
    end
end

"""Load `store` (stale `:running` → `:failed`), then step until interrupt. Ctrl-C stops the waiter, not Kit."""
function serve!(h::Placeholder; poll::Real=0.2)
    placeholder_load!(h)
    st = h.store === nothing ? "(memory)" : h.store
    println("DistSSHKitQueue serve  pid=$(getpid())  store=$st")
    println("Ctrl-C leaves the waiter; a running Kit job is not killed.")
    flush(stdout)
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

function serve(; store::AbstractString=default_store_path(), poll::Real=0.2, runner::Function=kit_runner)
    return serve!(Placeholder(; store=store, runner=runner); poll=poll)
end

const placeholder_head = serve!
