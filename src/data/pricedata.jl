struct PriceCurve{N,T <: AbstractFloat} <: AbstractVector{T}
    λ::Vector{T}

    function PriceCurve(λ::AbstractVector)
        N = length(λ)
        T = eltype(λ)
        return new{N,T}(λ)
    end
end
Base.iterate(curve::PriceCurve) = iterate(curve.λ)
Base.length(curve::PriceCurve{N}) where N = N
Base.size(curve::PriceCurve) = size(curve.λ)
@inline function Base.getindex(curve::PriceCurve, I...)
    @boundscheck checkbounds(curve.λ, I...)
    @inbounds return curve.λ[I...]
end
function Base.zero(::Type{PriceCurve{N,T}}) where {N, T <: AbstractFloat}
    return PriceCurve(zeros(T,N))
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
horizon(curve::PriceCurve{N}) where N = Horizon(N)
mean_price(curve::PriceCurve) = mean(curve.λ)

function Statistics.mean(price_curves::Vector{PriceCurve{N,T}}) where {N, T <: AbstractFloat}
    λ̄ = [mean([curve[i] for curve in price_curves]) for i in 1:N]
    return PriceCurve(λ̄)
end

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
