"""FIFO table: one DistSSHKit job at a time. Placement tokens are Kit's, not a Queue ceiling."""
mutable struct Queue
    lock::ReentrantLock
    jobs::Vector{Job}
    store::Union{Nothing,String}
    runner::Function
    live_id::Union{Nothing,String}
    allowed::Union{Nothing,Set{String}}
end

function Queue(;
    store::Union{Nothing,AbstractString}=nothing,
    runner::Function=run_kit,
    allowed::Union{Nothing,AbstractVector,AbstractSet}=nothing,
)
    st = store === nothing ? nothing : String(store)
    names = allowed === nothing ? nothing :
        Set{String}(filter(!isempty, String[kit_ssh_name(String(x)) for x in allowed]))
    return Queue(ReentrantLock(), Job[], st, runner, nothing, names)
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

function kit_kwargs(d::Dict{String,Any})
    isempty(d) && return NamedTuple()
    acc = Pair{Symbol,Any}[]
    for (k, v) in d
        key = Symbol(k)
        val = if key === :sync && v isa AbstractString && (v == "sync" || v == "rsync")
            Symbol(v)
        elseif key === :verbosity && v isa AbstractString
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

"""Throw with the richest detail the result carries (`KitRunResult`: `failed_step`
/ `exit_code`), so `Job.error` and the status `ERROR` column are actionable."""
function require_kit_ok(result)
    hasproperty(result, :ok) || return nothing
    getproperty(result, :ok) && return nothing
    kind = hasproperty(result, :kind) ? getproperty(result, :kind) : :run
    step = hasproperty(result, :failed_step) ? getproperty(result, :failed_step) : nothing
    code = hasproperty(result, :exit_code) ? getproperty(result, :exit_code) : nothing
    msg = "DistSSHKit $kind failed"
    step === nothing || (msg *= " at $(step)")
    (code === nothing || code == 0) || (msg *= " (exit $(code))")
    throw(ErrorException(msg))
end

"""Keywords DistSSHKit `execute!(...; detached=true)` accepts, from the job bag.

`yes` is always `true` (unattended child). `path_anchor` and other names are dropped.
`job_id` is not taken from the bag; `run_kit` passes `Job.id`.
Allow-list is DistSSHKit `execute_detached_accepts`.
"""
function execute_kwargs(j::Job)
    raw = kit_kwargs(j.kwargs)
    acc = Pair{Symbol,Any}[]
    for (k, v) in pairs(raw)
        k === :yes && continue
        k === :job_id && continue
        v === nothing && continue
        DistSSHKit.execute_detached_accepts(k; kind=j.kind) || continue
        push!(acc, k => v)
    end
    push!(acc, :yes => true)
    return (; acc...)
end

"""`output_dir` already recorded, else the job bag (Kit may still pick a default)."""
function kit_output_dir(j::Job)::Union{Nothing,String}
    p = j.result_path
    p !== nothing && return p
    od = get(j.kwargs, "output_dir", nothing)
    od === nothing && return nothing
    s = strip(String(od))
    return isempty(s) ? nothing : s
end

"""Whether DistSSHKit's detached `kit.pid` still names this run (pid + start key)."""
function kit_child_alive(j::Job)::Bool
    dir = kit_output_dir(j)
    dir === nothing && return false
    return DistSSHKit.kit_pid_file_running(dir)
end

function kit_run_error_text(result)::String
    try
        require_kit_ok(result)
        return ""
    catch e
        e isa ErrorException || rethrow()
        return e.msg
    end
end

"""Pid gone: prefer `kit.result`, else `:failed` (waiter lost `KitProcess`)."""
function settle_lost_kit_child!(j::Job)
    dir = kit_output_dir(j)
    rec = dir === nothing ? nothing : DistSSHKit.kit_result_from_dir(dir)
    j.finished_at = now(UTC)
    if rec !== nothing && rec.ok
        j.state = :done
        j.error = nothing
        rec.output_dir !== nothing && (j.result_path = String(rec.output_dir))
    elseif rec !== nothing
        j.state = :failed
        j.error = kit_run_error_text(rec)
        rec.output_dir !== nothing && (j.result_path = String(rec.output_dir))
    else
        j.state = :failed
        j.error = "serve restarted; running job marked failed"
    end
    return j
end

function run_kit(j::Job, on_spawn)
    kp = DistSSHKit.execute!(
        j.kind,
        j.script,
        j.hosts;
        detached=true,
        job_id=j.id,
        execute_kwargs(j)...,
    )::DistSSHKit.KitProcess
    spawned = kit_result_path(kp)
    on_spawn(spawned)
    result = wait(kp)
    require_kit_ok(result)
    return kit_result_path(j, result)
