"""One hall row. `kwargs` is forwarded to DistSSHKit `go!` / `drive!`."""
mutable struct QueueJob
    id::String
    kind::Symbol
    script::String
    hosts::Vector{String}
    state::Symbol
    queued_at::DateTime
    started_at::Union{Nothing,DateTime}
    finished_at::Union{Nothing,DateTime}
    error::Union{Nothing,String}
    kwargs::Dict{String,Any}
end

function QueueJob(;
    id::AbstractString=string(Base.UUID(rand(UInt128))),
    kind::Symbol,
    script::AbstractString,
    hosts::AbstractVector{<:AbstractString},
    state::Symbol=:queued,
    queued_at::DateTime=now(UTC),
    started_at=nothing,
    finished_at=nothing,
    error=nothing,
    kwargs::Dict{String,Any}=Dict{String,Any}(),
)
    kind in (:go, :drive) || throw(ArgumentError("kind must be :go or :drive"))
    state in (:queued, :running, :done, :failed, :cancelled) ||
        throw(ArgumentError("bad job state $state"))
    isempty(hosts) && throw(ArgumentError("job needs at least one host token"))
    return QueueJob(
        String(id),
        kind,
        String(script),
        String[String(h) for h in hosts],
        state,
        queued_at,
        started_at,
        finished_at,
        error === nothing ? nothing : String(error),
        kwargs,
    )
end

function Base.copy(j::QueueJob)
    return QueueJob(
        j.id,
        j.kind,
        j.script,
        copy(j.hosts),
        j.state,
        j.queued_at,
        j.started_at,
        j.finished_at,
        j.error,
        copy(j.kwargs),
    )
end
