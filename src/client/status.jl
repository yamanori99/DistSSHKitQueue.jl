"""Client `status`. Prints the table on the queue host (after ssh if `--qhost`)."""

function show_status(store::AbstractString; io::IO=stdout)
    rows = isfile(store) ? read_jobs(store) : Job[]
    println(io, "store: $store")
    isempty(rows) && (println(io, "(empty)"); return nothing)
    for j in rows
        parts = String[j.id, String(j.state), String(j.kind), j.script, join(j.hosts, ',')]
        proj = get(j.kwargs, "project", nothing)
        proj === nothing || push!(parts, String(proj))
        j.result_path === nothing || push!(parts, j.result_path)
        println(io, join(parts, "  "))
    end
    return nothing
end
