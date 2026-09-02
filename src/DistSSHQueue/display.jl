"""CLI chrome. Reuses DistSSHKit help helpers; job ids stay a bare line on stdout."""

_q_short(path::String)::String = DistSSHKit.short_path(path)
function _q_short(path::AbstractString)::String
    return DistSSHKit.short_path(string(path)::String)
end

function _q_cell(t::String, w::Int)::String
    n = length(t)
    n >= w && return t
    return string(t, " "^(w - n))
end

const _ID_PREFIX_MIN = 8

"""Path relative to `root`, or `nothing` if it is not inside."""
function _rel_under(path::AbstractString, root::AbstractString)::Union{Nothing,String}
    p = DistSSHKit.canonical_local_path(String(path))
    r = DistSSHKit.canonical_local_path(String(root))
    p == r && return "."
    pref = path_inside_prefix(r)
    startswith(p, pref) || return nothing
    return String(chopprefix(p, pref))
end

function _job_project_disp(j::Job)::String
    p = get(j.kwargs, "project", nothing)
    p isa AbstractString || return ""
    can = DistSSHKit.canonical_local_path(String(p))
    can == DistSSHKit.canonical_local_path(pwd()) && return "."
    return _q_short(String(p))
end

function _job_script_disp(j::Job)::String
    p = get(j.kwargs, "project", nothing)
    if p isa AbstractString
        rel = _rel_under(j.script, p)
        rel !== nothing && return rel
    end
    return _q_short(j.script)
end

function _job_result_disp(j::Job)::String
    r = j.result_path
    r isa AbstractString || return ""
    p = get(j.kwargs, "project", nothing)
    if p isa AbstractString
        rel = _rel_under(r, p)
        rel !== nothing && return rel
    end
    return _q_short(r)
end

"""Shortest unique prefixes (`minlen` or more) for `ids`, same order."""
function _unique_prefixes(
    ids::AbstractVector{<:AbstractString};
    minlen::Int=_ID_PREFIX_MIN,
)::Vector{String}
    n = length(ids)
    out = Vector{String}(undef, n)
    for i in 1:n
        id = String(ids[i])
        L = min(max(minlen, 1), length(id))
        while L < length(id)
            p = first(id, L)
            amb = false
            for j in 1:n
                j == i && continue
                startswith(String(ids[j]), p) && (amb = true; break)
            end
            amb || break
            L += 1
        end
        out[i] = first(id, L)
    end
    return out
end

function _id_chrome(id::AbstractString, ids::AbstractVector{<:AbstractString})::String
    ps = _unique_prefixes(ids)
    for i in eachindex(ids)
        String(ids[i]) == String(id) && return ps[i]
    end
    return first(String(id), min(_ID_PREFIX_MIN, length(id)))
end

const _ERROR_CELL_MAX = 60

function _job_error_disp(j::Job)::String
    e = j.error
    e isa AbstractString || return ""
    firstline = first(split(e, '\n'; limit=2))
    length(firstline) > _ERROR_CELL_MAX && return string(firstline[1:_ERROR_CELL_MAX], "…")
    return firstline
end

function _q_state_color(state::Symbol)
    state === :running && return :cyan
    state === :done && return :green
    state === :failed && return :red
    state === :cancelled && return :yellow
    return :light_black
end

function println_queue_version(io::IO=stdout)
    println(io, "DistSSHQueue $(pkgversion(DistSSHQueue))")
    DistSSHKit.println_kit_version(io)
    return nothing
end

