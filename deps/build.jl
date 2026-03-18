# Build script: compile Nickel's C API library from source
# Triggered by NICKELEVAL_BUILD_FFI=true

const NICKEL_VERSION = "1.16.0"
const NICKEL_REPO = "https://github.com/nickel-lang/nickel.git"

function library_name()
    if Sys.isapple()
        return "libnickel_lang.dylib"
    elseif Sys.iswindows()
        return "nickel_lang.dll"
    else
        return "libnickel_lang.so"
    end
end

function build_nickel_capi()
    cargo = Sys.which("cargo")
    if cargo === nothing
        @warn "cargo not found in PATH. Install Rust: https://rustup.rs/"
        return false
    end

    src_dir = joinpath(@__DIR__, "_nickel_src")

    # Clone or update — remove stale shallow clones to avoid fetch issues
    if isdir(src_dir)
        rm(src_dir; recursive=true, force=true)
    end
    @info "Cloning Nickel $(NICKEL_VERSION)..."
    run(`git clone --depth 1 --branch $(NICKEL_VERSION) $(NICKEL_REPO) $(src_dir)`)

    @info "Building Nickel C API library..."
    try
        cd(src_dir) do
            run(`cargo build --release -p nickel-lang --features capi`)
        end

        src_lib = joinpath(src_dir, "target", "release", library_name())
        dst_lib = joinpath(@__DIR__, library_name())

        if isfile(src_lib)
            cp(src_lib, dst_lib; force=true)
            @info "Library built: $(dst_lib)"

            # Also generate header if cbindgen is available
            if Sys.which("cbindgen") !== nothing
                cd(joinpath(src_dir, "nickel")) do
                    run(`cbindgen --config cbindgen.toml --crate nickel-lang --output $(joinpath(@__DIR__, "nickel_lang.h"))`)
                end
                @info "Header generated: $(joinpath(@__DIR__, "nickel_lang.h"))"
            end

            return true
        else
            @warn "Built library not found at $(src_lib)"
            return false
        end
    catch e
        @warn "Build failed: $(e)"
        return false
    end
end

if get(ENV, "NICKELEVAL_BUILD_FFI", "false") == "true"
    build_nickel_capi()
else
    @info "Skipping FFI build (set NICKELEVAL_BUILD_FFI=true to enable)"
end
