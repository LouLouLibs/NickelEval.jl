# FFI bindings for Nickel
#
# Native FFI bindings to a Rust wrapper around Nickel for high-performance evaluation
# without subprocess overhead.
#
# Two modes:
#   - nickel_eval_ffi: Uses JSON serialization (supports typed parsing)
#   - nickel_eval_native: Uses binary protocol (preserves Nickel types directly)
#
# Benefits over subprocess:
#   - No process spawn overhead
#   - Direct memory sharing
#   - Better performance for repeated evaluations

using Artifacts: artifact_hash
using LazyArtifacts

# Determine platform-specific library name
const LIB_NAME = if Sys.iswindows()
    "nickel_jl.dll"
elseif Sys.isapple()
    "libnickel_jl.dylib"
else
    "libnickel_jl.so"
end

# Find library path: try local deps/ first (custom builds, HPC clusters with old glibc),
# then fall back to pre-built artifact
function _find_library_path()
    # Try local deps/ folder first (custom builds override artifacts)
    local_path = joinpath(@__DIR__, "..", "deps", LIB_NAME)
    if isfile(local_path)
        return local_path
    end

    # Try artifact (Julia auto-selects platform based on arch/os in Artifacts.toml)
    try
        # @artifact_str triggers lazy download if needed
        artifact_dir = @artifact_str("libnickel_jl")
        lib_path = joinpath(artifact_dir, LIB_NAME)
        if isfile(lib_path)
            return lib_path
        end
    catch e
        # Artifact not available (platform not supported or download failed)
    end

    return nothing
end

const LIB_PATH = _find_library_path()

# Check if FFI library is available
const FFI_AVAILABLE = LIB_PATH !== nothing

# Binary protocol type tags (must match Rust definitions)
const TYPE_NULL   = 0x00
const TYPE_BOOL   = 0x01
const TYPE_INT    = 0x02
const TYPE_FLOAT  = 0x03
const TYPE_STRING = 0x04
const TYPE_ARRAY  = 0x05
const TYPE_RECORD = 0x06
const TYPE_ENUM   = 0x07

# C struct for native buffer (must match Rust NativeBuffer)
struct NativeBuffer
    data::Ptr{UInt8}
    len::Csize_t
end

"""
    check_ffi_available() -> Bool

Check if FFI bindings are available.
Returns true if the native library is compiled and available.
"""
function check_ffi_available()
    return FFI_AVAILABLE
end

"""
    nickel_eval_ffi(code::String) -> Any
    nickel_eval_ffi(code::String, ::Type{T}) -> T

Evaluate Nickel code using native FFI bindings via JSON serialization.
Returns the parsed result, optionally typed.

Throws `NickelError` if FFI is not available or if evaluation fails.

# Examples
```julia
julia> nickel_eval_ffi("1 + 2")
3

julia> result = nickel_eval_ffi("{ x = 1, y = 2 }")
julia> result.x  # dot-access supported
1

julia> nickel_eval_ffi("{ x = 1, y = 2 }", Dict{String, Int})
Dict{String, Int64}("x" => 1, "y" => 2)
```
"""
function nickel_eval_ffi(code::String)
    result_json = _eval_ffi_to_json(code)
    return JSON.parse(result_json)
end

function nickel_eval_ffi(code::String, ::Type{T}) where T
    result_json = _eval_ffi_to_json(code)
    if !hasmethod(JSON.parse, Tuple{String, Type})
        error("Typed parsing requires JSON.jl >= 1.0. " *
              "Either upgrade JSON.jl or use nickel_eval_native() which doesn't require JSON.")
    end
    return JSON.parse(result_json, T)
end

function _eval_ffi_to_json(code::String)
    _check_ffi_available()

    result_ptr = ccall((:nickel_eval_string, LIB_PATH),
                       Ptr{Cchar}, (Cstring,), code)

    if result_ptr == C_NULL
        _throw_ffi_error()
    end

    result_json = unsafe_string(result_ptr)
    ccall((:nickel_free_string, LIB_PATH), Cvoid, (Ptr{Cchar},), result_ptr)

    return result_json
end

