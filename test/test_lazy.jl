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

    @testset "Array access" begin
        nickel_open("[10, 20, 30]") do cfg
            @test cfg[1] === Int64(10)
            @test cfg[2] === Int64(20)
            @test cfg[3] === Int64(30)
        end

        # Array of records (lazy)
        nickel_open("[{ x = 1 }, { x = 2 }]") do cfg
            @test cfg[1].x === Int64(1)
            @test cfg[2].x === Int64(2)
        end

        # Nested: record containing array
        nickel_open("{ items = [10, 20, 30] }") do cfg
            @test cfg.items[2] === Int64(20)
        end
    end

    @testset "collect" begin
        # Record
        nickel_open("{ a = 1, b = \"two\", c = true }") do cfg
            result = collect(cfg)
            @test result isa Dict{String, Any}
            @test result == nickel_eval("{ a = 1, b = \"two\", c = true }")
        end

        # Nested record
        nickel_open("{ x = { y = 42 } }") do cfg
            result = collect(cfg)
            @test result["x"]["y"] === Int64(42)
        end

        # Array
        nickel_open("[1, 2, 3]") do cfg
            result = collect(cfg)
            @test result == Any[1, 2, 3]
        end

        # Collect a sub-tree
        nickel_open("{ a = 1, b = { c = 2, d = 3 } }") do cfg
            sub = collect(cfg.b)
            @test sub == Dict{String, Any}("c" => 2, "d" => 3)
        end

        # Primitive passthrough
        nickel_open("42") do cfg
            @test collect(cfg) === Int64(42)
        end
    end

    @testset "keys and length" begin
        nickel_open("{ a = 1, b = 2, c = 3 }") do cfg
            k = keys(cfg)
            @test k isa Vector{String}
            @test sort(k) == ["a", "b", "c"]
            @test length(cfg) == 3
        end

        nickel_open("[10, 20, 30, 40]") do cfg
            @test length(cfg) == 4
        end

        # keys on non-record throws
        nickel_open("[1, 2]") do cfg
            @test_throws ArgumentError keys(cfg)
        end
    end

    @testset "File evaluation" begin
        mktempdir() do dir
            # Simple file
            f = joinpath(dir, "config.ncl")
            write(f, "{ host = \"localhost\", port = 8080 }")
            nickel_open(f) do cfg
                @test cfg.host == "localhost"
                @test cfg.port === Int64(8080)
            end

            # File with imports
            shared = joinpath(dir, "shared.ncl")
            write(shared, "{ version = \"1.0\" }")
            main = joinpath(dir, "main.ncl")
            write(main, """
let s = import "shared.ncl" in
{ app_version = s.version, name = "myapp" }
""")
            nickel_open(main) do cfg
                @test cfg.app_version == "1.0"
                @test cfg.name == "myapp"
            end
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
