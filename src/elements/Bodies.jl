module Bodies

using DocStringExtensions
using SchwarzChristoffel


using ..Points
using ..Blobs

using ..Elements
using ..RigidBodyMotions

import ..Elements: position, impulse, circulation
import ..Motions: induce_velocity, induce_velocity!, mutually_induce_velocity!, self_induce_velocity,
                  self_induce_velocity!, allocate_velocity, advect!, streamfunction
import SchwarzChristoffel: Polygon, ConformalMap, PowerMap

import ..Utils:@get, MappedVector

export ConformalBody,Polygon,enforce_no_flow_through!,normal,tangent


mutable struct ConformalBody <: Element
    # This mostly serves as a wrapper for the map. The map m contains most
    # geometric data for the body already
    "conformal map that defines the body shape"
    m::ConformalMap
    "inverse of the conformal map"
    minv::InverseMap
    "Jacobian of the conformal map"
    dm::DerivativeMap
    "centroid"
    c::Complex128
    "orientation angle (in radians)"
    α::Float64
    "control points in inertial coordinates in physical plane"
    zs::Vector{Complex128}
    "translational velocity"
    ċ::Complex128
    "angular velocity"
    α̇::Float64
    "image singularities"
    img::Vector{Point}
end
@kind ConformalBody Singleton

ConformalBody(m::ConformalMap,c,α) =
        ConformalBody(m,InverseMap(m),DerivativeMap(m),
        Complex128(c),α,rigid_transform(m.z,Complex128(c),α),Complex128(0),0.0,
        Points.Point{Float64}[])

ConformalBody(m::ConformalMap) = ConformalBody(m,Complex128(0),0.0)

"""
    ConformalBody <: Elements.Element

Generates a body from a conformal map. This might be a Schwarz-Christoffel map,
in which case the constructor is supplied a polygon, or it might be a power-
series map, in which case the constructor is given a set of complex coefficients.

# Example

```jldoctest
julia> p = Bodies.Polygon([-1.0,0.2,1.0,-1.0],[-1.0,-1.0,0.5,1.0])
Polygon with 4 vertices at
             (-1.0,-1.0) (0.2,-1.0) (1.0,0.5) (-1.0,1.0)
             interior angles/π = [0.5, 0.656, 0.422, 0.422]

julia> Bodies.ConformalBody(p)
Body generated by: Schwarz-Christoffel map of unit circle to exterior of polygon with 4 vertices

  centroid at 0.0 + 0.0im
  angle 0.0

julia> a1 = 1; b1 = 0.1; ccoeff = Complex128[0.5(a1+b1),0,0.5(a1-b1)];

julia> b = Bodies.ConformalBody(ccoeff,Complex128(1.0),π/4)
Body generated by: Power series map

  centroid at 1.0 + 0.0im
  angle 0.7854
```
"""
function ConformalBody(p::Polygon,x...)
  m = ExteriorMap(p)
  ConformalBody(m,x...)
end

function ConformalBody(ccoeff::Vector{Complex128},x...)
  m = PowerMap(ccoeff)
  ConformalBody(m,x...)
end

ConformalBody() = ConformalBody(PowerMap(Complex128(1)))

function Base.show(io::IO, b::ConformalBody)
    println(io, "Body generated by: $(b.m)")
    println(io, "  centroid at $(round(b.c,4))")
    println(io, "  angle $(round(b.α,4))")
end


rigid_transform(z̃::Union{Complex128,Vector{Complex128}},
                c::Complex128,α::Float64) = c + z̃*exp(im*α)


Base.length(b::ConformalBody) = b.m.N

