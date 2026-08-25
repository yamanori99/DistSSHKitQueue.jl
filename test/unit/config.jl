using Test
using DistSSHKit
using DistSSHKitQueue

@testset "config path and store resolution" begin
    mktempdir() do d
        cfg = joinpath(d, "config.toml")
        store_cfg = joinpath(d, "from_config.toml")
        store_env = joinpath(d, "from_env.toml")
        write(cfg, "store = $(repr(store_cfg))\n\n[env]\nDSKQ_TEST_FROM_CFG = \"cfg\"\nDSKQ_TEST_KEEP = \"cfg\"\n")
        withenv(
            "DISTSSHKITQUEUE_CONFIG" => cfg,
            "DISTSSHKITQUEUE_STORE" => nothing,
            "DSKQ_TEST_FROM_CFG" => nothing,
            "DSKQ_TEST_KEEP" => "env",
        ) do
            @test DistSSHKitQueue.config_path() == cfg
            loaded = DistSSHKitQueue.load_config()
            @test DistSSHKitQueue.config_store_path(loaded) == store_cfg
            @test DistSSHKitQueue.store_path() == store_cfg
            DistSSHKitQueue.apply_config_env!(loaded)
            @test ENV["DSKQ_TEST_FROM_CFG"] == "cfg"
            @test ENV["DSKQ_TEST_KEEP"] == "env"
        end
        withenv("DISTSSHKITQUEUE_CONFIG" => cfg, "DISTSSHKITQUEUE_STORE" => store_env) do
            @test DistSSHKitQueue.store_path() == store_env
        end
        missing = joinpath(d, "nope.toml")
        withenv("DISTSSHKITQUEUE_CONFIG" => missing, "DISTSSHKITQUEUE_STORE" => nothing) do
            @test DistSSHKitQueue.load_config() == Dict{String,Any}()
            @test DistSSHKitQueue.store_path() == DistSSHKitQueue.default_store_path()
        end
        pop!(ENV, "DSKQ_TEST_FROM_CFG", nothing)
        pop!(ENV, "DSKQ_TEST_KEEP", nothing)
    end
end

@testset "with_store_lock retries EEXIST races" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        n = Threads.Atomic{Int}(0)
        tasks = [@async begin
            for _ in 1:40
                DistSSHKitQueue.with_store_lock(store) do
                    Threads.atomic_add!(n, 1)
                    sleep(0.001)
                end
            end
        end for _ in 1:4]
        foreach(wait, tasks)
        @test n[] == 160
    end
end

@testset "waiter pidfile" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        @test !DistSSHKitQueue.waiter_alive(store)
        DistSSHKitQueue.write_pid_file(store)
        @test DistSSHKitQueue.waiter_alive(store)
        DistSSHKitQueue.remove_pid_file(store)
        @test !DistSSHKitQueue.waiter_alive(store)
        write(DistSSHKitQueue.store_pid_path(store), "999999999")
        @test !DistSSHKitQueue.waiter_alive(store)
    end
end

@testset "detached serve script carries test tag" begin
    withenv("DISTSSHKITQUEUE_SERVE_TAG" => nothing) do
        script = DistSSHKitQueue.detached_serve_script("/julia", "/proj", "/tmp/q.log")
        @test occursin("nohup", script)
        @test !occursin("DISTSSHKITQUEUE_SERVE_TAG=", script)
    end
    withenv("DISTSSHKITQUEUE_SERVE_TAG" => "dskq-test-tag") do
        tagged = DistSSHKitQueue.detached_serve_script("/julia", "/proj", "/tmp/q.log")
        @test occursin("DISTSSHKITQUEUE_SERVE_TAG='dskq-test-tag'", tagged)
        @test occursin("nohup", tagged)
    end
end

@testset "write_pid_file appends DISTSSHKITQUEUE_TEST_PIDS" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        list = joinpath(d, "pids")
        write(list, "")
        withenv("DISTSSHKITQUEUE_TEST_PIDS" => list) do
            DistSSHKitQueue.write_pid_file(store)
        end
        @test occursin(string(getpid()), read(list, String))
        DistSSHKitQueue.remove_pid_file(store)
    end
end

@testset "ensure_waiter! skips when alive or opted out" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        withenv("DISTSSHKITQUEUE_NO_AUTOSERVE" => "1") do
            @test !DistSSHKitQueue.ensure_waiter!(store)
        end
        DistSSHKitQueue.write_pid_file(store)
        withenv("DISTSSHKITQUEUE_NO_AUTOSERVE" => nothing) do
            @test !DistSSHKitQueue.ensure_waiter!(store) # already alive (this test's own pid)
        end
        DistSSHKitQueue.remove_pid_file(store)
    end