end
run_kit(j::Job) = run_kit(j, Returns(nothing))

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

function _live_running(q::Queue)::Union{Nothing,Job}
    live = q.live_id
    live === nothing && return nothing
    i = findfirst(j -> j.id == live, q.jobs)
    i === nothing && return nothing
    j = q.jobs[i]
    return j.state === :running ? j : nothing
end

"""Merge disk into `q.jobs`.

The waiter overlays its in-memory live row whenever disk still has that
id and the disk row is not `:cancelled` (stale `load!` may have written
`:failed` without `kit.pid`; a later `_finish!(:done)` must still land).
Client `cancel!` persists `:cancelled`: that row wins, and `live_id` is
dropped so `_finish!(:done)` after `terminate_run!` cannot resurrect the
run.
"""
function reload_keep_live!(q::Queue)
    return reload_keep_live!(q, q.store)
end
reload_keep_live!(::Queue, ::Nothing) = nothing
function reload_keep_live!(q::Queue, store::String)
    disk = read_jobs(store)
    live = _live_running(q)
    out = Job[]
    seen = false
    for d in disk
        if live !== nothing && d.id == live.id
            seen = true
            if d.state === :cancelled
                push!(out, d)
                q.live_id = nothing
                live = nothing
            else
                push!(out, live)
            end
        else
            push!(out, d)
        end
    end
    if live !== nothing && !seen
        push!(out, live)
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
    for t in toks
        # Kit 0.4 classifier (`parent[:N]` / `child:NAME[:N]`). Not exported; Kit
        # tests and docs call it the same way.
        parsed = DistSSHKit.parse_placement_token(t)
        allow = q.allowed
        if allow !== nothing && !(parsed.name in allow)
            throw(ArgumentError(
                "Kit name $(repr(parsed.name)) is not allowed (token $(repr(t)))",
            ))
        end
    end
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

`hosts` must be DistSSHKit 0.4 placement tokens (`parent[:N]` / `child:NAME[:N]`).
Missing `project` uses `job_project()` (cwd / `DISTRIBUTED_PROJECT_ROOT`), not the
waiter `--project`. Same verb as CLI `submit`.

`q.allowed` is the inventory (`Queue(; allowed=…)`). It does not read
`config.toml`; CLI `submit` does (`allowed = ["parent", "host1"]`).
"""
function submit!(q::Queue, script::AbstractString, hosts::AbstractString...; kind::Symbol=:go, kwargs...)
    return _submit!(q, kind, script, hosts; kwargs...)
end

function submit!(q::Queue, script::AbstractString, hosts::AbstractVector{<:AbstractString}; kind::Symbol=:go, kwargs...)
    return _submit!(q, kind, script, hosts; kwargs...)
end

"""Cancel `:queued`, or `:running` via DistSSHKit `terminate_run!` when `result_path` / `output_dir` is known."""
function cancel!(q::Queue, id::AbstractString)::Bool
    action = _with_store(q) do
        lock(q.lock) do
            reload_keep_live!(q)
            i = findfirst(j -> j.id == id, q.jobs)
            i === nothing && throw(ArgumentError("unknown job $(repr(id))"))
            j = q.jobs[i]
            if j.state === :queued
                j.state = :cancelled
                j.finished_at = now(UTC)
                _persist!(q)
                return :queued
            end
            j.state === :running || return :no
            out_dir = kit_output_dir(j)
            out_dir === nothing && return :no
            return (out_dir, j.kind, j.id)
        end
    end
    if action isa Tuple{String,Symbol,String}
        running_dir, running_kind, running_id = action
        DistSSHKit.terminate_run!(running_dir; kind=running_kind)
        _finish!(q, running_id, :cancelled, nothing; result_path=running_dir)
        return true
    end
    return action === :queued
end

function _set_running_result_path!(q::Queue, id::AbstractString, path::AbstractString)
    _with_store(q) do
        lock(q.lock) do
            reload_keep_live!(q)
            i = findfirst(j -> j.id == id, q.jobs)
            i === nothing && return nothing
            j = q.jobs[i]
            j.state === :running || return nothing
            j.result_path = String(path)
            _persist!(q)
            return nothing
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
            # `:cancelled` must win a race with the spawn `_finish!(:failed)`
            # or `:done` after `terminate_run!` (wait can look successful).
            if state === :cancelled
                (j.state === :running || j.state === :failed || j.state === :done) ||
                    return nothing
            else
                j.state === :running || return nothing
            end
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
    on_spawn = function (p)
        p isa AbstractString && _set_running_result_path!(q, id, p)
        return nothing
    end
    Threads.@spawn begin
        try
            out = if runner === run_kit
                run_kit(snap, on_spawn)
            else
                runner(snap)
            end
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

const _ADOPT_LOST =
    "serve restarted; kit child exited (KitProcess lost; inspect RESULT / kit.result)"

"""If load kept a `:running` row because `kit.pid` is live, poll until it dies.