"""
    normal(ζ::Complex128,v::Complex128,b::ConformalBody) -> Float64

Returns the normal component of the complex vector `v` in the physical plane at
a point on the surface of body `b`. This surface point is specified by its
pre-image `ζ` on the unit circle.

# Example

```jldoctest
julia> p = Polygon([-1.0,1.0,1.0,-1.0],[-1.0,-1.0,1.0,1.0]);

julia> b = ConformalBody(p);

julia> Bodies.normal(exp(im*0),exp(im*π/4),b)
0.7071067811865472
```
"""
function normal(ζ::Complex128,v::Complex128,b::ConformalBody)
  dz, ddz = b.dm(ζ)
  real(v*conj(ζ*dz)/abs(dz))
end

"""
    tangent(ζ::Complex128,v::Complex128,b::ConformalBody) -> Float64

Returns the (counter-clockwise) tangent component of the complex vector `v`
in the physical plane at a point on the surface of body `b`. This surface point
is specified by its pre-image `ζ` on the unit circle.

# Example

```jldoctest
julia> p = Polygon([-1.0,1.0,1.0,-1.0],[-1.0,-1.0,1.0,1.0]);

julia> b = ConformalBody(p);

julia> Bodies.tangent(exp(im*0),exp(im*π/4),b)
0.7071067811865472
```
"""
function tangent(ζ::Complex128,v::Complex128,b::ConformalBody)
  dz, ddz = b.dm(ζ)
  imag(v*conj(ζ*dz)/abs(dz))
end

function allocate_conftransform(::ConformalBody)
    nothing
end

Elements.conftransform(ζ::Complex128,b::ConformalBody) = b.c + b.m(ζ)*exp(im*b.α)

Elements.conftransform(s::T,b::ConformalBody) where T <: Union{Blob,Point} =
                T(Elements.conftransform(s.z,b),s.S)

function allocate_inv_conftransform(::ConformalBody)
    nothing
end

Elements.inverse_conftransform(z::Complex128,b::ConformalBody) = b.minv((z-b.c)*exp(-im*b.α))

Elements.inverse_conftransform(s::T,b::ConformalBody) where T <: Union{Blob,Point} =
                T(Elements.inverse_conftransform(s.z,b),s.S)

function allocate_jacobian(::ConformalBody)
    nothing
end

function Elements.jacobian(ζ::Complex128,b::ConformalBody)
  dz, ddz = b.dm(ζ)
  return dz
end

Elements.jacobian(s::T,b::ConformalBody) where T <: Union{Blob,Point} =
                Elements.jacobian(s.z,b)


function allocate_velocity(::ConformalBody)
    warn("Body kinematics should be initialized manually.  This simply returns a stationary motion")
    RigidBodyMotion(0.0, 0.0)
end

function self_induce_velocity!(motion, ::ConformalBody, t)
    motion.ċ, motion.c̈, motion.α̇ = motion.kin(t)
    motion
end

function induce_velocity(ζ::Complex128, b::ConformalBody, t)
  # Also, this is the velocity in the circle plane, not physical plane
    @get b (m, minv, dm, c, α, ċ, α̇, img)
    @get m (ps,)
    @get ps (ccoeff,dcoeff)

    #ζ = minv(z)

    dz̃, ddz̃ = dm(ζ)

    c̃̇ = ċ*exp(-im*α)

    ζ⁻ˡ = 1/ζ^2
    w̃ = c̃̇*conj(ccoeff[1])*ζ⁻ˡ + conj(c̃̇)*(dz̃-ccoeff[1])
    for l = 2:length(dcoeff)
        w̃ += im*(l-1)*α̇*dcoeff[l]*ζ⁻ˡ
        ζ⁻ˡ /= ζ
    end
    # need to return the velocity u+iv, not the usual conjugate velocity
    w̃ = conj(w̃)

    # add the influence of images
    w̃ += induce_velocity(ζ,img,t)

    return w̃

end

