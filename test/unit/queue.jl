using Test
using DistSSHKit
using DistSSHKitQueue

function _wait_state(q, id, st; tries=200)
    for _ in 1:tries
        job(q, id).state === st && return nothing
        sleep(0.01)
    end
    error("job $id stayed $(job(q, id).state), expected $st")
end

@testset "true FIFO one at a time" begin
    started = String[]
    q = Queue(; runner=j -> (push!(started, j.id); sleep(0.05)))
    a = submit!(q, "a.jl", "child:worker:4")
    b = submit!(q, "b.jl", "child:worker:1")
    @test step!(q) == 1
    @test job(q, a).state === :running
    @test job(q, b).state === :queued
    @test step!(q) == 0
    _wait_state(q, a, :done)
    @test step!(q) == 1
    _wait_state(q, b, :done)
    @test started == [a, b]
end

@testset "cancel queued; running needs output_dir" begin
    q = Queue(; runner=_ -> sleep(0.05))
    a = submit!(q, "a.jl", "parent:2")
    b = submit!(q, "b.jl", "parent:2")
    @test cancel!(q, b)
    @test job(q, b).state === :cancelled
    @test step!(q) == 1
    @test !cancel!(q, a)
    _wait_state(q, a, :done)
end

@testset "cancel running via terminate_run! when output_dir is known" begin
    mktempdir() do d
        out = joinpath(d, "kit-out")
        mkpath(out)
        ev = Base.Event()
        q = Queue(; runner=_ -> wait(ev))
        id = submit!(q, "a.jl", "parent:1"; output_dir=out)
        @test step!(q) == 1
        @test job(q, id).state === :running
        @test cancel!(q, id)
        @test job(q, id).state === :cancelled
        notify(ev)
        sleep(0.05)
        @test job(q, id).state === :cancelled
    end
end

@testset "cancel running overwrites a concurrent :failed finish" begin
    mktempdir() do d
        out = joinpath(d, "kit-out")
        mkpath(out)
        q = Queue(; runner=_ -> wait(Base.Event()))
        id = submit!(q, "a.jl", "parent:1"; output_dir=out)
        @test step!(q) == 1
        DistSSHKitQueue._finish!(q, id, :failed, "terminated"; result_path=out)
        DistSSHKitQueue._finish!(q, id, :cancelled, nothing; result_path=out)
        @test job(q, id).state === :cancelled
    end
end

@testset "cancel running overwrites a concurrent :done finish" begin
    mktempdir() do d
        out = joinpath(d, "kit-out")
        mkpath(out)
        q = Queue(; runner=_ -> wait(Base.Event()))
        id = submit!(q, "a.jl", "parent:1"; output_dir=out)
        @test step!(q) == 1
        DistSSHKitQueue._finish!(q, id, :done, nothing; result_path=out)
        DistSSHKitQueue._finish!(q, id, :cancelled, nothing; result_path=out)
        @test job(q, id).state === :cancelled
    end
end

@testset "kit throw does not stall" begin
    q = Queue(; runner=j -> basename(j.script) == "bad.jl" ? error("boom") : nothing)
    a = submit!(q, "bad.jl", "parent:1")
    b = submit!(q, "ok.jl", "parent:1")
    @test step!(q) == 1
    _wait_state(q, a, :failed)
    @test occursin("boom", something(job(q, a).error, ""))
    @test step!(q) == 1
    _wait_state(q, b, :done)
end

@testset "kind=:drive" begin
    q = Queue(; runner=_ -> nothing)
    id = submit!(q, "d.jl", "parent:1"; kind=:drive)
    j = job(q, id)
    @test j.kind === :drive
    @test haskey(j.kwargs, "project")
    @test !haskey(j.kwargs, "path_anchor")
    gid = submit!(q, "g.jl", "parent:1")
    g = job(q, gid)
    @test g.kind === :go
    @test !haskey(g.kwargs, "path_anchor")
end

