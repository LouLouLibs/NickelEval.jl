@testset "Lazy Evaluation" begin
    @testset "nickel_open returns NickelValue" begin
        is_nickel_value = nickel_open("{ x = 1 }") do cfg
            cfg isa NickelValue
        end
        @test is_nickel_value
    end

    @testset "nickel_kind" begin
        nickel_open("{ x = 1 }") do cfg
            @test nickel_kind(cfg) == :record
        end
        nickel_open("[1, 2, 3]") do cfg
            @test nickel_kind(cfg) == :array
        end
        nickel_open("42") do cfg
            @test nickel_kind(cfg) == :number
        end
        nickel_open("\"hello\"") do cfg
            @test nickel_kind(cfg) == :string
        end
        nickel_open("true") do cfg
            @test nickel_kind(cfg) == :bool
        end
        nickel_open("null") do cfg
            @test nickel_kind(cfg) == :null
        end
    end

    @testset "Record field access" begin
        # getproperty (dot syntax)
        nickel_open("{ x = 42 }") do cfg
            @test cfg.x === Int64(42)
        end

        # getindex (bracket syntax)
        nickel_open("{ x = 42 }") do cfg
            @test cfg["x"] === Int64(42)
        end

        # Nested navigation
        nickel_open("{ a = { b = { c = 99 } } }") do cfg
            @test cfg.a.b.c === Int64(99)
        end

        # Mixed types in record
        nickel_open("{ name = \"test\", count = 42, flag = true }") do cfg
            @test cfg.name == "test"
            @test cfg.count === Int64(42)
            @test cfg.flag === true
        end

        # Null field
        nickel_open("{ x = null }") do cfg
            @test cfg.x === nothing
        end
    end

    @testset "show" begin
        nickel_open("{ x = 1, y = 2, z = 3 }") do cfg
            s = repr(cfg)
            @test occursin("record", s)
            @test occursin("3", s)
        end
        nickel_open("[1, 2]") do cfg
            s = repr(cfg)
            @test occursin("array", s)
            @test occursin("2", s)
        end
    end
end
