#!/usr/bin/env julia
# Developer tool: regenerate src/libnickel.jl from deps/nickel_lang.h
# Usage: julia --project=deps/ deps/generate_bindings.jl

using Clang
using Clang.Generators

cd(@__DIR__)

header = joinpath(@__DIR__, "nickel_lang.h")
if !isfile(header)
    error("deps/nickel_lang.h not found. Build the Nickel C API first.")
end

options = load_options(joinpath(@__DIR__, "generator.toml"))
ctx = create_context([header], get_default_args(), options)
build!(ctx)

println("Bindings generated at src/libnickel.jl")