function induce_velocity(target::T,b::ConformalBody, t) where T <: Union{Blob,Point}
  # Here we apply Routh correction and adjust velocity relative to body. Note that
  # all singularity positions are interpreted in circle plane
  @get b (m, minv, dm, c, α, ċ, α̇, img)

  w̃ = induce_velocity(target.z,b,t)

  z̃ = m(target.z)
  dz̃, ddz̃ = dm(target.z)
  c̃̇ = ċ*exp(-im*α)
  w̃ += target.S*conj(ddz̃)/(4π*im*conj(dz̃))
  w̃ /=conj(dz̃)
  w̃ -= c̃̇ + im*α̇*z̃

  return w̃/dz̃

end

include("bodies/boundary_conditions.jl")

function Elements.streamfunction(ζ::Complex128, b::ConformalBody)
  @get b (m, minv, c, α, ċ, α̇, img)
  @get m (ps,)
  @get ps (ccoeff,dcoeff)

  #ζ = minv(z)
  z̃ = m(ζ)

  c̃̇ = ċ*exp(-im*α)

  ζ⁻ˡ = 1/ζ
  F = -c̃̇*conj(ccoeff[1])*ζ⁻ˡ + conj(c̃̇)*(z̃-ccoeff[1]*ζ-ccoeff[2]) - im*α̇*dcoeff[1]
  for l = 2:length(dcoeff)
      F -= im*α̇*dcoeff[l]*ζ⁻ˡ
      ζ⁻ˡ /= ζ
  end

  return imag(F) + streamfunction(ζ,img)

end

###

function induce_velocity!(ws::Vector, b::ConformalBody, sources::T, t) where T <: Union{Tuple, AbstractArray}
    for source in sources
        induce_velocity!(ws, b, source, t)
    end
    ws
end
function induce_velocity(b::ConformalBody, src, t)
    out = allocate_velocity(b.zs)
    induce_velocity!(out, b, src, t)
end

function induce_velocity!(ws::Vector, b::ConformalBody, src, t)
    _singular_velocity!(ws, b, Elements.unwrap(src), t,
                        kind(Elements.unwrap_src(src)))
end

function _singular_velocity!(ws, b, src::Blob{T}, t, ::Type{Singleton}) where T
    induce_velocity!(ws, b.zs, Point{T}(src.z, src.S), t)
end

function _singular_velocity!(ws, b, src, t, ::Type{Singleton})
    induce_velocity!(ws, b.zs, src, t)
end

function _singular_velocity!(ws, b, src, t, ::Type{Group})
    for i in eachindex(src)
        induce_velocity!(ws, b, src[i], t)
    end
    ws
end

induce_velocity!(m::RigidBodyMotion, target::ConformalBody, source, t) = m

function advect!(body₊::ConformalBody, body₋::ConformalBody, ṗ::RigidBodyMotion, Δt)
    if body₊ != body₋
        body₊.m    = body₋.m
        body₊.minv    = body₋.minv
        body₊.dm   = body₋.dm
        if length(body₊.zs) != length(body₋.zs)
            resize!(body₊.zs, length(body₋.zs))
        end
        body₊.zs   .= body₋.zs
    end
    body₊.c = body₋.c + ṗ.ċ*Δt
    body₊.α = body₋.α + ṗ.α̇*Δt

    @get body₊ (m, c, α)

    @. body₊.zs = rigid_transform(m.z,Complex128(c),α)

    return body₊
end


#= stuff to contemplate adding back in





function streamfunction(ζ::Complex128, b::PowerBody, Winf::Complex128, t)
  @get b (C, D, α, c)

  W̃inf = Winf*exp(im*α)

  F = W̃inf*C[1]*ζ + conj(W̃inf*C[1])/ζ

  imag(F)

end

=#



#=

function impulse(p::Plate)
    @get p (c, B₀, α, Γ, L, A)
    -im*c*Γ - exp(im*α)*π*(0.5L)^2*im*(A[0] - 0.5A[2] - B₀)
end




normal(z, α) = imag(exp(-im*α)*z)
tangent(z, α) = real(exp(-im*α)*z)