end

@testset "stop latch holds off auto-serve until serve clears it" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        @test !DistSSHKitQueue.waiter_stopped(store)
        DistSSHKitQueue.set_stopped!(store)
        @test DistSSHKitQueue.waiter_stopped(store)
        @test isfile(DistSSHKitQueue.store_stop_path(store))
        withenv("DISTSSHKITQUEUE_NO_AUTOSERVE" => nothing) do
            @test !DistSSHKitQueue.ensure_waiter!(store) # latched off, no spawn
        end
        DistSSHKitQueue.clear_stopped!(store)
        @test !DistSSHKitQueue.waiter_stopped(store)
    end
end

@testset "stop_cli sets the latch and reports" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        write(store, "jobs = []\n")
        withenv("DISTSSHKITQUEUE_STORE" => store, "DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml")) do
            code, out, _ = capture_stdio() do
                DistSSHKitQueue.stop_cli(String[])
            end
            @test code == 0
            @test occursin("Stopped waiter", out)
        end
        @test DistSSHKitQueue.waiter_stopped(store)
    end
end

@testset "serve! refuses a second waiter" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        write(store, "jobs = []\n")
        holder = run(pipeline(`sleep 30`; stdout=devnull, stderr=devnull); wait=false)
        try
            write(DistSSHKitQueue.store_pid_path(store), string(getpid(holder)))
            q = DistSSHKitQueue.Queue(; store=store, runner=_ -> nothing)
            _, out, _ = capture_stdio() do
                DistSSHKitQueue.serve!(q; interval=0.02)
            end
            @test occursin("Already running", out)
            @test occursin("status or watch", out)
            @test DistSSHKitQueue.waiter_pid(store) == getpid(holder)
        finally
            kill(holder)
            wait(holder)
        end
    end
end

@testset "serve! stops when its pidfile is removed" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        write(store, "jobs = []\n")
        q = DistSSHKitQueue.Queue(; store=store, runner=_ -> nothing)
        _, out, _ = capture_stdio() do
            t = @async DistSSHKitQueue.serve!(q; interval=0.02)
            for _ in 1:200
                DistSSHKitQueue.waiter_pid(store) == getpid() && break
                sleep(0.02)
            end
            rm(d; force=true, recursive=true)
            for _ in 1:200
                istaskdone(t) && break
                sleep(0.02)
            end
            @test istaskdone(t)
            wait(t)
        end
        @test occursin("Waiter stopping", out)
        @test !isfile(store)
    end
end

@testset "serve! clears the stop latch on start" begin
    mktempdir() do d
        store = joinpath(d, "jobs.toml")
        write(store, "jobs = []\n")
        DistSSHKitQueue.set_stopped!(store)
        q = DistSSHKitQueue.Queue(; store=store, runner=_ -> nothing)
        capture_stdio() do
            t = @async DistSSHKitQueue.serve!(q; interval=0.02)
            for _ in 1:100
                DistSSHKitQueue.waiter_stopped(store) || break
                sleep(0.02)
            end
            @test !DistSSHKitQueue.waiter_stopped(store)
            schedule(t, InterruptException(); error=true)
            try
                wait(t)
            catch
            end
        end
    end
end

@testset "default_queue_env prefers the dedicated env dir" begin
    mktempdir() do d
        dedicated = joinpath(d, "env")
        fallback = DistSSHKit.canonical_local_path(dirname(Base.active_project()))
        @test DistSSHKitQueue.default_queue_env(; dedicated=dedicated) == fallback
        mkpath(dedicated)
        write(joinpath(dedicated, "Project.toml"), "name = \"x\"\n")
        @test DistSSHKitQueue.default_queue_env(; dedicated=dedicated) == dedicated
    end
end

