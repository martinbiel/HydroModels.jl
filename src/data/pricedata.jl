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

    function (::Type{PriceData})(P::AbstractMatrix,horizon::Horizon)
        T = eltype(P)
        n_in_rows = div(size(P,1),nhours(horizon))
        n_cols = size(P,2)
        available = n_in_rows*n_cols
        curves = Vector{PriceCurve{T}}(available)
        for i = 1:n_cols
            for j = 1:n_in_rows
                curves[(i-1)*n_in_rows+j] = PriceCurve(P[((j-1)*nhours(horizon)+1):j*nhours(horizon),i])
            end
        end
        return new{T}(curves)
    end

    function (::Type{PriceData})(P::AbstractVector,horizon::Horizon)
        T = eltype(P)
        available = div(length(P),nhours(horizon))
        curves = Vector{PriceCurve{T}}(undef, available)
        for i = 1:available
            curves[i] = PriceCurve(P[((i-1)*nhours(horizon)+1):i*nhours(horizon)])
        end
        return new{T}(curves)
    end
end
ncurves(pricedata::PriceData) = length(pricedata.curves)
horizon(pricedata::PriceData,i::Integer) = horizon(pricedata[i])
expected(pricedata::PriceData) = mean(expected.(pricedata.curves))

Base.getindex(pricedata::PriceData,i::Integer) = pricedata.curves[i]

function PriceData(filename::String)
    P = readdlm(filename, ',')
    return PriceData(convert(Matrix{Float64},P[2:end,:]))
end

function PriceData(filename::String,curvehorizon::Horizon)
    P = readdlm(filename, ',')
    return PriceData(convert(Matrix{Float64},P[2:end,:]),curvehorizon)
end

function NordPoolPriceData(filename::String,curvehorizon::Horizon,area::Integer)
    P = readdlm(filename, ',')
    return PriceData(convert(Vector{Float64},P[4:end,3+area]),curvehorizon)
end
