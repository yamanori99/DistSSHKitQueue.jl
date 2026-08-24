# Child CLI (`julia -m DistSSHKitQueue`) + parent:1. Not SSH.
# Fake `ssh` only checks `--qhost` argv. Real OpenSSH client path is test/e2e.jl.

using Test
using DistSSHKitQueue

const QUEUE_ROOT = abspath(joinpath(@__DIR__, "..", ".."))
const JULIA = DistSSHKitQueue.default_julia_bin()

qcli(args) = DistSSHKitQueue.with_serve_tag(
    `$JULIA --startup-file=no --project=$QUEUE_ROOT -m DistSSHKitQueue $(String[string(a) for a in args])`,
)

function store_jobs(env)
    return DistSSHKitQueue.load_jobs(env["DISTSSHKITQUEUE_STORE"])
end

function wait_jobs(pred, env; tries=200, sleep_s=0.1)
    rows = DistSSHKitQueue.Job[]
    for _ = 1:tries
        rows = store_jobs(env)
        pred(rows) && return rows
        sleep(sleep_s)
    end
    return rows
end

function wait_done(env; tries=600, sleep_s=0.2)
    wait_jobs(env; tries=tries, sleep_s=sleep_s) do rows
        any(j -> j.state === :done, rows) || any(j -> j.state === :failed, rows)
    end
    return read(addenv(qcli(["status"]), env...), String)
end

function stop_store_waiter(store::AbstractString)
    DistSSHKitQueue.stop_waiter!(store)
    return nothing
end

function write_fake_ssh(path::AbstractString, log::AbstractString)
    mkpath(dirname(path))
    write(
        path,
        """
#!/bin/sh
{
  for a in "\$@"; do
    printf '%s\\n' "\$a"
  done
  printf '%s\\n' "---"
} >> $(DistSSHKitQueue.sh_single_quote(log))
for a in "\$@"; do
  if [ "\$a" = "--version" ]; then
    printf '%s\\n' "julia version 1.12.7"
    exit 0
  fi
done
exit 0
""",
    )
    chmod(path, 0o755)
    return path
end