Does not spawn a second DistSSHKit child. Outcome from `kit.result` when present.
"""
function adopt_running!(q::Queue)
    snap = lock(q.lock) do
        i = findfirst(j -> j.state === :running, q.jobs)
        i === nothing && return nothing
        j = q.jobs[i]
        kit_child_alive(j) || return nothing
        q.live_id = j.id
        return copy(j)
    end
    snap === nothing && return nothing
    id = snap.id
    dir = kit_output_dir(snap)
    Threads.@spawn begin
        while true
            live = lock(q.lock) do
                i = findfirst(j -> j.id == id, q.jobs)
                i === nothing && return nothing
                copy(q.jobs[i])
            end
            live === nothing && return
            live.state === :running || return
            kit_child_alive(live) || break
            sleep(0.2)
        end
        rec = dir === nothing ? nothing : DistSSHKit.kit_result_from_dir(dir)
        if rec !== nothing && rec.ok
            path = rec.output_dir === nothing ? dir : rec.output_dir
            _finish!(q, id, :done, nothing; result_path=path)
        elseif rec !== nothing
            path = rec.output_dir === nothing ? dir : rec.output_dir
            _finish!(q, id, :failed, kit_run_error_text(rec); result_path=path)
        else
            _finish!(q, id, :failed, _ADOPT_LOST; result_path=dir)
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

function _running_copy(q::Queue)::Union{Nothing,Job}
    lock(q.lock) do
        i = findfirst(j -> j.state === :running, q.jobs)
        i === nothing && return nothing
        return copy(q.jobs[i])
    end
end

"""Load `store` (stale `:running` → `:failed`), then `step!` until interrupt. Ctrl-C stops the waiter, not Kit.

A second `serve` on the same store prints `Already running` and returns.
"""
function serve!(q::Queue; interval::Real=0.2)
    store = q.store
    if store isa String
        existing = waiter_pid(store)
        if existing !== nothing && existing != getpid()
            print_serve_already(existing, store)
            return nothing
        end
        # Claim the pidfile before `load!`. Two autoserve processes otherwise both
        # pass `waiter_alive` and the second `load_jobs` persists `:failed` on a
        # `:running` row that has no `kit.pid` yet.
        clear_stopped!(store)
        write_pid_file(store)
    end
    load!(q)
    adopt_running!(q)
    label = store isa String ? store : "(memory)"
    io = stdout
    print_serve_banner(getpid(), label)
    print_serve_idle_note(; io=io)
    draw = _serve_can_draw(io)
    flush(io)
    done = Ref(false)
    spin = if draw
        @async begin
            i = 1
            frames = DistSSHKit.SPINNER_FRAMES
            while !done[]
                print_serve_live_line(frames[i], _running_copy(q); io=io)
                i = i == length(frames) ? 1 : i + 1
                sleep(0.08)
            end
        end
    else
        nothing
    end
    owns() = store isa String ? (waiter_pid(store) == getpid()) : true
    gone = false
    # Skip the dir-lock + TOML parse of `step!` while the store is unchanged: an
    # idle waiter otherwise churns mkdir/rmdir + parse every `interval`. Any
    # client enqueue or our own persist bumps the mtime, so nothing is missed.
    last_mtime = Ref(typemin(Float64))
    try
        while true
            if !owns()
                gone = true
                break
            end
            if store isa String
                m = _store_mtime(store)
                # Kit writes kit.pid / kit.result without touching the table.
                # Skip only when idle; a running row still needs step!.
                if m != last_mtime[] || _running_copy(q) !== nothing
                    step!(q)
                    last_mtime[] = _store_mtime(store)
                end
            else
                step!(q)
            end
            sleep(interval)
        end
    catch e
        e isa InterruptException || rethrow()
        return nothing
    finally
        done[] = true
        spin isa Task && wait(spin)
        if draw
            print(io, "\r\e[K")
            flush(io)
        end
        if gone
            print_waiter_gone(label; io=io)
        elseif store isa String && waiter_pid(store) == getpid()
            remove_pid_file(store)
        end
    end
    return nothing
end

function serve(; store::AbstractString=default_store_path(), interval::Real=0.2, runner::Function=run_kit)
    return serve!(Queue(; store=store, runner=runner); interval=interval)
end
