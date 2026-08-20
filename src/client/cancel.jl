"""Client `cancel <id>`. `:queued` only; runs on the queue host after ssh."""

function cancel_cli(args::Vector{String})::Cint
    isempty(args) && throw(ArgumentError("cancel: need a job id"))
    args[1] in ("-h", "--help") && (show_usage(); return 0)
    length(args) == 1 || throw(ArgumentError("cancel: extra arguments"))
    id = String(args[1])
    q = Queue(; store=store_path())
    cancelled = try
        cancel!(q, id)
    catch e
        e isa ArgumentError || rethrow()
        false # unknown id reads the same as "not queued" to the caller
    end
    if cancelled
        println(id)
        return 0
    end
    DistSSHKit.print_cli_error("job $(repr(id)) is not queued")
    return 1
end
