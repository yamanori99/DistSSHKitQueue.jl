"""Capture CLI stdio the way DistSSHKit tests do.

Julia 1.12 `redirect_stdout` does not accept `IOBuffer`. Kit uses `mktemp`
(`test/unit/DistSSHKit/main_dispatch.jl`). Redirecting also makes
`DistSSHKit.use_colors()` false (`stdout isa TTY`), so ANSI does not leak
into `Pkg.test()` output.
"""
function capture_stdio(f)
    mktemp() do out_path, out_io
        mktemp() do err_path, err_io
            value = redirect_stdout(out_io) do
                redirect_stderr(err_io) do
                    f()
                end
            end
            flush(out_io)
            flush(err_io)
            return value, read(out_path, String), read(err_path, String)
        end
    end
end