@testset "extract_remote_opts" begin
    withenv("DISTSSHKITQUEUE_HOST" => nothing) do
    withenv("JULIA_DISTRIBUTED_EXE" => nothing) do
        host, rjulia, payload = DistSSHKitQueue.extract_remote_opts(["qhost:qbox", "status"])
        @test host == "qbox"
        @test rjulia === nothing
        @test payload == ["status"]
        dest, spec = DistSSHKitQueue.coalesce_remote(host, rjulia, nothing, nothing)
        @test dest == "qbox"
        @test spec == "auto"
        h2, j2, p2 = DistSSHKitQueue.extract_remote_opts(["--hosts", "other", "status"])
        @test h2 === nothing
        @test j2 === nothing
        @test p2 == ["--hosts", "other", "status"]
        h3, _, p3 = DistSSHKitQueue.extract_remote_opts(["go", "--hosts", "child:w:2", "S.jl"])
        @test h3 === nothing
        @test p3 == ["go", "--hosts", "child:w:2", "S.jl"]
        h4, j4, p4 = DistSSHKitQueue.extract_remote_opts(["go", "--julia", "/opt/julia", "S.jl"])
        @test h4 === nothing
        @test j4 === nothing
        @test p4 == ["go", "--julia", "/opt/julia", "S.jl"]
    end
    withenv("JULIA_DISTRIBUTED_EXE" => "/opt/from-env/julia") do
        h, j, p = DistSSHKitQueue.extract_remote_opts(["qhost:qbox", "status"])
        _, spec = DistSSHKitQueue.coalesce_remote(h, j, nothing, nothing)
        @test spec == "/opt/from-env/julia"
        @test p == ["status"]
    end

    host2, rjulia2, payload2 = DistSSHKitQueue.extract_remote_opts([
        "qhost:qbox", "--remote-julia", "/opt/julia", "go", "parent:1", "S.jl",
    ])
    @test host2 == "qbox"
    @test rjulia2 == "/opt/julia"
    @test payload2 == ["go", "parent:1", "S.jl"]
    @test_throws ArgumentError DistSSHKitQueue.extract_remote_opts(["--qhost", "qbox", "status"])
    @test DistSSHKitQueue.parse_qhost_token("qhost:user@box") == "user@box"
    @test_throws ArgumentError DistSSHKitQueue.parse_qhost_token("child:w:2")

    host_go, julia_go, payload_go = DistSSHKitQueue.extract_remote_opts(["go", "child:w1:2", "S.jl"])
    @test host_go === nothing
    @test julia_go === nothing
    @test payload_go == ["go", "child:w1:2", "S.jl"]

    @test_throws ArgumentError DistSSHKitQueue.coalesce_remote("a", nothing, "b", nothing)
    @test_throws ArgumentError DistSSHKitQueue.reject_qhost_on_local("setup", "qbox")
    @test_throws ArgumentError DistSSHKitQueue.reject_qhost_on_local("enable", "qbox")
    @test_throws ArgumentError DistSSHKitQueue.reject_qhost_on_local("add-host", "qbox")
    @test_throws ArgumentError DistSSHKitQueue.reject_qhost_on_local("remove-host", "qbox")
    DistSSHKitQueue.reject_qhost_on_local("status", "qbox")
    DistSSHKitQueue.reject_qhost_on_local("list-host", "qbox")
    DistSSHKitQueue.reject_qhost_on_local("setup", nothing)
    code, _, err = capture_stdio() do
        DistSSHKitQueue.main(["qhost:qbox", "add-host", "host1"])
    end
    @test code == 1
    @test occursin("runs on the queue host", err)
    code2, _, err2 = capture_stdio() do
        DistSSHKitQueue.main(["qhost:qbox", "remove-host", "host1"])
    end
    @test code2 == 1
    @test occursin("runs on the queue host", err2)

    host4, _, payload4 = DistSSHKitQueue.extract_remote_opts(String[])
    @test host4 === nothing
    @test payload4 == String[]

    @test DistSSHKitQueue.looks_like_kit_go_argv(["--hosts", "child:w:2", "S.jl"])
    @test DistSSHKitQueue.looks_like_kit_go_argv(["--julia", "/opt/julia", "S.jl"])
    @test DistSSHKitQueue.looks_like_kit_go_argv(["child:w:2", "S.jl"])
    @test !DistSSHKitQueue.looks_like_kit_go_argv(["go", "--hosts", "child:w:2", "S.jl"])
    @test !DistSSHKitQueue.looks_like_kit_go_argv(["submit", "go", "--hosts", "child:w:2", "S.jl"])
    @test !DistSSHKitQueue.looks_like_kit_go_argv(["enable", "--julia", "/opt/julia"])
    @test !DistSSHKitQueue.looks_like_kit_go_argv(["status"])
    @test !DistSSHKitQueue.looks_like_kit_go_argv(["--hosts", "child:w:2"])
    withenv("DISTSSHKITQUEUE_HOST" => "qbox") do
        hd, _, pd = DistSSHKitQueue.extract_remote_opts(["status"])
        @test hd == "qbox"
        @test pd == ["status"]
        ht, _, _ = DistSSHKitQueue.extract_remote_opts(["qhost:other", "status"])
        @test ht == "other"
    end
    withenv("DISTSSHKITQUEUE_HOST" => "qhost:qbox") do
        hp, _, _ = DistSSHKitQueue.extract_remote_opts(["status"])
        @test hp == "qbox"
    end
    end
end

