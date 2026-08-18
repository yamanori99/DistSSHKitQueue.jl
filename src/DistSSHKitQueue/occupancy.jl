# host:N occupancy. Same token shape as DistSSHKit (`local` / `l` / `localhost`).

function split_host_n(spec::AbstractString)::Tuple{String,Union{Nothing,Int}}
    s = strip(String(spec))
    isempty(s) && throw(ArgumentError("empty host token"))
    if contains(s, ':')
        parts = split(s, ':', limit=2)
        n = parse(Int, parts[2])
        n < 1 && throw(ArgumentError("slot count must be >= 1, got $n in $(repr(s))"))
        return String(parts[1]), n
    end
    return s, nothing
end

function host_key(name::AbstractString)::String
    n = String(strip(String(name)))
    return n in ("localhost", "local", "l") ? "local" : n
end

"""Demand per host key from DistSSHKit tokens (`host:N`; bare `host` is 1)."""
function demand_map(tokens::AbstractVector{<:AbstractString})::Dict{String,Int}
    out = Dict{String,Int}()
    for tok in tokens
        name, w = split_host_n(tok)
        k = host_key(name)
        out[k] = get(out, k, 0) + something(w, 1)
    end
    return out
end

function capacity_map(slots::AbstractVector{<:AbstractString})::Dict{String,Int}
    cap = demand_map(slots)
    isempty(cap) && throw(ArgumentError("Placeholder needs at least one slot token (e.g. local:2)"))
    return cap
end

function used_map(jobs::AbstractVector, cap::Dict{String,Int})::Dict{String,Int}
    used = Dict{String,Int}(k => 0 for k in keys(cap))
    for j in jobs
        j.state === :running || continue
        for (k, n) in demand_map(j.hosts)
            used[k] = get(used, k, 0) + n
        end
    end
    return used
end

function fits(cap::Dict{String,Int}, used::Dict{String,Int}, tokens::AbstractVector{<:AbstractString})::Bool
    for (k, n) in demand_map(tokens)
        haskey(cap, k) || return false
        get(used, k, 0) + n > cap[k] && return false
    end
    return true
end
