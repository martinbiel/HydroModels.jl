struct PriceCurve{T <: AbstractFloat} <: AbstractVector{T}
    λ::Vector{T}

    function (::Type{PriceCurve})(λ::AbstractVector)
        T = eltype(λ)
        return new{T}(λ)
    end
end
Base.iterate(curve::PriceCurve) = iterate(curve.λ)
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
Base.axes(curve::PriceCurve) = axes(curve.λ)
Base.IndexStyle(::Type{<:PriceCurve}) = Base.IndexLinear()

horizon(curve::PriceCurve) = Horizon(length(curve.λ))
mean_price(curve::PriceCurve) = mean(curve.λ)

struct PriceData{T <: AbstractFloat}
    curves::Dict{Int, PriceCurve{T}}

    function PriceData(curves::Dict{Int, PriceCurve{T}}) where T <: AbstractFloat
        return new{T}(curves)
    end
end

ncurves(pricedata::PriceData) = length(pricedata.curves)
horizon(pricedata::PriceData,i::Integer) = horizon(first(pricedata))
mean_price(pricedata::PriceData) = mean([mean_price(c) for (d,c) in pricedata.curves])
Base.getindex(pricedata::PriceData, i::Integer) = pricedata.curves[i]