@testset "config host names" begin
    H = DistSSHKitQueue.HostAllow
    @test DistSSHKitQueue.config_host_names(Dict{String,Any}()) === nothing
    @test DistSSHKitQueue.config_host_names(Dict{String,Any}("store" => "x")) === nothing
    @test DistSSHKitQueue.config_host_names(Dict{String,Any}("hosts" => [" parent ", "child:host1"])) ==
          H("parent" => nothing, "host1" => nothing)
    @test DistSSHKitQueue.config_host_names(Dict{String,Any}("hosts" => ["child:host1", "parent:2"])) ==
          H("host1" => nothing, "parent" => 2)
    @test DistSSHKitQueue.config_host_names(Dict{String,Any}("allowed" => ["child:host1", "parent:2"])) ==
          H("host1" => nothing, "parent" => 2)
    @test DistSSHKitQueue.kit_ssh_name("child:host1:4") == "host1"
    @test DistSSHKitQueue.kit_ssh_name("parent") == "parent"
    @test_throws ArgumentError DistSSHKitQueue.kit_ssh_name("host1")
    @test DistSSHKitQueue.config_host_names(Dict{String,Any}("hosts" => Any[])) == H()
    @test_throws ArgumentError DistSSHKitQueue.config_host_names(Dict{String,Any}("hosts" => ["host1"]))
    @test_throws ArgumentError DistSSHKitQueue.config_host_names(Dict{String,Any}("hosts" => "parent"))
    @test_throws ArgumentError DistSSHKitQueue.config_host_names(
        Dict{String,Any}("hosts" => ["parent"], "allowed" => ["child:host1"]),
    )
end

@testset "add-host / remove-host write hosts" begin
    mktempdir() do d
        H = DistSSHKitQueue.HostAllow
        cfg = joinpath(d, "config.toml")
        DistSSHKitQueue.write_config_template(cfg)
        DistSSHKitQueue.add_host_names!(cfg, ["parent", "child:host1"])
        text = read(cfg, String)
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=cfg)) ==
              H("parent" => nothing, "host1" => nothing)
        @test occursin("hosts = [", text)
        @test occursin("child:host1", text)
        @test occursin("[env]", text)
        @test occursin("# DistSSHKitQueue", text)
        @test occursin("DISTRIBUTED_SSH_OPTS", text)
        @test !occursin("# hosts", text)
        DistSSHKitQueue.add_host_names!(cfg, ["child:host1"])
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=cfg)) ==
              H("parent" => nothing, "host1" => nothing)
        DistSSHKitQueue.add_host_names!(cfg, ["child:host1:4"])
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=cfg)) ==
              H("parent" => nothing, "host1" => 4)
        @test occursin("child:host1:4", read(cfg, String))
        DistSSHKitQueue.remove_host_names!(cfg, ["parent"])
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=cfg)) ==
              H("host1" => 4)
        DistSSHKitQueue.remove_host_names!(cfg, ["child:host1"])
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=cfg)) ==
              H()
        @test occursin("hosts = []", read(cfg, String))
        @test_throws ArgumentError DistSSHKitQueue.remove_host_names!(cfg, ["child:host1"])
        @test_throws ArgumentError DistSSHKitQueue.add_host_names!(cfg, ["host1"])
        missing = joinpath(d, "none.toml")
        DistSSHKitQueue.add_host_names!(missing, ["child:host1"])
        @test isfile(missing)
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=missing)) ==
              H("host1" => nothing)
        @test_throws ArgumentError DistSSHKitQueue.add_host_names!(cfg, String[])
        @test DistSSHKitQueue.replace_or_insert_hosts_line("store = \"x\"\n", "hosts = []") ==
              "store = \"x\"\nhosts = []\n"
        old = joinpath(d, "old.toml")
        write(old, "store = \"x\"\nallowed = [\"parent\"]\n")
        DistSSHKitQueue.add_host_names!(old, ["child:host1"])
        migrated = read(old, String)
        @test occursin("hosts = [", migrated)
        @test occursin("child:host1", migrated)
        @test !occursin("allowed =", migrated)
        @test DistSSHKitQueue.config_host_names(DistSSHKitQueue.load_config(; path=old)) ==
              H("parent" => nothing, "host1" => nothing)
    end
end