@testset "kit.pid keeps a live detached child across load" begin
    mktempdir() do d
        out = joinpath(d, "kit-out")
        mkpath(out)
        write(joinpath(out, "kit.pid"), string(getpid()))
        p = joinpath(d, "jobs.toml")
        j = DistSSHKitQueue.Job(;
            kind=:go,
            script="/tmp/job.jl",
            hosts=["parent:1"],
            state=:running,
            result_path=out,
        )
        DistSSHKitQueue.save_jobs(p, [j])
        q = Queue(; store=p, runner=_ -> error("must not re-run"))
        load!(q)
        loaded = job(q, j.id)
        @test loaded.state === :running
        @test DistSSHKitQueue.kit_child_alive(loaded)
        DistSSHKitQueue.adopt_running!(q)
        @test q.live_id == j.id
        sleep(0.05)
        @test job(q, j.id).state === :running
    end
end

@testset "two-line kit.pid is live" begin
    mktempdir() do d
        out = joinpath(d, "kit-out")
        mkpath(out)
        st = DistSSHKit.kit_process_start_key(getpid())
        body = st === nothing ? string(getpid(), '\n') : string(getpid(), '\n', st, '\n')
        write(joinpath(out, "kit.pid"), body)
        j = DistSSHKitQueue.Job(;
            kind=:go,
            script="/tmp/job.jl",
            hosts=["parent:1"],
            state=:running,
            result_path=out,
        )
        @test DistSSHKitQueue.kit_child_alive(j)
        @test DistSSHKit.kit_pid_file_running(out)
    end
end

@testset "kit.result settles a finished running row on load" begin
    mktempdir() do d
        out = joinpath(d, "kit-out")
        mkpath(out)
        DistSSHKit._write_kit_result_file(DistSSHKit.KitRunResult(
            true, :go, out, nothing, nothing, 0,
        ))
        p = joinpath(d, "jobs.toml")
        j = DistSSHKitQueue.Job(;
            kind=:go,
            script="/tmp/job.jl",
            hosts=["parent:1"],
            state=:running,
            result_path=out,
        )
        DistSSHKitQueue.save_jobs(p, [j])
        q = Queue(; store=p, runner=_ -> error("must not re-run"))
        load!(q)
        loaded = job(q, j.id)
        @test loaded.state === :done
        @test loaded.error === nothing
    end
end

@testset "TOML store restart" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        q = Queue(; store=p, runner=_ -> wait(ev))
        id = submit!(q, "a.jl", "parent:1")
        @test step!(q) == 1
        @test job(q, id).state === :running
        q2 = Queue(; store=p, runner=_ -> nothing)
        load!(q2)
        notify(ev)
        _wait_state(q, id, :done)
        @test job(q2, id).state === :failed
        @test occursin("serve restarted", something(job(q2, id).error, ""))
    end
end

@testset "kit ok=false is failed" begin
    @test_throws ErrorException DistSSHKitQueue.require_kit_ok((ok=false, kind=:go))
    detailed = try
        DistSSHKitQueue.require_kit_ok((ok=false, kind=:drive, failed_step="drive", exit_code=42))
    catch e
        e
    end
    @test detailed isa ErrorException
    @test occursin("drive", detailed.msg)
    @test occursin("exit 42", detailed.msg)
    @test DistSSHKitQueue.require_kit_ok((ok=true, kind=:go, output_dir="/tmp/out")) === nothing
    @test DistSSHKitQueue.kit_result_path((ok=true, output_dir="/tmp/out")) == "/tmp/out"
    q = Queue(; runner=_ -> error("DistSSHKit go failed (ok=false)"))
    id = submit!(q, "a.jl", "parent:1")
    @test step!(q) == 1
    _wait_state(q, id, :failed)
end