"""
    unit_impulse(src, plate::Plate)

Compute the impulse per unit circulation of `src` and its associated bound vortex sheet on `plate` (its image vortex)
`src` can be either a `Complex128` or a subtype of `Vortex.PointSource`.
"""
function unit_impulse(z::Complex128, plate::Plate)
    z̃ = 2(z - plate.c)*exp(-im*plate.α)/plate.L
    unit_impulse(z̃)
end
unit_impulse(z̃) = -im*(z̃ + real(√(z̃ - 1)*√(z̃ + 1) - z̃))
unit_impulse(src, plate::Plate) = unit_impulse(Elements.position(src), plate)

include("plates/boundary_conditions.jl")
include("plates/circulation.jl")
include("plates/force.jl")

doc"""
    surface_pressure(plate, motion, te_sys, Γs₋, Δt)

Compute the pressure difference across the plate along Chebyshev nodes.

!!! note
    The pressure difference across the bound vortex sheet is given by:
    ```math
        [p]_-^+
      = -\rho \left[ \frac{1}{2}(\boldsymbol{v}^+ + \boldsymbol{v}^-)
                   - \boldsymbol{v}_b
             \right]
             \cdot ( \boldsymbol{\gamma} \times \boldsymbol{\hat{n}})
        +\rho \frac{\mathrm{d}\Gamma}{\mathrm{d}t}
    ```
    where ``\rho`` is the fluid density, ``\boldsymbol{v}^\pm`` is the
    velocity on either side of the plate, ``\boldsymbol{v}_b`` is the local
    velocity of the plate, ``\boldsymbol{\gamma}`` is the bound vortex
    sheet strength, and ``\Gamma`` is the integrated circulation.
    We will compute ``\frac{\mathrm{d}\Gamma}{\mathrm{d}t}`` using finite
    differences.  So we will need the circulation along the plate from a
    previous time-step in order to compute the current pressure
    distribution.  We assume that value of circulation at the trailing
    edge of the plate is equal the the net circulation of all the vorticity
    that has been shed from the trailing edge.

# Arguments

- `plate`: we assume that the `Plate` structure that is passed in
  already enforces the no-flow-through condition
- `motion`: the motion of the plate used to compute ``\boldsymbol{v}_b``
- `te_sys`: the system of vortex elements representing the vorticity
  shed from the trailing edge of the plate
- `Γs₋`: the circulation along the plate's Chebyshev nodes, this
  should be equivalent to calling
  `Vortex.circulation(te_sys) .+ Vortex.bound_circulation(plate)`
  from a previous time-step.
- `Δt`: time-step used to compute ``\frac{\mathrm{d}\Gamma}{\mathrm{d}t}``
  using finite differences

# Returns

- `Δp`: the pressure difference across the plate along Chebyshev nodes
- `Γs₊`: the circulation along the plate at the current time-step
  (this value is used in computing the current `Δp` and can be used as
  the `Γs₋` for computing pressure differences at the **next** time-step)
"""
function surface_pressure(plate, motion, ambient_sys, Γs₋, Δt)
    @get plate (C, ss, α)

    Δp = strength(plate) .* (Chebyshev.firstkind(real.(C), ss) .- tangent(motion.ċ, α))

    Γs₊ = circulation(ambient_sys) .+ bound_circulation(plate)
    Δp .+= (Γs₊ .- Γs₋)./Δt

    Δp, Γs₊
end

"""
    edges(plate)

Return the coordinates of the leading and trailing edges

# Example

```jldoctest
julia> p = Plate(128, 1.0, 0, π/4)
Plate: N = 128, L = 1.0, c = 0.0 + 0.0im, α = 45.0ᵒ
       LESP = 0.0, TESP = 0.0

julia> Plates.edges(p)
(0.3535533905932738 + 0.35355339059327373im, -0.3535533905932738 - 0.35355339059327373im)
```
"""
edges(plate) = plate.zs[end], plate.zs[1]

include("plates/pressure.jl")
=#




end