@testset "setup writes config, not a dskq shim" begin
    mktempdir() do d
        bindir = joinpath(d, "bin")
        cfg = joinpath(d, "config.toml")
        other = joinpath(d, "keep.toml")
        write(other, "store = \"x\"\n")
        withenv("DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml")) do
            code, out, _ = capture_stdio() do
                DistSSHKitQueue.main(["setup", "--config", cfg])
            end
            @test code == 0
            @test occursin("Wrote", out)
        end
        @test !isfile(joinpath(bindir, "dskq"))
        @test isfile(cfg)
        @test occursin("[env]", read(cfg, String))
        @test occursin("# hosts", read(cfg, String))
        @test DistSSHKitQueue.write_config_template(other) === false
        @test read(other, String) == "store = \"x\"\n"
    end
end

@testset "setup re-run is idempotent; --force rewrites" begin
    mktempdir() do d
        cfg = joinpath(d, "config.toml")
        run_setup(extra) = capture_stdio() do
            DistSSHKitQueue.main(vcat(["setup", "--config", cfg], extra))
        end
        withenv("DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml")) do
            code1, out1, _ = run_setup(String[])
            @test code1 == 0
            @test occursin("Wrote", out1)
            write(cfg, "store = \"edited\"\n")
            code2, out2, _ = run_setup(String[])
            @test code2 == 0
            @test occursin("Present", out2)
            @test read(cfg, String) == "store = \"edited\"\n"
            code3, out3, _ = run_setup(["--force"])
            @test code3 == 0
            @test occursin("Wrote", out3)
            @test occursin("[env]", read(cfg, String))
            code4, _, err4 = run_setup(["--service"])
            @test code4 == 1
            @test occursin("enable", err4)
            code5, _, err5 = capture_stdio() do
                DistSSHKitQueue.main(["service", "install"])
            end
            @test code5 == 1
            @test occursin("enable", err5)
        end
    end
end

@testset "teardown -y removes queue-host files" begin
    mktempdir() do home
        data = joinpath(home, ".distsshkitqueue")
        mkpath(joinpath(data, "env"))
        cfg = joinpath(data, "config.toml")
        store = joinpath(data, "jobs.toml")
        write(cfg, "store = $(repr(store))\n")
        write(store, "jobs = []\n")
        write(string(store, ".log"), "log\n")
        write(joinpath(data, "env", "Project.toml"), "name = \"x\"\n")
        bindir = joinpath(home, ".local", "bin")
        mkpath(bindir)
        wrap = joinpath(bindir, "dskq")
        write(wrap, "#!/bin/sh\n")
        withenv(
            "DISTSSHKITQUEUE_CONFIG" => nothing,
            "DISTSSHKITQUEUE_STORE" => nothing,
            "DISTSSHKIT_YES" => nothing,
        ) do
            code1, _, err1 = capture_stdio() do
                DistSSHKitQueue.teardown_main(["--home", home, "--write-only"])
            end
            @test code1 == 1
            @test occursin("teardown needs -y", err1)
            @test isfile(store)
            @test isfile(wrap)
            code2, out2, _ = capture_stdio() do
                DistSSHKitQueue.teardown_main(["--home", home, "-y", "--write-only"])
            end
            @test code2 == 0
            @test occursin("Removed", out2)
        end
        @test !ispath(data)
        @test !isfile(wrap)
    end
end

@testset "teardown honors DISTSSHKIT_YES like DistSSHKit" begin
    mktempdir() do home
        data = joinpath(home, ".distsshkitqueue")
        mkpath(data)
        cfg = joinpath(data, "config.toml")
        store = joinpath(data, "jobs.toml")
        write(cfg, "store = $(repr(store))\n")
        write(store, "jobs = []\n")
        withenv(
            "DISTSSHKITQUEUE_CONFIG" => nothing,
            "DISTSSHKITQUEUE_STORE" => nothing,
            "DISTSSHKIT_YES" => "true",
        ) do
            code, _, err = capture_stdio() do
                DistSSHKitQueue.teardown_main(["--home", home, "--write-only"])
            end
            @test code == 0
            @test !occursin("teardown needs -y", err)
        end
        @test !ispath(data)
    end
end

@testset "teardown DISTSSHKIT_YES from target config [env]" begin
    mktempdir() do home
        data = joinpath(home, ".distsshkitqueue")
        mkpath(data)
        cfg = joinpath(data, "config.toml")
        store = joinpath(data, "jobs.toml")
        write(cfg, "store = $(repr(store))\n\n[env]\nDISTSSHKIT_YES = \"1\"\n")
        write(store, "jobs = []\n")
        withenv(
            "DISTSSHKITQUEUE_CONFIG" => nothing,
            "DISTSSHKITQUEUE_STORE" => nothing,
            "DISTSSHKIT_YES" => nothing,
        ) do
            code, _, _ = capture_stdio() do
                DistSSHKitQueue.teardown_main(["--home", home, "--write-only"])
            end
            @test code == 0
        end
        @test !ispath(data)
    end
end
