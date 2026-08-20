"""FIFO table: one DistSSHKit job at a time. `host:N` is Kit's, not a Queue ceiling."""
mutable struct Queue
    lock::ReentrantLock
    jobs::Vector{Job}
    store::Union{Nothing,String}
    runner::Function
    live_id::Union{Nothing,String}
end

function Queue(;
    store::Union{Nothing,AbstractString}=nothing,
    runner::Function=run_kit,
)
    st = store === nothing ? nothing : String(store)
    return Queue(ReentrantLock(), Job[], st, runner, nothing)
end

"""Kit job tree: `DISTRIBUTED_PROJECT_ROOT`, else the `Project.toml` above `cwd`, else `cwd`.

Not the Julia `--project=` that loaded DistSSHKitQueue.
"""
function job_project(; cwd::AbstractString=pwd())::String
    env = strip(get(ENV, "DISTRIBUTED_PROJECT_ROOT", ""))
    isempty(env) || return DistSSHKit.canonical_local_path(env)
    host = DistSSHKit.resolve_pkg_project_dir(cwd)
    root = isfile(joinpath(host, "Project.toml")) ? String(host) : String(cwd)
    return DistSSHKit.canonical_local_path(root)
end

resolve_script(path::AbstractString) = DistSSHKit.canonical_local_path(path)

# DistSSHKit `execute!(...; detached=true)` allow-list (not stdout/stderr).
const _EXECUTE_SHARED = (
    :output_dir,
    :args,
    :project,
    :sync,
    :julia,
    :quiet,
    :verbosity,
    :remote,
    :hosts_file,
)
const _EXECUTE_DRIVE_ONLY = (
    :log_dir,
    :enable_log,
    :package,
    :require_all_hosts,
    :skip_hash_check,
)

function kit_kwargs(d::Dict{String,Any})
    isempty(d) && return NamedTuple()
    acc = Pair{Symbol,Any}[]
    for (k, v) in d
        key = Symbol(k)
        val = if key === :sync && v isa AbstractString && (v == "sync" || v == "rsync")
            Symbol(v)
        elseif key === :args && v isa AbstractVector
            String[String(x) for x in v]
        else
            v
        end
        push!(acc, key => val)
    end
    return (; acc...)
end

function kit_result_path(result)::Union{Nothing,String}
    hasproperty(result, :output_dir) || return nothing
    p = getproperty(result, :output_dir)
    p === nothing && return nothing
    s = strip(String(p))
    return isempty(s) ? nothing : s
end

function kit_result_path(j::Job, result)::Union{Nothing,String}
    p = kit_result_path(result)
    p !== nothing && return p
    od = get(j.kwargs, "output_dir", nothing)
    od === nothing && return nothing
    s = strip(String(od))
    return isempty(s) ? nothing : s
end

function require_kit_ok(result)
    hasproperty(result, :ok) || return nothing
    getproperty(result, :ok) && return nothing
    kind = hasproperty(result, :kind) ? getproperty(result, :kind) : :run
    throw(ErrorException("DistSSHKit $kind failed (ok=false)"))
end

"""Keywords DistSSHKit `execute!(...; detached=true)` accepts, from the job bag.

`yes` is always `true` (unattended child). `path_anchor` and other names are dropped.
"""
function execute_kwargs(j::Job)
    raw = kit_kwargs(j.kwargs)
    acc = Pair{Symbol,Any}[]
    for (k, v) in pairs(raw)
        k === :yes && continue
        v === nothing && continue
        if k in _EXECUTE_DRIVE_ONLY
            j.kind === :drive || continue
        elseif !(k in _EXECUTE_SHARED)
            continue
        end
        push!(acc, k => v)
    end
    push!(acc, :yes => true)
    return (; acc...)
end

function run_kit(j::Job)
    kp = DistSSHKit.execute!(j.kind, j.script, j.hosts; detached=true, execute_kwargs(j)...)::DistSSHKit.KitProcess
    result = wait(kp)
    require_kit_ok(result)
    return kit_result_path(j, result)
end

function _persist!(q::Queue)
    return _persist!(q, q.store)
end
_persist!(::Queue, ::Nothing) = nothing
_persist!(q::Queue, store::String) = save_jobs(store, q.jobs)

function _with_store(f, q::Queue)
    return _with_store(f, q.store)
end
_with_store(f, ::Nothing) = f()
_with_store(f, store::String) = with_store_lock(f, store)

function _running(q::Queue)::Bool
    return any(j -> j.state === :running, q.jobs)
end

"""Load `store` (stale `:running` → `:failed`)."""
function load!(q::Queue)
    _with_store(q) do
        lock(q.lock) do
            _load_from_store!(q, q.store)
            return nothing
        end
    end
end
_load_from_store!(::Queue, ::Nothing) = nothing
function _load_from_store!(q::Queue, store::String)
    q.jobs = load_jobs(store)
    _persist!(q)
    return nothing
end

function reload_keep_live!(q::Queue)
    return reload_keep_live!(q, q.store)
