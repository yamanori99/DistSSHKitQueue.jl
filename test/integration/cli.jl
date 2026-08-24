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
    # `read_jobs`: `load_jobs` would treat a live `:running` row without `kit.pid`
    # yet as a restart and report `:failed` in-memory (and tests would pass/fail on a lie).
    return DistSSHKitQueue.read_jobs(env["DISTSSHKITQUEUE_STORE"])
end

function wait_job(env, id, states; tries=900, sleep_s=0.2)
    want = Set{Symbol}(states)
    sid = String(id)
    last = DistSSHKitQueue.Job[]
    for _ = 1:tries
        last = store_jobs(env)
        i = findfirst(j -> j.id == sid, last)
        if i !== nothing && last[i].state in want
            return last[i]
        end
        sleep(sleep_s)
    end
    error("timeout waiting for $sid in $want; last=$last")
end

function wait_kit_pid(path::AbstractString; tries=300, sleep_s=0.1)
    for _ = 1:tries
        isfile(path) && return nothing
        sleep(sleep_s)
    end
    error("timeout waiting for $path")
end

function cli_env(d::AbstractString)
    cfg = joinpath(d, "config.toml")
    store = joinpath(d, "jobs.toml")
    jobdir = joinpath(d, "job")
    mkpath(jobdir)
    write(joinpath(jobdir, "Project.toml"), "[deps]\n")
    write(joinpath(jobdir, "hello.jl"), "println(\"cli-local\")\n")
    write(joinpath(jobdir, "hold.jl"), "run(`sleep 600`)\n")
    write(cfg, "store = $(repr(store))\n\n[env]\nDISTSSHKIT_YES = \"1\"\n")
    env = Dict(
        "DISTSSHKITQUEUE_CONFIG" => cfg,
        "DISTSSHKITQUEUE_STORE" => store,
        "DISTSSHKIT_YES" => "1",
    )
    withenv(env..., "DISTSSHKITQUEUE_NO_AUTOSERVE" => "1") do
        DistSSHKitQueue.main(["setup", "--config", cfg]) == 0 || error("setup failed")
    end
    return env, cfg, store, jobdir
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
    @testset "setup submit status parent:1 (explicit serve)" begin
        mktempdir() do d
            base, _, store, jobdir = cli_env(d)
            env = merge(base, Dict("DISTSSHKITQUEUE_NO_AUTOSERVE" => "1"))
            serve_cmd = addenv(qcli(["serve", "--interval", "0.1"]), env...)
            proc = run(serve_cmd; wait=false)
            try
                cd(jobdir) do
                    id = strip(read(addenv(qcli(["submit", "go", "parent:1", "hello.jl"]), env...), String))
                    @test !isempty(id)
                    row = wait_job(env, id, (:done, :failed))
                    @test row.state === :done
                    out = read(addenv(qcli(["status"]), env...), String)
                    @test occursin(id, out)
                    wout = read(addenv(qcli(["watch", "--ticks", "1", "--interval", "0.05"]), env...), String)
                    @test occursin("DistSSHKitQueue watch", wout)
                    @test occursin(id, wout)
                    @test occursin("done", wout)
                    @test occursin("Ctrl-C stops watch", wout)
                end
            finally
                DistSSHKitQueue.stop_waiter!(store)
                try
                    kill(proc)
                    wait(proc)
                catch
                end
            end
        end
    end

    @testset "auto-serve submit and cancel queued" begin
        mktempdir() do d
            env, _, store, jobdir = cli_env(d)
            try
                cd(jobdir) do
                    hold_out = joinpath(d, "hold-queued-out")
                    id1 = strip(read(addenv(qcli(["submit", "go", "parent:1", "--output-dir", hold_out, "hold.jl"]), env...), String))
                    @test !isempty(id1)
                    row = wait_job(env, id1, (:running,))
                    wait_kit_pid(joinpath(hold_out, "kit.pid"))
                    @test row.state === :running
                    id2 = strip(read(addenv(qcli(["submit", "go", "parent:1", "hello.jl"]), env...), String))
                    queued = wait_job(env, id2, (:queued,))
                    @test queued.state === :queued
                    c = strip(read(addenv(qcli(["cancel", id2]), env...), String))
                    @test c == id2
                    listed = read(addenv(qcli(["status"]), env...), String)
                    @test occursin(id1, listed)
                    @test occursin(id2, listed)
                    @test occursin("cancelled", listed)
                end
            finally
                DistSSHKitQueue.stop_waiter!(store)
            end
        end
    end

    @testset "cancel running parent:1" begin
        mktempdir() do d
            env, _, store, jobdir = cli_env(d)
            outdir = joinpath(d, "cancel-run-out")
            try
                cd(jobdir) do
                    id = strip(read(addenv(qcli(["submit", "go", "parent:1", "--output-dir", outdir, "hold.jl"]), env...), String))
                    @test !isempty(id)
                    row = wait_job(env, id, (:running,))
                    wait_kit_pid(joinpath(outdir, "kit.pid"))
                    @test row.state === :running
                    c = strip(read(addenv(qcli(["cancel", id]), env...), String))
                    @test c == id
                    done = wait_job(env, id, (:cancelled, :failed, :done); tries=200)
                    @test done.state === :cancelled
                end
            finally
                DistSSHKitQueue.stop_waiter!(store)
            end
        end
    end

    @testset "--qhost HOST ssh argv (no remote exec)" begin
        mktempdir() do d
            env, _, _, _ = cli_env(d)
            log = joinpath(d, "ssh.log")
            fake = joinpath(d, "fakebin")
            write_fake_ssh(joinpath(fake, "ssh"), log)
            path = fake * ":" * get(ENV, "PATH", "")
            withenv(env..., "PATH" => path) do
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