@testset "execute_kwargs drops names execute! detached rejects" begin
    q = Queue(; runner=_ -> nothing)
    gid = submit!(q, "g.jl", "parent:1"; path_anchor="/x", yes=false, log_dir="/logs", quiet=true)
    gkw = DistSSHKitQueue.execute_kwargs(job(q, gid))
    @test gkw.yes === true
    @test gkw.quiet === true
    @test !haskey(gkw, :path_anchor)
    @test !haskey(gkw, :job_id)
    @test !haskey(gkw, :log_dir)
    did = submit!(q, "d.jl", "parent:1"; kind=:drive, log_dir="/logs", skip_hash_check=false)
    dkw = DistSSHKitQueue.execute_kwargs(job(q, did))
    @test dkw.log_dir == "/logs"
    @test dkw.skip_hash_check === false
    @test dkw.yes === true
    wid = submit!(q, "w.jl", "h1"; kind=:drive, workers=4, mem_headroom=0.5)
    wkw = DistSSHKitQueue.execute_kwargs(job(q, wid))
    @test wkw.workers == 4
    @test wkw.mem_headroom == 0.5
    @test !haskey(DistSSHKitQueue.execute_kwargs(job(q, gid)), :workers)
end

@testset "result_path from runner and kwargs" begin
    q = Queue(; runner=_ -> "/tmp/kit-out")
    id = submit!(q, "a.jl", "parent:1"; output_dir="/tmp/unused")
    @test step!(q) == 1
    _wait_state(q, id, :done)
    @test job(q, id).result_path == "/tmp/kit-out"

    q2 = Queue(; runner=_ -> nothing)
    id2 = submit!(q2, "b.jl", "parent:1"; output_dir="/tmp/bag")
    @test step!(q2) == 1
    _wait_state(q2, id2, :done)
    @test job(q2, id2).result_path == "/tmp/bag"
end

@testset "client cancel reloads store" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        q = Queue(; store=p, runner=_ -> sleep(0.05))
        a = submit!(q, "a.jl", "parent:1")
        b = submit!(q, "b.jl", "parent:1")
        @test step!(q) == 1
        other = Queue(; store=p)
        @test cancel!(other, b)
        @test !cancel!(other, a)
        @test job(other, b).state === :cancelled
        _wait_state(q, a, :done)
        @test step!(q) == 0
    end
end

@testset "client enqueue keeps running row" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        ev = Base.Event()
        q = Queue(; store=p, runner=_ -> wait(ev))
        a = submit!(q, "a.jl", "parent:1")
        @test step!(q) == 1
        q2 = Queue(; store=p, runner=_ -> nothing)
        b = submit!(q2, "b.jl", "worker:2")
        rows = DistSSHKitQueue.read_jobs(p)
        @test job(q, a).state === :running
        @test any(j -> j.id == b && j.state === :queued, rows)
        @test any(j -> j.id == a && j.state === :running, rows)
        notify(ev)
        _wait_state(q, a, :done)
    end
end

