"""OS unit that runs `julia --project=<queue-env> -m DistSSHKitQueue serve`.

Writes a LaunchAgent (macOS) or systemd user unit (Linux). Not a second protocol.
"""

const SERVICE_LABEL = "org.distsshkitqueue.serve"
const SYSTEMD_UNIT = "distsshkitqueue.serve.service"

function xml_escape(s::AbstractString)::String
    t = replace(String(s), "&" => "&amp;")
    t = replace(t, "<" => "&lt;")
    t = replace(t, ">" => "&gt;")
    return replace(t, '"' => "&quot;")
end

function launch_agent_path(; home::AbstractString=homedir())::String
    return joinpath(home, "Library", "LaunchAgents", string(SERVICE_LABEL, ".plist"))
end

function systemd_user_path(; home::AbstractString=homedir())::String
    return joinpath(home, ".config", "systemd", "user", SYSTEMD_UNIT)
end

function launch_agent_plist(julia::AbstractString, project::AbstractString)::String
    j = xml_escape(julia)
    p = xml_escape(project)
    return """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$(xml_escape(SERVICE_LABEL))</string>
    <key>ProgramArguments</key>
    <array>
        <string>$j</string>
        <string>--startup-file=no</string>
        <string>--project=$p</string>
        <string>-m</string>
        <string>DistSSHKitQueue</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
"""
end

function systemd_user_unit(julia::AbstractString, project::AbstractString)::String
    # systemd ExecStart: quote if the path has spaces.
    exe = occursin(r"\s", julia) ? "'$(replace(julia, "'" => "'\\''"))'" : String(julia)
    proj = occursin(r"\s", project) ? "'$(replace(project, "'" => "'\\''"))'" : String(project)
    return """
[Unit]
Description=DistSSHKitQueue serve

[Service]
Type=simple
ExecStart=$exe --startup-file=no --project=$proj -m DistSSHKitQueue serve
Restart=on-failure

[Install]
WantedBy=default.target
"""
end

function write_serve_unit(path::AbstractString, body::AbstractString)
    mkpath(dirname(path))
    write(path, body)
    return path
end

function service_install(; julia::AbstractString=default_julia_bin(), project::AbstractString=default_queue_env(), apply::Bool=true)
    jl = DistSSHKit.canonical_local_path(julia)
    proj = DistSSHKit.canonical_local_path(project)
    isfile(jl) || throw(ArgumentError("service: julia not found at $(repr(jl))"))
    isfile(joinpath(proj, "Project.toml")) || throw(ArgumentError("service: no Project.toml in $(repr(proj))"))
    if Sys.isapple()
        path = launch_agent_path()
        write_serve_unit(path, launch_agent_plist(jl, proj))
        apply && _launchctl_load(path)
        print_wrote(path)
        return 0
    elseif Sys.islinux()
        path = systemd_user_path()
        write_serve_unit(path, systemd_user_unit(jl, proj))
        apply && _systemd_enable()
        print_wrote(path)
        return 0
    end
    throw(ArgumentError("enable: macOS or Linux only"))
end

function service_uninstall(; apply::Bool=true, home::AbstractString=homedir())
    live = DistSSHKit.canonical_local_path(home) == DistSSHKit.canonical_local_path(homedir())
    if Sys.isapple()
        path = launch_agent_path(; home=home)
        apply && live && isfile(path) && _launchctl_unload()
        isfile(path) && rm(path)
        return 0
    elseif Sys.islinux()
        apply && live && _systemd_disable()
        path = systemd_user_path(; home=home)
        isfile(path) && rm(path)
        return 0
    end
    throw(ArgumentError("disable: macOS or Linux only"))
end

function _launchctl_load(path::AbstractString)
    uid = string(Libc.getuid())
    domain = "gui/$uid/$(SERVICE_LABEL)"
    try
        run(pipeline(`launchctl bootout $domain`; stdout=devnull, stderr=devnull))
    catch
    end
    run(`launchctl bootstrap gui/$uid $path`)
    return nothing
end

function _launchctl_unload()
    uid = string(Libc.getuid())
    try
        run(pipeline(`launchctl bootout gui/$uid/$(SERVICE_LABEL)`; stdout=devnull, stderr=devnull))
    catch
    end
    return nothing
end

function _systemd_enable()
    run(`systemctl --user daemon-reload`)
    run(`systemctl --user enable --now $(SYSTEMD_UNIT)`)
    return nothing
end

function _systemd_disable()
    try
        run(pipeline(`systemctl --user disable --now $(SYSTEMD_UNIT)`; stdout=devnull, stderr=devnull))
    catch
    end
    return nothing
end

function enable_main(args::Vector{String})::Cint
    julia = default_julia_bin()
    project = default_queue_env()
    apply = true
    i = 1
    while i <= length(args)
        if args[i] == "--julia" && i < length(args)
            julia = args[i+1]
            i += 2
        elseif args[i] == "--queue-env" && i < length(args)
            project = args[i+1]
            i += 2
        elseif args[i] == "--project"
            throw(ArgumentError(
                "enable: use --queue-env DIR, not --project. " *
                "Julia `--project=` loads DistSSHKitQueue; project is cwd / DISTRIBUTED_PROJECT_ROOT.",
            ))
        elseif args[i] == "--write-only"
            apply = false
            i += 1
        elseif args[i] in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown enable option: $(args[i])"))
        end
    end
    return service_install(; julia=julia, project=project, apply=apply)
end

function disable_main(args::Vector{String})::Cint
    apply = true
    i = 1
    while i <= length(args)
        if args[i] == "--write-only"
            apply = false
            i += 1
        elseif args[i] in ("-h", "--help")
            show_usage()
            return 0
        else
            throw(ArgumentError("unknown disable option: $(args[i])"))
        end
    end
    return service_uninstall(; apply=apply)
end

function service_main(::Vector{String})::Cint
    throw(ArgumentError("service is gone; use enable (reboot serve) or disable (drop the OS unit)"))
end
