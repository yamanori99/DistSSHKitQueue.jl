using TOML

function _dt(x)::Union{Nothing,DateTime}
    x === nothing && return nothing
    x isa DateTime && return x
    return DateTime(String(x))
end

function job_to_toml(j::PlaceholderJob)::Dict{String,Any}
    return Dict{String,Any}(
        "id" => j.id,
        "kind" => String(j.kind),
        "script" => j.script,
        "hosts" => copy(j.hosts),
        "state" => String(j.state),
        "queued_at" => string(j.queued_at),
        "started_at" => j.started_at === nothing ? "" : string(j.started_at),
        "finished_at" => j.finished_at === nothing ? "" : string(j.finished_at),
        "error" => j.error === nothing ? "" : j.error,
        "kwargs" => Dict{String,Any}(j.kwargs),
    )
end

function job_from_toml(d::AbstractDict)::PlaceholderJob
    err = String(get(d, "error", ""))
    started = String(get(d, "started_at", ""))
    finished = String(get(d, "finished_at", ""))
    kw = get(d, "kwargs", Dict{String,Any}())
    return PlaceholderJob(;
        id=String(d["id"]),
        kind=Symbol(d["kind"]),
        script=String(d["script"]),
        hosts=String[String(h) for h in d["hosts"]],
        state=Symbol(d["state"]),
        queued_at=_dt(d["queued_at"]),
        started_at=isempty(started) ? nothing : _dt(started),
        finished_at=isempty(finished) ? nothing : _dt(finished),
        error=isempty(err) ? nothing : err,
        kwargs=Dict{String,Any}(String(k) => v for (k, v) in kw),
    )
end

function save_jobs(path::AbstractString, jobs::AbstractVector{PlaceholderJob})
    p = String(path)
    mkpath(dirname(p))
    data = Dict{String,Any}("jobs" => [job_to_toml(j) for j in jobs])
    open(p, "w") do io
        TOML.print(io, data)
    end
    return nothing
end

function load_jobs(path::AbstractString)::Vector{PlaceholderJob}
    isfile(path) || return PlaceholderJob[]
    raw = TOML.parsefile(String(path))
    rows = get(raw, "jobs", nothing)
    rows isa AbstractVector || return PlaceholderJob[]
    out = PlaceholderJob[job_from_toml(r) for r in rows]
    for j in out
        if j.state === :running
            j.state = :failed
            j.finished_at = now(UTC)
            j.error = "head restarted; running job marked failed"
        end
    end
    return out
end
