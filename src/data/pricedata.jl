struct PriceCurve{T <: AbstractFloat} <: AbstractVector{T}
    λ::Vector{T}

    function (::Type{PriceCurve})(λ::AbstractVector)
        T = eltype(λ)
        return new{T}(λ)
    end
end
Base.start(curve::PriceCurve) = start(curve.λ)
Base.next(curve::PriceCurve, i) = next(curve.λ, i)
Base.done(curve::PriceCurve, i) = done(curve.λ, i)
Base.length(curve::PriceCurve) = length(curve.λ)
Base.size(curve::PriceCurve) = size(curve.λ)
@inline function Base.getindex(curve::PriceCurve, I...)
    @boundscheck checkbounds(curve.λ, I...)
    @inbounds return curve.λ[I...]
end
function Base.getindex(curve::PriceCurve, horizon::Horizon)
    horizon <= HydroModels.horizon(curve) || throw(BoundsError(curve,horizon))
    return PriceCurve(curve.λ[1:nhours(horizon)])
end
@inline function Base.setindex!(curve::PriceCurve, x, I...)
    @boundscheck checkbounds(curve.λ, I...)
    @inbounds curve.λ[I...] = x
end
Base.indices(curve::PriceCurve) = indices(curve.λ)
Base.linearindices(curve::PriceCurve) = linearindices(curve.λ)
Base.IndexStyle(::Type{<:PriceCurve}) = Base.IndexLinear()

horizon(curve::PriceCurve) = Horizon(length(curve.λ))
expected(curve::PriceCurve) = mean(curve.λ)

struct PriceData{T <: AbstractFloat}
    curves::Vector{PriceCurve{T}}

    function (::Type{PriceData})(P::AbstractMatrix)
        T = eltype(P)
        n = size(P,2)
        curves = Vector{PriceCurve{T}}(n)
        for i = 1:n
            curves[i] = PriceCurve(P[:,i])
        end
        return new{T}(curves)
    end
end
ncurves(pricedata::PriceData) = length(pricedata.curves)
horizon(pricedata::PriceData,i::Integer) = horizon(pricedata[i])
expected(pricedata::PriceData) = mean(expected.(pricedata.curves))

Base.getindex(pricedata::PriceData,i::Integer) = pricedata.curves[i]

function PriceData(filename::String)
    P = readcsv(filename)
    return PriceData(convert(Matrix{Float64},P[2:end,:]))
end
