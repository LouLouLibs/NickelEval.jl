using NickelEval
using Test

@testset "NickelEval.jl" begin
    if check_ffi_available()
        include("test_eval.jl")
        include("test_lazy.jl")
    else
        @warn "FFI library not available, skipping tests. Place libnickel_lang in deps/"
        @test_skip "FFI not available"
    end
end
