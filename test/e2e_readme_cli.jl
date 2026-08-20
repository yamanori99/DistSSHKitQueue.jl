# README CLI over real SSH. JetLS entry; also included from test/e2e.jl.
#
# Product path: client `--qhost` → queue host → DistSSHKit `host:N` workers.
# Loopback OpenSSH is the queue host (this machine). docker-ssh is workers only.
# `enable` / `disable` / `teardown` use `--write-only` (no user systemd / launchctl).

using Test
using Sockets
using DistSSHKitQueue

const README_CLI_JULIA = DistSSHKitQueue.default_julia_bin()

function julia_depot_path_env()::String
    return join((p for p in DEPOT_PATH if !isempty(p)), Sys.iswindows() ? ";" : ":")
end

function readme_qcmd(test_project::AbstractString, args)
    return Cmd(String[
        README_CLI_JULIA, "--startup-file=no", "--project=$test_project",
        "-m", "DistSSHKitQueue", String[string(a) for a in args]...,
    ])
end

function wait_status(pred, cmd::Cmd; tries=600, sleep_s=0.2)
    out = ""
    for _ = 1:tries
        out = read(cmd, String)
        pred(out) && return out
        sleep(sleep_s)
    end
    return out
end

function ssh_login_user()
    u = strip(get(ENV, "USER", ""))
    isempty(u) && (u = strip(get(ENV, "LOGNAME", "")))
    isempty(u) && (u = strip(readchomp(`whoami`)))
    return u
end

function find_sshd()
    w = Sys.which("sshd")
    w !== nothing && return w
    for p in ("/usr/sbin/sshd", "/usr/libexec/sshd")
        isfile(p) && return p
    end
    error("sshd not found; README --qhost E2E needs OpenSSH server")
end

function free_loopback_port()
    server = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    _, port = Sockets.getsockname(server)
    close(server)
    return Int(port)
end

function write_loopback_sshd(dir::AbstractString, port::Int, controller_key::AbstractString)
    hostkey = joinpath(dir, "ssh_host_ed25519_key")
    isfile(hostkey) || run(`ssh-keygen -t ed25519 -f $hostkey -N "" -q`)
    auth = joinpath(dir, "authorized_keys")
    cp(string(controller_key, ".pub"), auth; force=true)
    chmod(auth, 0o600)
    cfg = joinpath(dir, "sshd_config")
    lines = String[
        "Port $port",
        "ListenAddress 127.0.0.1",
        "HostKey $hostkey",
        "PidFile $(joinpath(dir, "sshd.pid"))",
        "AuthorizedKeysFile $auth",
        "PasswordAuthentication no",
        "PubkeyAuthentication yes",
        "KbdInteractiveAuthentication no",
        "ChallengeResponseAuthentication no",
        "StrictModes no",
        "PermitRootLogin no",
        "PrintMotd no",
        "LoginGraceTime 10",
    ]
    Sys.islinux() && push!(lines, "UsePAM no")
    write(cfg, join(lines, '\n') * "\n")
    return cfg
end

function start_loopback_sshd(dir::AbstractString, port::Int, controller_key::AbstractString)
    cfg = write_loopback_sshd(dir, port, controller_key)
    log = joinpath(dir, "sshd.log")
    sshd = find_sshd()
    proc = run(`$sshd -D -f $cfg -E $log`; wait=false)::Base.Process
    for _ = 1:50
        process_running(proc) || break
        try
            sock = Sockets.connect(Sockets.IPv4(127, 0, 0, 1), port)
            close(sock)
            return proc
        catch
            sleep(0.1)
        end
    end
    extra = isfile(log) ? read(log, String) : ""
    try
        kill(proc)
        wait(proc)
    catch
    end
    error("loopback sshd failed to listen on 127.0.0.1:$port\n$extra")
end

function stop_loopback_sshd(proc::Base.Process)
    try
        process_running(proc) && kill(proc)
        wait(proc)
    catch
    end
    return nothing
end

