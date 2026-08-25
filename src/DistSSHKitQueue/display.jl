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

function _job_project_disp(j::Job)::String
    p = get(j.kwargs, "project", nothing)
    p isa AbstractString || return ""
    return _q_short(p)
end

function _job_result_disp(j::Job)::String
    r = j.result_path
    r isa AbstractString || return ""
    return _q_short(r)
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

function print_queue_usage(io::IO=stdout)
    DistSSHKit.print_help_chrome("DistSSHKitQueue"; io=io)
    DistSSHKit.print_help_section("Usage"; io=io)
    DistSSHKit.print_help_lines(io,
        "  julia -m DistSSHKitQueue [qhost:HOST] <command> [args...]",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Client"; io=io)
    DistSSHKit.print_help_lines(io,
        "  (--project=. is the job tree; no files written on the laptop.)",
        "  status                         List jobs on the queue host",
        "  list-host                      Host tokens from config hosts; ssh -G Host / HostName / User / Port",
        "  watch [--interval S]           Live status; Ctrl-C leaves the waiter",
        "  submit go [Kit go argv]        Enqueue DistSSHKit go (parent[:N] / child:NAME[:N])",
        "  submit drive [Kit drive argv]  Enqueue DistSSHKit drive",
        "  cancel <id>                    Drop a :queued row, or stop :running",
        "  teardown -y                    Stop waiter and remove queue-host files",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Queue host"; io=io)
    DistSSHKit.print_help_lines(io,
        "  setup [--force]                Write config.toml (--force rewrites)",
        "  add-host NAME [NAME...]        Add Kit names to config hosts (first add creates the list)",
        "  remove-host NAME [NAME...]     Drop Kit names from that list",
        "  serve                          Run the waiter in this terminal",
        "  stop                           Stop that waiter, keep config / store",
        "  enable                         After reboot, start serve (LaunchAgent / systemd)",
        "  disable                        Remove that OS registration",
        "  teardown -y                    Same as client teardown, locally",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Notes"; io=io)
    DistSSHKit.print_help_lines(io,
        "  Day to day: qhost:HOST from a client (like Kit child:NAME). On the queue host: omit it.",
        "  status / watch print qhost (that token, or local plus hostname).",
        "  A sleeping laptop is not a queue host.",
        "  Do not pass qhost:HOST to setup / serve / enable / disable / add-host / remove-host.",
        "  --hosts / --julia belong to Kit go/drive. Queue-host Julia: --remote-julia / JULIA_DISTRIBUTED_EXE.",
        "  list-host is not Kit --hosts. On the queue host: list-host. From a client: qhost:HOST list-host.",
        "  add-host / remove-host write that hosts list on the queue host. Names: parent or host1 / child:host1.",
        "  ssh -G for list-host runs on the queue host (its SSH config), not on the client.",
        "  list-host does not print private keys or IdentityFile.",
        "  config hosts = [\"parent\", \"host1\"] (or child:host1). Library submit! uses Queue(; allowed=…).",
        "  teardown -y: waiter, OS unit, ~/.distsshkitqueue (not a git clone).",
        "  submit starts a waiter if none is running (DISTSSHKITQUEUE_NO_AUTOSERVE=1).",
        "  stop latches it off; only an explicit serve resumes (submit will not).",
        "  Bare go / drive alias submit go / submit drive.",
        "  Ctrl-C on serve stops the waiter. A DistSSHKit job already running is not killed.",
        "  Ctrl-C on watch stops the live view only.",
        "  Config: $(_q_short(default_config_path()))   DISTSSHKITQUEUE_CONFIG",
        "  Store:  $(_q_short(default_store_path()))   DISTSSHKITQUEUE_STORE / config store=",
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
    DistSSHKit.print_help_chrome("DistSSHKitQueue serve"; io=io)
    DistSSHKit.print_help_lines(io, "  pid $pid  store $(_q_short(store))")
    return nothing
end

_serve_can_draw(io::IO)::Bool = io isa Base.TTY && !haskey(ENV, "NO_COLOR")

const _SERVE_CTRLC = "Ctrl-C stops the waiter. A DistSSHKit job already running is not killed."

function _serve_live_text(frame::Char, j::Union{Nothing,Job})::String
    j === nothing && return "  $frame  idle"
    return "  $frame  running  $(j.id)  $(j.kind)  $(_q_short(j.script))"
end

function print_serve_live_line(frame::Char, j::Union{Nothing,Job}; io::IO=stdout)
    print(io, '\r', "  ")
    DistSSHKit.print_colored(io, string(frame), :light_black, false)
    print(io, "  ")
    if j === nothing
        DistSSHKit.print_colored(io, "idle", :light_black, false)
    else
        DistSSHKit.print_colored(io, "running", :cyan, false)
        print(io, "  ", j.id, "  ", j.kind, "  ", _q_short(j.script))
    end
    print(io, "\e[K")
    flush(io)
    return nothing
end

function print_serve_idle_note(; io::IO=stdout)
    DistSSHKit.print_help_lines(io, _SERVE_CTRLC)
    return nothing
end

function print_waiter_gone(store::AbstractString; io::IO=stdout)
    DistSSHKit.print_colored(io, "Waiter stopping", :yellow, false)
    println(io)
    DistSSHKit.print_help_lines(io,
        "  store  $(_q_short(store)) (pidfile gone; removed or taken over)",
        "  A DistSSHKit job already running is not killed.",
    )
    return nothing
end

function print_serve_already(pid::Integer, store::AbstractString; io::IO=stdout)
    DistSSHKit.print_help_chrome("DistSSHKitQueue serve"; io=io)
    DistSSHKit.print_colored(io, "Already running", :cyan, false)
    println(io)
    DistSSHKit.print_help_lines(io,
        "  pid    $pid",
        "  store  $(_q_short(store))",
        "  Use status or watch. stop, then serve, to restart.",
    )
    return nothing
end

function print_waiter_started(log::AbstractString; io::IO=stderr)
    DistSSHKit.print_colored(io, "Started waiter", :cyan, false)
    println(io)
    DistSSHKit.print_help_lines(io, "  log  $(_q_short(log))")
    return nothing
end

function print_waiter_stopped(store::AbstractString, was_running::Bool; io::IO=stdout)
    DistSSHKit.print_colored(io, "Stopped waiter", :yellow, false)
    println(io)
    DistSSHKit.print_help_lines(io,
        "  store  $(_q_short(store))",
        was_running ? "  waiter was running; sent SIGTERM" : "  no waiter was running",
        "  submit will not auto-start; run serve to resume.",
    )
    return nothing
end

function _waiter_disp(store::AbstractString)::String
    waiter_alive(store) && return "running"
    waiter_stopped(store) && return "stopped"
    return "none"
end

function _qhost_disp(via::Union{Nothing,AbstractString})::String
    hn = gethostname()
    if via === nothing || isempty(String(via))
        return "local ($hn)"
    end
    v = String(via)
    return v == hn ? v : "$v ($hn)"
end

function print_jobs_table(rows::Vector{Job}; io::IO=stdout)
    DistSSHKit.print_help_section("Jobs"; io=io)
    if isempty(rows)
        DistSSHKit.print_colored(io, "  (empty)", :light_black, false)
        println(io)
        return nothing
    end
    ids = String[j.id for j in rows]
    states = String[String(j.state) for j in rows]
    kinds = String[String(j.kind) for j in rows]
    hosts = String[join(j.hosts, ',') for j in rows]
    scripts = String[_q_short(j.script) for j in rows]
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
    via::Union{Nothing,AbstractString}=nothing,
)
    DistSSHKit.print_help_section("Store"; io=io)
    DistSSHKit.print_help_lines(io,
        "  path   $(_q_short(store))",
        "  qhost  $(_qhost_disp(via))",
    )
    DistSSHKit.print_help_blank(io)
    return print_jobs_table(rows; io=io)
end

function print_watch_frame(
    store::AbstractString,
    rows::Vector{Job};
    io::IO=stdout,
    via::Union{Nothing,AbstractString}=nothing,
)
    DistSSHKit.print_help_chrome("DistSSHKitQueue watch"; io=io)
    DistSSHKit.print_help_section("Process"; io=io)
    DistSSHKit.print_help_lines(io,
        "  store   $(_q_short(store))",
        "  waiter  $(_waiter_disp(store))",
        "  qhost   $(_qhost_disp(via))",
    )
    DistSSHKit.print_help_blank(io)
    print_jobs_table(rows; io=io)
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_lines(io, "Ctrl-C stops watch; the waiter stays.")
    return nothing
end
