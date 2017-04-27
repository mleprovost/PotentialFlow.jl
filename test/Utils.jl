@testset "Utils" begin
    @testset "get" begin
        z = rand(Complex128)

        @get z (im, re)
        @test im == imag(z)
        @test re == real(z)

        @get z (re, im)
        @test im == imag(z)
        @test re == real(z)

        @get z (re, im) (r, i)
        @test i == imag(z)
        @test r == real(z)
    end

    @testset "MappedVector" begin
        x = [π, 0.0, π]
        y = Vortex.Utils.MappedVector(cos, x, Float64, 1)
        @test y[0] == -1.0
        @test y[1] == 1.0
        @test y[2] == -1.0

        buff = IOBuffer()
        show(buff, y)
        @test takebuf_string(buff) == "Array{Float64,1} → Base.#cos (0:2)"
    end
end