function write_ssh_config_with_qhost(
    path::AbstractString,
    port::Int,
    user::AbstractString,
    ssh_config::AbstractString,
    controller_key::AbstractString,
)
    body = read(ssh_config, String)
    write(
        path,
        body * """

Host dskq-qh
  HostName 127.0.0.1
  User $(user)
  Port $(port)
  IdentityFile $(controller_key)
  IdentitiesOnly yes
  BatchMode yes
  ConnectTimeout 10
  StrictHostKeyChecking accept-new
  UserKnownHostsFile $(joinpath(dirname(path), "known_hosts"))
  TCPKeepAlive yes
""",
    )
    return path
end

function write_remote_julia(path::AbstractString, env::Dict{String,String})
    exports = String[]
    for (k, v) in env
        push!(exports, "export $k=$(DistSSHKitQueue.sh_single_quote(v))")
    end
    write(
        path,
        """
#!/bin/sh
$(join(exports, "\n"))
exec $(DistSSHKitQueue.sh_single_quote(README_CLI_JULIA)) "\$@"
""",
    )
    chmod(path, 0o755)
    return path
end

function readme_cli_e2e(;
    queue_root::AbstractString,
    docker_ssh::AbstractString,
    job_project::AbstractString,
    remote_root::AbstractString,
    ssh_config::AbstractString,
    hosts::Vector{String},
)
    test_project = joinpath(queue_root, "test")
    controller_key = joinpath(docker_ssh, ".generated", "controller")
    qcmd(args) = readme_qcmd(test_project, args)

    @testset "README CLI (queue host + --qhost)" verbose = true begin
        mktempdir() do d
            e2e_home = joinpath(d, "home")
            mkpath(e2e_home)
            cfg = joinpath(e2e_home, ".distsshkitqueue", "config.toml")
            store = joinpath(e2e_home, ".distsshkitqueue", "jobs.toml")
            token = "$(hosts[1]):1"
            script = joinpath(job_project, "demos", "without_kit", "pi_echo.jl")
            @test isfile(script)

            host_env = Dict{String,String}(
                "HOME" => e2e_home,
                "JULIA_DEPOT_PATH" => julia_depot_path_env(),
                "DISTSSHKITQUEUE_CONFIG" => cfg,
                "DISTSSHKITQUEUE_STORE" => store,
                "DISTSSHKIT_YES" => "1",
                "DISTSSHKIT_QUIET" => get(ENV, "DISTSSHKIT_QUIET", "1"),
                "DISTRIBUTED_SSH_OPTS" => "-F $(ssh_config)",
                "DISTRIBUTED_REMOTE_PROJECT_ROOT" => remote_root,
            )

            @testset "queue-host verbs (logged in; omit --qhost)" begin
                env = merge(host_env, Dict("DISTSSHKITQUEUE_NO_AUTOSERVE" => "1"))
                @test run(ignorestatus(addenv(qcmd(["setup"]), env...))).exitcode == 0
                @test isfile(cfg)
                @test run(ignorestatus(addenv(qcmd(["enable", "--write-only", "--project", test_project, "--julia", README_CLI_JULIA]), env...))).exitcode == 0
                unit = if Sys.isapple()
                    DistSSHKitQueue.launch_agent_path(; home=e2e_home)
                else
                    DistSSHKitQueue.systemd_user_path(; home=e2e_home)
                end
                @test isfile(unit)
                @test occursin("DistSSHKitQueue", read(unit, String))
                @test run(ignorestatus(addenv(qcmd(["disable", "--write-only"]), env...))).exitcode == 0
                @test !isfile(unit)

                serve_proc = run(addenv(qcmd(["serve", "--interval", "0.2"]), env...); wait=false)
                try
                    outdir = joinpath(job_project, "go_out", "readme_on_host")
                    isdir(outdir) && rm(outdir; recursive=true)
                    id = strip(read(addenv(qcmd(["submit", "go", token, "--output-dir", outdir, script, "64"]), env...), String))
                    @test !isempty(id)
                    listed = wait_status(addenv(qcmd(["status"]), env...)) do out
                        occursin(id, out) && occursin("  done  ", out) && !occursin("  running  ", out)
                    end
                    @test occursin(id, listed)
                    @test occursin("  done  ", listed)
                    wout = read(addenv(qcmd(["watch", "--ticks", "1", "--interval", "0.05"]), env...), String)
                    @test occursin("DistSSHKitQueue watch", wout)
                    @test occursin(id, wout)
                finally
                    DistSSHKitQueue.stop_waiter!(store)
                    try
                        kill(serve_proc)
                        wait(serve_proc)
                    catch
                    end
                end
                @test run(ignorestatus(addenv(qcmd(["stop"]), env...))).exitcode == 0
            end

            @testset "client --qhost (real ssh to loopback queue host)" begin
                sshd_dir = joinpath(d, "sshd")
                mkpath(sshd_dir)
                port = free_loopback_port()
                qh_store = joinpath(e2e_home, ".distsshkitqueue", "qhost-jobs.toml")
                sshd_proc = start_loopback_sshd(sshd_dir, port, controller_key)
                try
                    ssh_cfg = write_ssh_config_with_qhost(
                        joinpath(d, "ssh_config"), port, ssh_login_user(),
                        ssh_config, controller_key,
                    )
                    probe = run(ignorestatus(`ssh -F $ssh_cfg -o ConnectTimeout=5 dskq-qh true`))
                    probe.exitcode == 0 || error("loopback ssh to dskq-qh failed: $(read(joinpath(sshd_dir, "sshd.log"), String))")
                    remote_env = Dict{String,String}(
                        "HOME" => e2e_home,
                        "JULIA_DEPOT_PATH" => julia_depot_path_env(),
                        "JULIA_PROJECT" => test_project,
                        "DISTSSHKITQUEUE_CONFIG" => cfg,
                        "DISTSSHKITQUEUE_STORE" => qh_store,
                        "DISTSSHKIT_YES" => "1",
                        "DISTSSHKIT_QUIET" => get(ENV, "DISTSSHKIT_QUIET", "1"),
                        "DISTRIBUTED_SSH_OPTS" => "-F $(ssh_config)",
                        "DISTRIBUTED_REMOTE_PROJECT_ROOT" => remote_root,
                    )
                    wrapper = write_remote_julia(joinpath(d, "remote-julia"), remote_env)
                    client_env = Dict{String,String}(
                        "DISTSSHKIT_YES" => "1",
                        "DISTRIBUTED_SSH_OPTS" => "-F $ssh_cfg",
                    )
                    qh(rest) = qcmd(["--qhost", "dskq-qh", "--remote-julia", wrapper, rest...])

                    rejected = run(ignorestatus(addenv(qh(["setup"]), client_env...)))
                    @test rejected.exitcode != 0

                    outdir = joinpath(job_project, "go_out", "readme_qhost")
                    isdir(outdir) && rm(outdir; recursive=true)
                    id1 = strip(read(addenv(qh(["submit", "go", token, "--output-dir", outdir, script, "64"]), client_env...), String))
                    @test !isempty(id1)
                    listed = wait_status(addenv(qh(["status"]), client_env...)) do out
                        occursin(id1, out) && occursin("  done  ", out) && !occursin("  running  ", out)
                    end
                    @test occursin(id1, listed)
                    @test occursin("  done  ", listed)
                    wout = read(addenv(qh(["watch", "--ticks", "1", "--interval", "0.05"]), client_env...), String)
                    @test occursin(id1, wout)

                    cancel_out = joinpath(job_project, "go_out", "readme_cancel")
                    isdir(cancel_out) && rm(cancel_out; recursive=true)
                    id2 = strip(read(addenv(qh(["submit", "go", token, "--output-dir", cancel_out, script, "64"]), client_env...), String))
                    id3 = strip(read(addenv(qh(["submit", "go", token, script, "64"]), client_env...), String))
                    cancelled = strip(read(addenv(qh(["cancel", id3]), client_env...), String))
                    @test cancelled == id3
                    after = wait_status(addenv(qh(["status"]), client_env...)) do out
                        occursin(id2, out) && occursin("cancelled", out) && !occursin("  running  ", out)
                    end
                    @test occursin(id2, after)
                    @test occursin("cancelled", after)

                    @test run(ignorestatus(addenv(qh(["stop"]), client_env...))).exitcode == 0
                    @test run(ignorestatus(addenv(qh(["teardown", "-y", "--write-only"]), client_env...))).exitcode == 0
                finally
                    DistSSHKitQueue.stop_waiter!(qh_store)
                    DistSSHKitQueue.stop_waiter!(store)
                    stop_loopback_sshd(sshd_proc)
                end
            end
        end
    end
    return nothing
end