function print_queue_usage(io::IO=stdout)
    DistSSHKit.print_help_chrome("DistSSHQueue"; io=io)
    DistSSHKit.print_help_section("Usage"; io=io)
    DistSSHKit.print_help_lines(io,
        "  julia -m DistSSHQueue [qhost:HOST] <command> [args...]",
        "  julia -m DistSSHQueue --version",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Client"; io=io)
    DistSSHKit.print_help_lines(io,
        "  (julia --project= loads Queue; project is cwd / DISTRIBUTED_PROJECT_ROOT.)",
        "  status [-q]                    List jobs on the queue host",
        "  list-host                      Host tokens from config hosts; ssh -G Host / HostName / User / Port",
        "  size [Kit size argv]           DistSSHKit size on the queue host (does not enqueue)",
        "  watch [-q] [--interval S]      Live status; Ctrl-C leaves serve",
        "  submit go [Kit go argv]        Enqueue DistSSHKit go (parent[:N] / child:NAME[:N])",
        "  submit drive [Kit drive argv]  Enqueue DistSSHKit drive (stderr: queued count)",
        "  cancel <id>                    Drop a :queued row, or stop :running (Kit output dir)",
        "  fetch <id>                     Copy a finished Kit leaf onto this job tree",
        "  teardown -y                    Stop serve and remove queue-host files",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Queue host"; io=io)
    DistSSHKit.print_help_lines(io,
        "  setup [--force]                Write config.toml (--force rewrites)",
        "  add-host TOKEN [TOKEN...]      Add Kit tokens (parent / child:NAME; optional :N max)",
        "  remove-host TOKEN [TOKEN...]   Drop those Kit tokens (no serve restart)",
        "  serve                          Run serve in this terminal",
        "  stop                           Stop serve, keep config / store",
        "  enable [--queue-env DIR]       After reboot, start serve (LaunchAgent / systemd)",
        "  disable                        Remove that OS registration",
        "  teardown -y                    Same as client teardown, locally",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Notes"; io=io)
    DistSSHKit.print_help_lines(io,
        "  Day to day: qhost:HOST from a client (like Kit child:NAME). On the queue host: omit it.",
        "  DISTSSHQUEUE_HOST is the default SSH name when qhost: is omitted (client only).",
        "  status / watch print qhost (client token via DISTSSHQUEUE_QHOST, or local plus hostname).",
        "  The queue host is always-on macOS or Linux. A sleeping laptop is not a queue host.",
        "  WSL2 is a client or worker, not the always-on queue host.",
        "  Do not pass qhost:HOST to setup / serve / enable / disable / add-host / remove-host.",
        "  --hosts / --julia belong to Kit go/drive. Queue-host Julia: --remote-julia / JULIA_DISTRIBUTED_EXE.",
        "  --queue-env DIR is julia --project= on the queue host (default ~/.distsshqueue/env). Not the client's --project=.",
        "  DISTSSHQUEUE_QUEUE_ENV overrides that default. --queue-env @ is the remote default env.",
        "  list-host is not Kit --hosts. On the queue host: list-host. From a client: qhost:HOST list-host.",
        "  size is Kit size (RAM/CPU / --probe). qhost:HOST size. Omit tokens to use config hosts. Not a submit gate.",
        "  add-host / remove-host write that hosts list on the queue host. Same tokens as Kit: parent / child:NAME.",
        "  Optional max :N on the token (child:host1:4). Submit of a larger :N is refused. Bare host1 is not a token.",
        "  Next submit reads the file; do not restart serve. A running Kit job is not stopped.",
        "  Already queued rows still start if a name is later removed.",
        "  ssh -G for list-host runs on the queue host (its SSH config), not on the client.",
        "  list-host does not print private keys or IdentityFile.",
        "  config hosts = [\"parent\", \"child:host1:4\"]. Library submit! uses Queue(; allowed=…).",
        "  teardown -y: serve, OS unit, ~/.distsshqueue (not a git clone).",
        "  teardown also honors DISTSSHKIT_YES (same as DistSSHKit).",
        "  submit starts serve if none is running (DISTSSHQUEUE_NO_AUTOSERVE=1).",
        "  stop: submit will not start serve; only an explicit serve resumes.",
        "  Bare go / drive alias submit go / submit drive. Kit go argv with a .jl",
        "  and no Queue verb is go (`--hosts child:NAME:N SCRIPT.jl`).",
        "  --version / -v print DistSSHQueue then DistSSHKit. submit go -v is Kit only.",
        "  Ctrl-C on serve stops this process. A DistSSHKit job already running is not killed.",
        "  enable --queue-env DIR is julia --project= in the OS unit.",
        "  Project is cwd / DISTRIBUTED_PROJECT_ROOT, not enable --queue-env.",
        "  qhost: submit rsyncs the client job tree to ~/.distsshqueue/stage/<id> (same tree reuses it).",
        "  fetch is the inverse: one finished .distsshkit leaf, same relpath. Not forwarded as a whole.",
        "  One Kit clone per job on the queue host (unique ~/org/Repo.jl); not a Queue job name.",
        "  submit refuses two projects Kit would deploy to the same worker path (no rename, no --delete).",
        "  Job ids are a bare stdout line. submit stderr is `Queued  N` (and running).",
        "  DISTSSHKIT_QUIET hides that stderr. status / watch -q hide chrome (Kit --quiet / DISTSSHKIT_QUIET). --progress / --verbose stay chrome.",
        "  Config: $(_q_short(default_config_path()))   DISTSSHQUEUE_CONFIG",
        "  Store:  $(_q_short(default_store_path()))   DISTSSHQUEUE_STORE / config store=",
        "  Default qhost: DISTSSHQUEUE_HOST (not DISTSSHKIT_HOSTS).",
    )
    return nothing
end

function print_wrote(path::AbstractString; io::IO=stdout)
    DistSSHKit.print_colored(io, "Wrote  ", :green, false)
    println(io, _q_short(path))
    return nothing
end

function print_removed(path::AbstractString; io::IO=stdout)
    DistSSHKit.print_colored(io, "Removed  ", :green, false)
    println(io, _q_short(path))
    return nothing
end

function print_present(path::AbstractString; io::IO=stdout)
    DistSSHKit.print_colored(io, "Present  ", :light_black, false)
    print(io, _q_short(path))
    DistSSHKit.print_colored(io, "  (unchanged; --force to rewrite)", :light_black, false)
    println(io)
    return nothing
end

function print_serve_banner(pid::Integer, store::AbstractString; io::IO=stdout)
    DistSSHKit.print_help_chrome("DistSSHQueue serve"; io=io)
    DistSSHKit.print_help_lines(io, "  pid $pid  store $(_q_short(store))")
    return nothing
end

_serve_can_draw(io::IO)::Bool = io isa Base.TTY && !haskey(ENV, "NO_COLOR")

const _SERVE_CTRLC = "Ctrl-C stops serve. A DistSSHKit job already running is not killed."

function _clip_cols(s::AbstractString, cols::Int)::String
    cols <= 0 && return String(s)
    tw = textwidth(s)
    tw <= cols && return String(s)
    cols <= 1 && return "…"
    buf = IOBuffer()
    used = 0
    for c in s
        w = textwidth(c)
        used + w > cols - 1 && break
        print(buf, c)
        used += w
    end
    print(buf, '…')
    return String(take!(buf))
end

function _serve_live_text(
    frame::Char,
    j::Union{Nothing,Job},
    ids::AbstractVector{<:AbstractString}=String[];
    cols::Int=0,
)::String
    j === nothing && return _clip_cols("  $frame  idle", cols)
    sid = isempty(ids) ? first(j.id, min(_ID_PREFIX_MIN, length(j.id))) : _id_chrome(j.id, ids)
    body = "  $frame  running  $sid  $(j.kind)  $(_job_script_disp(j))"
    return _clip_cols(body, cols)
end

function print_serve_live_line(
    frame::Char,
    j::Union{Nothing,Job},
    ids::AbstractVector{<:AbstractString}=String[];
    io::IO=stdout,
)
    cols = io isa Base.TTY ? displaysize(io)[2] : 0
    s = _serve_live_text(frame, j, ids; cols=cols)
    print(io, '\r', s, "\e[K")
    flush(io)
    return nothing
end

function print_serve_idle_note(; io::IO=stdout)
    DistSSHKit.print_help_lines(io, _SERVE_CTRLC)
    return nothing
end

function print_serve_gone(store::AbstractString; io::IO=stdout)
    DistSSHKit.print_colored(io, "Stopping serve", :yellow, false)
    println(io)
    DistSSHKit.print_help_lines(io,
        "  store  $(_q_short(store)) (pidfile gone; removed or taken over)",
        "  A DistSSHKit job already running is not killed.",
    )
    return nothing
end

function print_serve_already(pid::Integer, store::AbstractString; io::IO=stdout)
    DistSSHKit.print_help_chrome("DistSSHQueue serve"; io=io)
    DistSSHKit.print_colored(io, "Already running", :cyan, false)
    println(io)
    DistSSHKit.print_help_lines(io,
        "  pid    $pid",
        "  store  $(_q_short(store))",
        "  Use status or watch. stop, then serve, to restart.",
    )
    return nothing
end

function print_serve_started(log::AbstractString; io::IO=stderr)
    DistSSHKit.print_colored(io, "Started serve", :cyan, false)
    println(io)
    DistSSHKit.print_help_lines(io, "  log  $(_q_short(log))")
    return nothing
end

function print_serve_stopped(store::AbstractString, was_running::Bool; io::IO=stdout)
    DistSSHKit.print_colored(io, "Stopped serve", :yellow, false)
    println(io)
    DistSSHKit.print_help_lines(io,
        "  store  $(_q_short(store))",
        was_running ? "  serve was running; sent SIGTERM" : "  no serve was running",
        "  submit will not auto-start; run serve to resume.",
    )
    return nothing
end

function _serve_disp(store::AbstractString)::String
    serve_alive(store) && return "running"
    serve_stopped(store) && return "stopped"
    return "none"
end

function _qhost_disp(qhost::Union{Nothing,AbstractString})::String
    hn = gethostname()
    if qhost === nothing || isempty(String(qhost))
        return "local ($hn)"
    end
    v = String(qhost)
    return v == hn ? v : "$v ($hn)"
end

function print_jobs_table(rows::Vector{Job}; io::IO=stdout)
    DistSSHKit.print_help_section("Jobs"; io=io)
    if isempty(rows)
        DistSSHKit.print_colored(io, "  (empty)", :light_black, false)
        println(io)
        return nothing
    end
    ids = _unique_prefixes(String[j.id for j in rows])
    states = String[String(j.state) for j in rows]
    kinds = String[String(j.kind) for j in rows]
    hosts = String[join(j.hosts, ',') for j in rows]
    scripts = String[_job_script_disp(j) for j in rows]
    w_id = max(2, maximum(length, ids; init=2))
    w_st = max(5, maximum(length, states; init=5))
    w_k = max(4, maximum(length, kinds; init=4))
    w_h = max(5, maximum(length, hosts; init=5))
    w_sc = max(6, maximum(length, scripts; init=6))
    headers = String["ID", "STATE", "KIND", "HOSTS", "SCRIPT"]
    widths = Int[w_id, w_st, w_k, w_h, w_sc]

    # Optional trailing columns: shown only when at least one row has a value.
    optional = Tuple{String,Vector{String},Int}[]
    show_proj = any(j -> get(j.kwargs, "project", nothing) !== nothing, rows)
    if show_proj
        projs = String[_job_project_disp(j) for j in rows]
        push!(optional, ("PROJECT", projs, max(7, maximum(length, projs; init=7))))
    end
    show_res = any(j -> j.result_path !== nothing, rows)
    if show_res
        ress = String[_job_result_disp(j) for j in rows]
        push!(optional, ("RESULT", ress, max(6, maximum(length, ress; init=6))))
    end
    show_err = any(j -> j.error !== nothing, rows)
    if show_err
        errs = String[_job_error_disp(j) for j in rows]
        push!(optional, ("ERROR", errs, max(5, maximum(length, errs; init=5))))
    end
    for (h, _, w) in optional
        push!(headers, h)
        push!(widths, w)
    end

    head = join((_q_cell(headers[i], widths[i]) for i in eachindex(headers)), "  ")
    DistSSHKit.print_colored(io, "  " * head, :light_black, false)
    println(io)
    for (i, j) in enumerate(rows)
        print(io, "  ", _q_cell(ids[i], w_id), "  ")
        DistSSHKit.print_colored(io, _q_cell(states[i], w_st), _q_state_color(j.state), false)
        print(io, "  ", _q_cell(kinds[i], w_k), "  ", _q_cell(hosts[i], w_h), "  ", _q_cell(scripts[i], w_sc))
        for (_, vals, w) in optional
            print(io, "  ", _q_cell(vals[i], w))
        end
        println(io)
    end
    return nothing
end

function print_status_table(
    store::AbstractString,
    rows::Vector{Job};
    io::IO=stdout,
    qhost::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
)
    if !quiet
        DistSSHKit.print_help_section("Store"; io=io)
        DistSSHKit.print_help_lines(io,
            "  path   $(_q_short(store))",
            "  qhost  $(_qhost_disp(qhost))",
        )
        DistSSHKit.print_help_blank(io)
    end
    return print_jobs_table(rows; io=io)
end

function print_watch_frame(
    store::AbstractString,
    rows::Vector{Job};
    io::IO=stdout,
    qhost::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
)
    if !quiet
        DistSSHKit.print_help_chrome("DistSSHQueue watch"; io=io)
        DistSSHKit.print_help_section("Process"; io=io)
        DistSSHKit.print_help_lines(io,
            "  store   $(_q_short(store))",
            "  serve   $(_serve_disp(store))",
            "  qhost   $(_qhost_disp(qhost))",
        )
        DistSSHKit.print_help_blank(io)
    end
    print_jobs_table(rows; io=io)
    if !quiet
        DistSSHKit.print_help_blank(io)
        DistSSHKit.print_help_lines(io, "Ctrl-C stops watch; serve stays.")
    end
    return nothing
end
