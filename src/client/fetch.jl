"""Client `fetch <id>`: inverse of stage. Copy one finished Kit leaf onto this job tree."""

const FETCH_SOURCE_SEP = '\t'
const FETCH_READY = (:done, :failed, :cancelled)

function posix_dir(path::AbstractString)::String
    return rstrip(replace(String(path), '\\' => '/'), '/')
end

function path_has_distsshkit(path::AbstractString)::Bool
    return any(p -> p == ".distsshkit", split(posix_dir(path), '/'; keepempty=false))
end

"""`result_path` relative to `root` (stage or local project). Refuses `..` and off-tree paths.

`canonicalize`: local omit-`qhost:` paths (macOS `/var` vs `/private/var`). Do not
canonicalize a queue-host stage path on the client.
"""
function fetch_relpath(
    result_path::AbstractString,
    root::AbstractString;
    canonicalize::Bool=false,
)::String
    raw_p = canonicalize ? DistSSHKit.canonical_local_path(result_path) : String(result_path)
    raw_r = canonicalize ? DistSSHKit.canonical_local_path(root) : String(root)
    p = posix_dir(raw_p)
    r = posix_dir(raw_r)
    (p == r || startswith(p, path_inside_prefix(r))) || throw(ArgumentError(
        "result is not under this client tree's stage; run fetch from the same job project as submit",
    ))
    rel = p == r ? "." : String(chopprefix(p, path_inside_prefix(r)))
    any(part -> part == ".." || part == ".", split(rel, '/'; keepempty=false)) && throw(ArgumentError(
        "fetch: refused relative path $(repr(rel))",
    ))
    return rel
end

function fetch_dest(local_proj::AbstractString, rel::AbstractString)::String
    rel == "." && throw(ArgumentError("fetch: result path is the project root"))
    dest = DistSSHKit.canonical_local_path(joinpath(local_proj, rel))
    path_under_project(dest, local_proj) || throw(ArgumentError(
        "fetch dest escapes the job project",
    ))
    path_has_distsshkit(dest) || throw(ArgumentError(
        "fetch only copies Kit .distsshkit leaves",
    ))
    return dest
end

function require_fetchable_leaf(id::AbstractString, result_path::AbstractString)
    leaf = basename(posix_dir(result_path))
    occursin(String(id), leaf) || throw(ArgumentError(
        "result leaf does not contain the job id (submit --output-dir is not fetchable)",
    ))
    path_has_distsshkit(result_path) || throw(ArgumentError(
        "fetch only copies Kit .distsshkit leaves",
    ))
    return nothing
end

"""One machine line: `state<TAB>abs-path`. Used by `hop_print`, not `main`."""
function fetch_source(id::AbstractString; store::AbstractString=store_path())::String
    q = Queue(; store=store)
    load!(q)
    j = job(q, id)
    j.state === :queued && throw(ArgumentError("job $(repr(id)) is still queued"))
    j.state === :running && throw(ArgumentError("job $(repr(id)) is still running"))
    p = j.result_path
    (p === nothing || isempty(strip(p))) && throw(ArgumentError(
        "job $(repr(id)) has no result_path",
    ))
    j.state in FETCH_READY || throw(ArgumentError(
        "job $(repr(id)) is $(j.state)",
    ))
    return string(j.state, FETCH_SOURCE_SEP, p)
end

function parse_fetch_source(line::AbstractString)
    s = String(line)
    i = findfirst(==(FETCH_SOURCE_SEP), s)
    i === nothing && throw(ArgumentError("fetch: bad source line"))
    st = Symbol(s[1:prevind(s, i)])
    path = s[nextind(s, i):end]
    isempty(path) && throw(ArgumentError("fetch: bad source line"))
    return st, path
end

"""Client-only marker after `qhost:` submit. Not a Kit leaf (`go/` / `drive/`)."""
const SUBMIT_TICKET_UUID =
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

function job_id_from_submit_stdout(out::AbstractString)::Union{Nothing,String}
    for line in eachsplit(String(out), '\n'; keepempty=false)
        s = strip(line)
        occursin(SUBMIT_TICKET_UUID, s) && return s
    end
    return nothing
end

function submit_ticket_path(root::AbstractString, id::AbstractString)::String
    return joinpath(String(root), ".distsshkit", "queue", String(id))
end

function write_submit_ticket(
    root::AbstractString,
    stdout_text::AbstractString;
    script::Union{Nothing,AbstractString}=nothing,
    qhost::Union{Nothing,AbstractString}=nothing,
)::Union{Nothing,String}
    id = job_id_from_submit_stdout(stdout_text)
    id === nothing && return nothing
    dest = submit_ticket_path(root, id)
    mkpath(dirname(dest))
    lines = String["id = $(repr(id))"]
    if script !== nothing && !isempty(strip(String(script)))
        sp = String(script)
        rel = try
            replace(
                relpath(
                    DistSSHKit.canonical_local_path(sp),
                    DistSSHKit.canonical_local_path(root),
                ),
                '\\' => '/',
            )
        catch
            replace(sp, '\\' => '/')
        end
        push!(lines, "script = $(repr(rel))")
    end
    if qhost !== nothing && !isempty(strip(String(qhost)))
        push!(lines, "qhost = $(repr(String(qhost)))")
    end
    write(dest, join(lines, '\n') * '\n')
    return dest
end

function local_fetch_dest(
    id::AbstractString,
    result_path::AbstractString,
    root::AbstractString;
    canonicalize::Bool=false,
)::String
    require_fetchable_leaf(id, result_path)
    rel = fetch_relpath(result_path, root; canonicalize=canonicalize)
    return fetch_dest(job_project(), rel)
end

function fetch_cli(
    qhost::Union{Nothing,AbstractString},
    gjulia::Union{Nothing,AbstractString},
    gqenv::Union{Nothing,AbstractString},
    rest::Vector{String},
)::Cint
    host, rjulia, qenv, payload = extract_remote_opts(rest)
    dest, spec = coalesce_remote(qhost, gjulia, host, rjulia)
    qe = coalesce_queue_env(gqenv, qenv)
    isempty(payload) && throw(ArgumentError("fetch: need a job id"))
    payload[1] in ("-h", "--help") && (show_usage(); return 0)
    length(payload) == 1 || throw(ArgumentError("fetch: extra arguments"))
    id = String(payload[1])
    local_proj = job_project()
    if dest === nothing
        st, path = parse_fetch_source(fetch_source(id))
        st in FETCH_READY || throw(ArgumentError("job $(repr(id)) is $(st)"))
        out = local_fetch_dest(id, path, local_proj; canonicalize=true)
        println(out)
        return 0
    end
    staging_enabled() || throw(ArgumentError(
        "qhost fetch needs rsync (unset DISTSSHQUEUE_NO_STAGE / DISTSSHKIT_TEST_SSH)",
    ))
    home = queue_host_homedir(dest, spec)
    stage_root = remote_stage_root(client_stage_key(local_proj); home=home)
    expr = "using DistSSHQueue; print(DistSSHQueue.fetch_source($(repr(id))))"
    st, path = parse_fetch_source(hop_print(dest, spec, expr; queue_env=qe))
    st in FETCH_READY || throw(ArgumentError("job $(repr(id)) is $(st)"))
    out = local_fetch_dest(id, path, stage_root)
    rsync_from_qhost!(dest, path, out)
    println(out)
    return 0
end