@testset "CLI help and Kit go enqueue" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        jobdir = mktempdir()
        write(joinpath(jobdir, "Project.toml"), "[deps]\n")
        write(joinpath(jobdir, "job.jl"), "1\n")
        write(joinpath(jobdir, "alias.jl"), "1\n")
        write(joinpath(jobdir, "drv.jl"), "1\n")
        withenv(
            "DISTSSHKITQUEUE_STORE" => p,
            "DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml"),
            "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => nothing,
        ) do
            cd(jobdir) do
                proj = DistSSHKit.canonical_local_path(pwd())
                help = sprint(DistSSHKitQueue.print_queue_usage)
                @test occursin("Usage", help)
                @test occursin("--qhost HOST", help)
                @test occursin("watch", help)
                @test occursin("enable", help)
                @test occursin("disable", help)
                @test occursin("sleeping laptop", help)
                @test !occursin("service install", help)
                code_h, out_h, _ = capture_stdio() do
                    DistSSHKitQueue.main(["-h"])
                end
                @test code_h == 0
                @test occursin("Usage", out_h)
                code_st, out_st, _ = capture_stdio() do
                    DistSSHKitQueue.main(["status"])
                end
                @test code_st == 0
                @test occursin("Store", out_st)
                @test occursin("qhost", out_st)
                @test occursin("local ($(gethostname()))", out_st)
                @test occursin("(empty)", out_st)
                empty = sprint(io -> DistSSHKitQueue.show_status(p; io=io))
                @test occursin("Store", empty)
                @test occursin("(empty)", empty)
                via_out = sprint(io -> DistSSHKitQueue.show_status(p; io=io, via="cluster-a"))
                @test occursin("cluster-a ($(gethostname()))", via_out)
                @test DistSSHKitQueue._qhost_disp(gethostname()) == gethostname()
                code_go, out_go, _ = capture_stdio() do
                    DistSSHKitQueue.main(["submit", "go", "child:worker:4", "job.jl"])
                end
                @test code_go == 0
                rows = DistSSHKitQueue.read_jobs(p)
                @test length(rows) == 1
                @test strip(out_go) == rows[1].id
                @test rows[1].kind === :go
                @test rows[1].script == DistSSHKit.canonical_local_path(joinpath(pwd(), "job.jl"))
                @test rows[1].hosts == ["child:worker:4"]
                @test rows[1].state === :queued
                @test rows[1].kwargs["project"] == proj
                listed = sprint(io -> DistSSHKitQueue.show_status(p; io=io))
                @test occursin(rows[1].id, listed)
                @test occursin("queued", listed)
                @test occursin("STATE", listed)
                code_alias, _, _ = capture_stdio() do
                    DistSSHKitQueue.main(["go", "parent:1", "alias.jl"])
                end
                @test code_alias == 0
                code_drv, _, _ = capture_stdio() do
                    DistSSHKitQueue.main(["submit", "drive", "parent:2", "drv.jl"])
                end
                @test code_drv == 0
                rows = DistSSHKitQueue.read_jobs(p)
                @test length(rows) == 3
                @test rows[2].kind === :go
                @test rows[2].script == DistSSHKit.canonical_local_path(joinpath(pwd(), "alias.jl"))
                @test rows[3].kind === :drive
                @test rows[3].script == DistSSHKit.canonical_local_path(joinpath(pwd(), "drv.jl"))
                @test rows[3].hosts == ["parent:2"]
                @test rows[3].kwargs["project"] == proj
                code_w, _, _ = capture_stdio() do
                    DistSSHKitQueue.main(["submit", "drive", "--workers", "4", "child:host1", "drv.jl"])
                end
                @test code_w == 0
                rows = DistSSHKitQueue.read_jobs(p)
                @test rows[end].hosts == ["child:host1"]
                @test rows[end].kwargs["workers"] == 4
                cid = rows[2].id
                code_c, out_c, _ = capture_stdio() do
                    DistSSHKitQueue.main(["cancel", cid])
                end
                @test code_c == 0
                @test strip(out_c) == cid
                cancelled = DistSSHKitQueue.read_jobs(p)
                @test any(j -> j.id == cid && j.state === :cancelled, cancelled)
            end
        end
    end
end

@testset "watch reprints status then exits on --ticks" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        jobdir = joinpath(d, "jobtree")
        mkpath(jobdir)
        write(joinpath(jobdir, "a.jl"), "1\n")
        withenv(
            "DISTSSHKITQUEUE_STORE" => p,
            "DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml"),
            "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => nothing,
        ) do
            cd(jobdir) do
                code, out, _ = capture_stdio() do
                    DistSSHKitQueue.main(["watch", "--ticks", "1", "--interval", "0.01"])
                end
                @test code == 0
                @test occursin("DistSSHKitQueue watch", out)
                @test occursin("waiter", out)
                @test occursin("qhost", out)
                @test occursin("local ($(gethostname()))", out)
                @test occursin("(empty)", out)
                @test occursin("Ctrl-C stops watch", out)
                code_go, _, _ = capture_stdio() do
                    DistSSHKitQueue.main(["submit", "go", "parent:1", "a.jl"])
                end
                @test code_go == 0
                code2, out2, _ = capture_stdio() do
                    DistSSHKitQueue.main(["watch", "--ticks", "2", "--interval", "0.01"])
                end
                @test code2 == 0
                @test occursin("queued", out2)
                errc, _, err = capture_stdio() do
                    DistSSHKitQueue.main(["watch", "--bogus"])
                end
                @test errc == 1
                @test occursin("unknown watch option", err)
            end
        end
    end
