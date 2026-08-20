"""Client `status`. Prints the table on the queue host (after ssh if `--qhost`)."""

function show_status(store::AbstractString; io::IO=stdout)
    rows = isfile(store) ? read_jobs(store) : Job[]
    return print_status_table(store, rows; io=io)
end