@testset "CLI (parent:1)" begin
    mktempdir() do d
        cfg = joinpath(d, "config.toml")
        store = joinpath(d, "jobs.toml")
        jobdir = joinpath(d, "job")
        mkpath(jobdir)
        write(joinpath(jobdir, "Project.toml"), "[deps]\n")
        write(joinpath(jobdir, "hello.jl"), "println(\"cli-local\")\n")
        write(joinpath(jobdir, "hold.jl"), "while true; sleep(1); end\n")
        write(cfg, "store = $(repr(store))\n\n[env]\nDISTSSHKIT_YES = \"1\"\n")
        baseenv = Dict(
            "DISTSSHKITQUEUE_CONFIG" => cfg,
            "DISTSSHKITQUEUE_STORE" => store,
            "DISTSSHKIT_YES" => "1",
        )
        withenv(baseenv..., "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1") do
            @test DistSSHKitQueue.main(["setup", "--config", cfg]) == 0
        end
        @test isfile(cfg)

        @testset "setup submit status parent:1 (explicit serve)" begin
            env = merge(baseenv, Dict("DISTSSHKITQUEUE_NO_AUTOSERVE" => "1"))
            serve_cmd = addenv(qcli(["serve", "--interval", "0.1"]), env...)
            proc = run(serve_cmd; wait=false)
            try
                cd(jobdir) do
                    id = strip(read(addenv(qcli(["submit", "go", "parent:1", "hello.jl"]), env...), String))
                    @test !isempty(id)
                    out = wait_done(env)
                    @test occursin(id, out)
                    @test occursin("  done  ", out)
                    wout = read(addenv(qcli(["watch", "--ticks", "1", "--interval", "0.05"]), env...), String)
                    @test occursin("DistSSHKitQueue watch", wout)
                    @test occursin(id, wout)
                    @test occursin("done", wout)
                    @test occursin("Ctrl-C stops watch", wout)
                end
            finally
                kill(proc)
                wait(proc)
            end
        end

        @testset "auto-serve submit and cancel queued" begin
            env = copy(baseenv)
            cd(jobdir) do
                hold_out = joinpath(d, "hold-queued-out")
                id1 = strip(read(addenv(qcli(["submit", "go", "parent:1", "--output-dir", hold_out, "hold.jl"]), env...), String))
                id2 = strip(read(addenv(qcli(["submit", "go", "parent:1", "hello.jl"]), env...), String))
                @test !isempty(id1)
                c = strip(read(addenv(qcli(["cancel", id2]), env...), String))
                @test c == id2
                rows = wait_jobs(env) do js
                    a = findfirst(j -> j.id == id1, js)
                    a !== nothing && js[a].state === :running && isfile(joinpath(hold_out, "kit.pid"))
                end
                @test any(j -> j.id == id1 && j.state === :running, rows)
                listed = read(addenv(qcli(["status"]), env...), String)
                @test occursin(id1, listed)
                @test occursin("  running  ", listed)
                st2 = read(addenv(qcli(["status"]), env...), String)
                @test occursin(id2, st2)
                @test occursin("cancelled", st2)
                @test strip(read(addenv(qcli(["cancel", id1]), env...), String)) == id1
            end
            stop_store_waiter(store)
        end

        @testset "cancel running parent:1" begin
            env = copy(baseenv)
            outdir = joinpath(d, "cancel-run-out")
            cd(jobdir) do
                id = strip(read(addenv(qcli(["submit", "go", "parent:1", "--output-dir", outdir, "hold.jl"]), env...), String))
                @test !isempty(id)
                rows = wait_jobs(env) do js
                    a = findfirst(j -> j.id == id, js)
                    a !== nothing && js[a].state === :running && isfile(joinpath(outdir, "kit.pid"))
                end
                @test any(j -> j.id == id && j.state === :running, rows)
                listed = read(addenv(qcli(["status"]), env...), String)
                @test occursin("  running  ", listed)
                c = strip(read(addenv(qcli(["cancel", id]), env...), String))
                @test c == id
                wait_jobs(env; tries=100) do js
                    a = findfirst(j -> j.id == id, js)
                    a !== nothing && js[a].state === :cancelled
                end
                st = read(addenv(qcli(["status"]), env...), String)
                @test occursin(id, st)
                @test occursin("cancelled", st)
            end
            stop_store_waiter(store)
        end

        @testset "--qhost HOST ssh argv (no remote exec)" begin
            log = joinpath(d, "ssh.log")
            fake = joinpath(d, "fakebin")
            write_fake_ssh(joinpath(fake, "ssh"), log)
            path = fake * ":" * get(ENV, "PATH", "")
            withenv(baseenv..., "PATH" => path) do
                @test DistSSHKitQueue.main([
                    "--qhost", "cluster-a",
                    "--remote-julia", JULIA,
                    "status",
                ]) == 0
                @test DistSSHKitQueue.main([
                    "--qhost", "cluster-a",
                    "--remote-julia", JULIA,
                    "watch",
                    "--ticks", "1",
                ]) == 0
            end
            dumped = read(log, String)
            @test occursin("cluster-a", dumped)
            @test occursin("DistSSHKitQueue", dumped)
            @test occursin("status", dumped)
            @test occursin("watch", dumped)
            @test occursin("--via", dumped)
        end
    end

    @testset "teardown -y after setup" begin
        mktempdir() do home
            data = joinpath(home, ".distsshkitqueue")
            bindir = joinpath(home, ".local", "bin")
            mkpath(bindir)
            leftover = joinpath(bindir, "dskq")
            write(leftover, "#!/bin/sh\n")
            withenv("DISTSSHKITQUEUE_CONFIG" => nothing, "DISTSSHKITQUEUE_STORE" => nothing) do
                @test DistSSHKitQueue.main([
                    "setup",
                    "--config", joinpath(data, "config.toml"),
                ]) == 0
                @test DistSSHKitQueue.main([
                    "teardown",
                    "--home", home,
                    "-y",
                    "--write-only",
                ]) == 0
            end
            @test !isfile(leftover)
            @test !isdir(data)
        end
    end
end