end

@testset "cli surfaces friendly errors instead of stacktraces" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        jobdir = joinpath(d, "jobtree")
        mkpath(jobdir)
        withenv(
            "DISTSSHKITQUEUE_STORE" => p,
            "DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml"),
            "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => nothing,
        ) do
            cd(jobdir) do
                code, _, err = capture_stdio() do
                    DistSSHKitQueue.main(["submit", "go", "parent:1", "no_such.jl"])
                end
                @test code == 1
                @test occursin("not found", err)
                @test isempty(DistSSHKitQueue.read_jobs(p))

                code2, _, err2 = capture_stdio() do
                    DistSSHKitQueue.main(["cancel"])
                end
                @test code2 == 1
                @test occursin("Error:", err2)
                @test occursin("need a job id", err2)
                @test !occursin("Stacktrace", err2)

                code3, _, err3 = capture_stdio() do
                    DistSSHKitQueue.main(["cancel", "no-such-id"])
                end
                @test code3 == 1
                @test occursin("cannot be cancelled", err3)

                code4, _, err4 = capture_stdio() do
                    DistSSHKitQueue.main(["--qhost", "h", "serve"])
                end
                @test code4 == 1
                @test occursin("Error:", err4)
            end
        end
    end
end

@testset "status table shows the ERROR column for failed jobs" begin
    mktempdir() do d
        p = joinpath(d, "jobs.toml")
        q = Queue(; store=p, runner=_ -> error("boom: kaboom"))
        id = submit!(q, "a.jl", "parent:1")
        @test step!(q) == 1
        _wait_state(q, id, :failed)
        listed = sprint(io -> DistSSHKitQueue.show_status(p; io=io))
        @test occursin("ERROR", listed)
        @test occursin("boom: kaboom", listed)
    end
end

@testset "serve live line" begin
    @test DistSSHKitQueue._serve_live_text('⠋', nothing) == "  ⠋  idle"
    j = DistSSHKitQueue.Job(; kind=:go, script="/tmp/job.jl", hosts=["parent:1"], state=:running)
    t = DistSSHKitQueue._serve_live_text('⠙', j)
    @test startswith(t, "  ⠙  running  $(j.id)  go")
    @test occursin("job.jl", t)
    buf = IOBuffer()
    DistSSHKitQueue.print_serve_banner(1, "/tmp/jobs.toml"; io=buf)
    s = String(take!(buf))
    @test occursin("pid 1", s)
    @test occursin("store", s)
    @test !occursin("Process", s)
    buf2 = IOBuffer()
    DistSSHKitQueue.print_serve_idle_note(; io=buf2)
    note = String(take!(buf2))
    @test occursin("Ctrl-C stops the waiter", note)
    @test occursin("DistSSHKit job already running is not killed", note)
end

@testset "service unit text is serve" begin
    plist = DistSSHKitQueue.launch_agent_plist("/opt/bin/julia", "/opt/Queue.jl")
    @test occursin("org.distsshkitqueue.serve", plist)
    @test occursin("/opt/bin/julia", plist)
    @test occursin("--project=/opt/Queue.jl", plist)
    @test occursin("DistSSHKitQueue", plist)
    @test occursin("serve", plist)
    unit = DistSSHKitQueue.systemd_user_unit("/usr/bin/julia", "/opt/Queue.jl")
    @test occursin("ExecStart=/usr/bin/julia --startup-file=no --project=/opt/Queue.jl -m DistSSHKitQueue serve", unit)
    @test occursin("Restart=on-failure", unit)
end
