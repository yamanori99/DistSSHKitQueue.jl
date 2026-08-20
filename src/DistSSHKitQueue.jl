"""
DistSSHKitQueue — FIFO waiter for DistSSHKit (`go` / `drive`).

CLI: `serve`, `status`, `submit go` / `submit drive`, `cancel`, `service`.
Julia: `Queue`, `submit!`, `job`, `jobs`, `cancel!`, `serve!`.
Waiter runs DistSSHKit `execute!(...; detached=true)`.
`--project=<queue-env>` loads this package; the job tree is `job_project()`.

Design: [`DESIGN.md`](https://github.com/yamanori99/DistSSHKitQueue.jl/blob/main/DESIGN.md).
"""
module DistSSHKitQueue

using Dates
using DistSSHKit
using TOML

export Queue
export Job
export submit!
export cancel!
export jobs
export job
export step!
export load!
export serve!
export serve
export job_project
export default_store_path
export main

include("DistSSHKitQueue/job.jl")
include("DistSSHKitQueue/store.jl")
include("DistSSHKitQueue/queue.jl")
include("DistSSHKitQueue/cli.jl")
include("DistSSHKitQueue/service.jl")

if VERSION >= v"1.12"
    Base.eval(@__MODULE__, :(@main))
end

end # module DistSSHKitQueue