end
reload_keep_live!(::Queue, ::Nothing) = nothing
function reload_keep_live!(q::Queue, store::String)
    disk = read_jobs(store)
    live = q.live_id
    live_job = nothing
    if live !== nothing
        i = findfirst(j -> j.id == live, q.jobs)
        if i !== nothing && q.jobs[i].state === :running
            live_job = q.jobs[i]
        end
    end
    out = Job[]
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
    q.jobs = out
    return nothing
end

"""Copy of the table."""
function jobs(q::Queue)::Vector{Job}
    lock(q.lock) do
        return Job[copy(j) for j in q.jobs]
    end
end

"""Copy of one row."""
function job(q::Queue, id::AbstractString)::Job
    lock(q.lock) do
        i = findfirst(j -> j.id == id, q.jobs)
        i === nothing && throw(ArgumentError("unknown job $(repr(id))"))
        return copy(q.jobs[i])
    end
end

function _submit!(q::Queue, kind::Symbol, script::AbstractString, hosts; kwargs...)
    toks = String[String(x) for x in hosts]
    kw = Dict{String,Any}(String(k) => v for (k, v) in pairs(kwargs))
    haskey(kw, "project") || (kw["project"] = job_project())
    j = Job(; kind=kind, script=resolve_script(script), hosts=toks, kwargs=kw)
    _with_store(q) do
        lock(q.lock) do
            reload_keep_live!(q)
            push!(q.jobs, j)
            _persist!(q)
        end
    end
    return j.id
end

"""Enqueue. `kind=:go` or `:drive` (DistSSHKit `execute!`).

Missing `project` uses `job_project()` (cwd / `DISTRIBUTED_PROJECT_ROOT`), not the
waiter `--project`. Same verb as CLI `submit`.
"""
function submit!(q::Queue, script::AbstractString, hosts::AbstractString...; kind::Symbol=:go, kwargs...)
    return _submit!(q, kind, script, hosts; kwargs...)
end

function submit!(q::Queue, script::AbstractString, hosts::AbstractVector{<:AbstractString}; kind::Symbol=:go, kwargs...)
    return _submit!(q, kind, script, hosts; kwargs...)
end

"""Cancel if `:queued`. Reloads the store first (client CLI). Returns `false` if not queued."""
function cancel!(q::Queue, id::AbstractString)::Bool
    return _with_store(q) do
        lock(q.lock) do
            reload_keep_live!(q)
            i = findfirst(j -> j.id == id, q.jobs)
            i === nothing && throw(ArgumentError("unknown job $(repr(id))"))
            j = q.jobs[i]
            j.state === :queued || return false
            j.state = :cancelled
            j.finished_at = now(UTC)
            _persist!(q)
            return true
        end
    end
end

function _finish!(q::Queue, id::AbstractString, state::Symbol, err; result_path=nothing)
    _with_store(q) do
        lock(q.lock) do
            reload_keep_live!(q)
            i = findfirst(j -> j.id == id, q.jobs)
            i === nothing && return nothing
            j = q.jobs[i]
            j.state === :running || return nothing
            j.state = state
            j.finished_at = now(UTC)
            j.error = err === nothing ? nothing : String(err)
            if result_path !== nothing
                j.result_path = String(result_path)
            end
            q.live_id == id && (q.live_id = nothing)
            _persist!(q)
            return nothing
        end
    end
end

function _start!(q::Queue, j::Job)
    j.state = :running
    j.started_at = now(UTC)
    q.live_id = j.id
    _persist!(q)
    runner = q.runner
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
            _finish!(q, id, :done, nothing; result_path=path)
        catch e
            _finish!(q, id, :failed, sprint(showerror, e))
        end
    end
    return nothing
end

"""Start the FIFO head if nothing is `:running`. At most one Kit job."""
function step!(q::Queue)::Int
    return _with_store(q) do
        lock(q.lock) do
            reload_keep_live!(q)
            _running(q) && return 0
            i = findfirst(j -> j.state === :queued, q.jobs)
            i === nothing && return 0
            _start!(q, q.jobs[i])
            return 1
        end
    end
end

"""Load `store` (stale `:running` → `:failed`), then `step!` until interrupt. Ctrl-C stops the waiter, not Kit."""
function serve!(q::Queue; interval::Real=0.2)
    load!(q)
    st = q.store === nothing ? "(memory)" : q.store
    st isa String && write_pid_file(st)
    println("DistSSHKitQueue serve  pid=$(getpid())  store=$st")
    println("Ctrl-C leaves the waiter; a running Kit job is not killed.")
    flush(stdout)
    try
        while true
            step!(q)
            sleep(interval)
        end
    catch e
        e isa InterruptException || rethrow()
        return nothing
    finally
        st isa String && remove_pid_file(st)
    end
end

function serve(; store::AbstractString=default_store_path(), interval::Real=0.2, runner::Function=run_kit)
    return serve!(Queue(; store=store, runner=runner); interval=interval)
end
