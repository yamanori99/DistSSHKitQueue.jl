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
        "  julia -m DistSSHKitQueue [--qhost HOST] <command> [args...]",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Client"; io=io)
    DistSSHKit.print_help_lines(io,
        "  (--project=. is the job tree; no files written on the laptop.)",
        "  status                         List jobs on the queue host",
        "  submit go [Kit go argv]        Enqueue DistSSHKit go",
        "  submit drive [Kit drive argv]  Enqueue DistSSHKit drive",
        "  cancel <id>                    Drop a :queued row",
        "  teardown -y                    Stop waiter and remove queue-host files",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Queue host"; io=io)
    DistSSHKit.print_help_lines(io,
        "  setup [--service]              Write dskq + config.toml",
        "  serve                          Run the FIFO waiter",
        "  service install|uninstall      LaunchAgent / systemd user unit",
        "  teardown -y                    Same as client teardown, locally",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Notes"; io=io)
    DistSSHKit.print_help_lines(io,
        "  Same machine: omit --qhost. Several clusters: pass --qhost every time.",
        "  Do not pass --qhost to setup / serve / service.",
        "  Remote Julia: Kit auto-detect; --remote-julia / JULIA_DISTRIBUTED_EXE override.",
        "  teardown -y: waiter, dskq, OS unit, ~/.distsshkitqueue (not a git clone).",
        "  submit starts a waiter if none is running (DISTSSHKITQUEUE_NO_AUTOSERVE=1).",
        "  Bare go / drive alias submit go / submit drive.",
        "  Ctrl-C leaves the waiter; a running Kit job is not killed.",
        "  Config: $(_q_short(default_config_path()))   DISTSSHKITQUEUE_CONFIG",
        "  Store:  $(_q_short(default_store_path()))   DISTSSHKITQUEUE_STORE / config store=",
    )
    return nothing
end

function print_wrote(path::AbstractString; io::IO=stdout)
    DistSSHKit._print_colored(io, "Wrote  ", :green, false)
    println(io, _q_short(path))
    return nothing
end

function print_removed(path::AbstractString; io::IO=stdout)
    DistSSHKit._print_colored(io, "Removed  ", :green, false)
    println(io, _q_short(path))
    return nothing
end

function print_path_hint(bindir::AbstractString; io::IO=stderr)
    DistSSHKit._print_colored(io, "Hint: ", :yellow, true)
    println(io, _q_short(bindir), " is not on PATH; use the absolute path or add it")
    return nothing
end

function print_serve_banner(pid::Integer, store::AbstractString; io::IO=stdout)
    DistSSHKit.print_help_chrome("DistSSHKitQueue serve"; io=io)
    DistSSHKit.print_help_section("Process"; io=io)
    DistSSHKit.print_help_lines(io,
        "  pid    $pid",
        "  store  $(_q_short(store))",
    )
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_lines(io,
        "Ctrl-C leaves the waiter; a running Kit job is not killed.",
    )
    return nothing
end

function print_waiter_started(log::AbstractString; io::IO=stderr)
    DistSSHKit._print_colored(io, "Started waiter", :cyan, false)
    println(io)
    DistSSHKit.print_help_lines(io, "  log  $(_q_short(log))")
    return nothing
end

function print_status_table(store::AbstractString, rows::Vector{Job}; io::IO=stdout)
    DistSSHKit.print_help_section("Store"; io=io)
    DistSSHKit.print_help_lines(io, "  $(_q_short(store))")
    DistSSHKit.print_help_blank(io)
    DistSSHKit.print_help_section("Jobs"; io=io)
    if isempty(rows)
        DistSSHKit._print_colored(io, "  (empty)", :light_black, false)
        println(io)
        return nothing
    end
    show_proj = any(j -> get(j.kwargs, "project", nothing) !== nothing, rows)
    show_res = any(j -> j.result_path !== nothing, rows)
    ids = String[j.id for j in rows]
    states = String[String(j.state) for j in rows]
    kinds = String[String(j.kind) for j in rows]
    hosts = String[join(j.hosts, ',') for j in rows]
    scripts = String[_q_short(j.script) for j in rows]
    projs = String[show_proj ? _job_project_disp(j) : "" for j in rows]
    ress = String[show_res ? _job_result_disp(j) : "" for j in rows]
    w_id = max(2, maximum(length, ids; init=2))
    w_st = max(5, maximum(length, states; init=5))
    w_k = max(4, maximum(length, kinds; init=4))
    w_h = max(5, maximum(length, hosts; init=5))
    w_sc = max(6, maximum(length, scripts; init=6))
    headers = String["ID", "STATE", "KIND", "HOSTS", "SCRIPT"]
    widths = Int[w_id, w_st, w_k, w_h, w_sc]
    if show_proj
        w_p = max(7, maximum(length, projs; init=7))
        push!(headers, "PROJECT")
        push!(widths, w_p)
    end
    if show_res
        w_r = max(6, maximum(length, ress; init=6))
        push!(headers, "RESULT")
        push!(widths, w_r)
    end
    head = join((_q_cell(headers[i], widths[i]) for i in eachindex(headers)), "  ")
    DistSSHKit._print_colored(io, "  " * head, :light_black, false)
    println(io)
    for (i, j) in enumerate(rows)
        cells = String[
            _q_cell(ids[i], w_id),
            _q_cell(states[i], w_st),
            _q_cell(kinds[i], w_k),
            _q_cell(hosts[i], w_h),
            _q_cell(scripts[i], w_sc),
        ]
        print(io, "  ", cells[1], "  ")
        DistSSHKit._print_colored(io, cells[2], _q_state_color(j.state), false)
        print(io, "  ", cells[3], "  ", cells[4], "  ", cells[5])
        show_proj && print(io, "  ", _q_cell(projs[i], widths[6]))
        if show_res
            idx = show_proj ? 7 : 6
            print(io, "  ", _q_cell(ress[i], widths[idx]))
        end
        println(io)
    end
    return nothing
end
