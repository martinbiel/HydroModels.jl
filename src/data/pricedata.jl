struct PriceCurve{T <: AbstractFloat}
    λ::Vector{T}

    function (::Type{PriceCurve})(λ::AbstractVector)
        T = eltype(λ)
        return new{T}(λ)
    end
end

function Base.getindex(curve::PriceCurve,t::Integer)
    return curve.λ[t]
end

horizon(pricedata::PriceCurve) = Horizon(length(pricedata.λ))
expected(pricedata::PriceCurve) = mean(pricedata.λ)

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

function PriceData(filename::String)
    P = readcsv(filename)
    return PriceData(convert(Matrix{Float64},P[2:end,:]))
end
