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

@testset "extract_remote_opts and remote_inner" begin
    withenv("JULIA_DISTRIBUTED_EXE" => nothing) do
        host, rjulia, payload = DistSSHKitQueue.extract_remote_opts(["--on", "m4", "status"])
        @test host == "m4"
        @test rjulia === nothing
        @test payload == ["status"]
        dest, spec = DistSSHKitQueue.coalesce_remote(host, rjulia, nothing, nothing)
        @test dest == "m4"
        @test spec == "auto"
    end
    withenv("JULIA_DISTRIBUTED_EXE" => "/opt/from-env/julia") do
        h, j, p = DistSSHKitQueue.extract_remote_opts(["--on", "m4", "status"])
        _, spec = DistSSHKitQueue.coalesce_remote(h, j, nothing, nothing)
        @test spec == "/opt/from-env/julia"
        @test p == ["status"]
    end

    host2, rjulia2, payload2 = DistSSHKitQueue.extract_remote_opts(["--on", "m4", "--remote-julia", "/opt/julia", "go", "S.jl"])
    @test host2 == "m4"
    @test rjulia2 == "/opt/julia"
    @test payload2 == ["go", "S.jl"]

    host3, j3, payload3 = DistSSHKitQueue.extract_remote_opts(["go", "S.jl"])
    @test host3 === nothing
    @test j3 === nothing
    @test payload3 == ["go", "S.jl"]

    @test_throws ArgumentError DistSSHKitQueue.coalesce_remote("a", nothing, "b", nothing)

    host4, _, payload4 = DistSSHKitQueue.extract_remote_opts(String[])
    @test host4 === nothing
    @test payload4 == String[]

    @test DistSSHKitQueue.remote_inner("julia", "submit", ["go", "S.jl", "h:2"]) ==
          "'julia' '-m' 'DistSSHKitQueue' 'submit' 'go' 'S.jl' 'h:2'"
    cmd = DistSSHKitQueue.remote_command("m4-mini-ts", "julia", "status", String[])
    s = string(cmd)
    @test occursin("ssh", s)
    @test occursin("m4-mini-ts", s)
    @test occursin("DistSSHKitQueue", s)
end

@testset "wrapper_body and setup --write-only" begin
    body = DistSSHKitQueue.wrapper_body("/opt/bin/julia", "/opt/Queue.jl")
    @test startswith(body, "#!/bin/sh\n")
    @test occursin("'/opt/bin/julia'", body)
    @test occursin("--project='/opt/Queue.jl'", body)
    @test occursin("-m DistSSHKitQueue", body)
    mktempdir() do d
        bindir = joinpath(d, "bin")
        cfg = joinpath(d, "config.toml")
        other = joinpath(d, "keep.toml")
        write(other, "store = \"x\"\n")
        julia = DistSSHKitQueue.default_julia_bin()
        project = dirname(dirname(pathof(DistSSHKitQueue)))
        withenv("DISTSSHKITQUEUE_CONFIG" => joinpath(d, "missing.toml")) do
            @test DistSSHKitQueue.main([
                "setup",
                "--julia", julia,
                "--project", project,
                "--bindir", bindir,
                "--config", cfg,
                "--write-only",
            ]) == 0
        end
        wrap = joinpath(bindir, "dskq")
        @test isfile(wrap)
        text = read(wrap, String)
        @test occursin("-m DistSSHKitQueue", text)
        @test occursin("--project=", text)
        @test isfile(cfg)
        @test occursin("[env]", read(cfg, String))
        @test DistSSHKitQueue.write_config_template(other) === false
        @test read(other, String) == "store = \"x\"\n"
    end
end
