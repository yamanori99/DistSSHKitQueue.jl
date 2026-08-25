"""CLI `add-host` / `remove-host`: write Kit placement tokens into config `hosts`."""

function add_host_cli(args::Vector{String})::Cint
    names = String[]
    for a in args
        if a in ("-h", "--help")
            show_usage()
            return 0
        end
        startswith(a, "-") && throw(ArgumentError("unknown add-host option: $(a)"))
        push!(names, a)
    end
    add_host_names!(config_path(), names)
    print_list_host(config_host_names(load_config()))
    return 0
end

function remove_host_cli(args::Vector{String})::Cint
    names = String[]
    for a in args
        if a in ("-h", "--help")
            show_usage()
            return 0
        end
        startswith(a, "-") && throw(ArgumentError("unknown remove-host option: $(a)"))
        push!(names, a)
    end
    remove_host_names!(config_path(), names)
    print_list_host(config_host_names(load_config()))
    return 0
end