"""
    nickel_eval_native(code::String) -> Any

Evaluate Nickel code using native FFI with binary protocol.
Returns Julia native types directly from Nickel's type system:

- Nickel `Number` (integer) → `Int64`
- Nickel `Number` (decimal) → `Float64`
- Nickel `String` → `String`
- Nickel `Bool` → `Bool`
- Nickel `null` → `nothing`
- Nickel `Array` → `Vector{Any}`
- Nickel `Record` → `Dict{String, Any}`

This preserves type information that would be lost through JSON serialization.

# Examples
```julia
julia> nickel_eval_native("42")
42

julia> typeof(nickel_eval_native("42"))
Int64

julia> typeof(nickel_eval_native("42.0"))
Float64

julia> nickel_eval_native("{ name = \"test\", count = 5 }")
Dict{String, Any}("name" => "test", "count" => 5)
```
"""
function nickel_eval_native(code::String)
    _check_ffi_available()

    buffer = ccall((:nickel_eval_native, LIB_PATH),
                   NativeBuffer, (Cstring,), code)

    if buffer.data == C_NULL
        _throw_ffi_error()
    end

    # Copy data before freeing (Rust owns the memory)
    data = Vector{UInt8}(undef, buffer.len)
    unsafe_copyto!(pointer(data), buffer.data, buffer.len)

    # Free the Rust buffer
    ccall((:nickel_free_buffer, LIB_PATH), Cvoid, (NativeBuffer,), buffer)

    # Decode the binary protocol
    return _decode_native(data)
end

"""
    nickel_eval_file_native(path::String) -> Any

Evaluate a Nickel file using native FFI with binary protocol.
This function supports Nickel imports - files can use `import` statements
to include other Nickel files relative to the evaluated file's location.

Returns Julia native types directly from Nickel's type system (same as `nickel_eval_native`).

# Examples
```julia
# config.ncl:
# let shared = import "shared.ncl" in
# { name = shared.project_name, version = "1.0" }

julia> nickel_eval_file_native("config.ncl")
Dict{String, Any}("name" => "MyProject", "version" => "1.0")
```

# Import Resolution
Imports are resolved relative to the file being evaluated:
- `import "other.ncl"` - relative to the file's directory
- `import "/absolute/path.ncl"` - absolute path
"""
function nickel_eval_file_native(path::String)
    _check_ffi_available()

    # Convert to absolute path for proper import resolution
    abs_path = abspath(path)

    buffer = ccall((:nickel_eval_file_native, LIB_PATH),
                   NativeBuffer, (Cstring,), abs_path)

    if buffer.data == C_NULL
        _throw_ffi_error()
    end

    # Copy data before freeing (Rust owns the memory)
    data = Vector{UInt8}(undef, buffer.len)
    unsafe_copyto!(pointer(data), buffer.data, buffer.len)

    # Free the Rust buffer
    ccall((:nickel_free_buffer, LIB_PATH), Cvoid, (NativeBuffer,), buffer)

    # Decode the binary protocol
    return _decode_native(data)
end

# Decode binary-encoded Nickel value to Julia native types.
function _decode_native(data::Vector{UInt8})
    io = IOBuffer(data)
    return _decode_value(io)
end

function _decode_value(io::IOBuffer)
    tag = read(io, UInt8)

    if tag == TYPE_NULL
        return nothing
    elseif tag == TYPE_BOOL
        return read(io, UInt8) != 0x00
    elseif tag == TYPE_INT
        return ltoh(read(io, Int64))  # little-endian to host
    elseif tag == TYPE_FLOAT
        return ltoh(read(io, Float64))
    elseif tag == TYPE_STRING
        len = ltoh(read(io, UInt32))
        bytes = read(io, len)
        return String(bytes)
    elseif tag == TYPE_ARRAY
        len = ltoh(read(io, UInt32))
        return Any[_decode_value(io) for _ in 1:len]
    elseif tag == TYPE_RECORD
        len = ltoh(read(io, UInt32))
        dict = Dict{String, Any}()
        for _ in 1:len
            key_len = ltoh(read(io, UInt32))
            key = String(read(io, key_len))
            dict[key] = _decode_value(io)
        end
        return dict
    elseif tag == TYPE_ENUM
        # Format: tag_len (u32) | tag_bytes | has_arg (u8) | [arg_value]
        tag_len = ltoh(read(io, UInt32))
        tag_name = Symbol(String(read(io, tag_len)))
        has_arg = read(io, UInt8) != 0x00
        arg = has_arg ? _decode_value(io) : nothing
        return NickelEnum(tag_name, arg)
    else
        error("Unknown type tag in binary protocol: $tag")
    end
end

function _check_ffi_available()
    if !FFI_AVAILABLE
        error("FFI library not available.\n\n" *
              "The FFI functions require a pre-built native library.\n" *
              "Use subprocess mode instead: nickel_eval() and nickel_eval_file()\n\n" *
              "To build locally (requires Rust):\n" *
              "  cd rust/nickel-jl && cargo build --release\n" *
              "  mkdir -p deps && cp target/release/$LIB_NAME ../../deps/")
    end
end

function _throw_ffi_error()
    error_ptr = ccall((:nickel_get_error, LIB_PATH), Ptr{Cchar}, ())
    if error_ptr != C_NULL
        throw(NickelError(unsafe_string(error_ptr)))
    else
        throw(NickelError("Nickel evaluation failed with unknown error"))
    end
end
