struct WaterValueCut{T <: AbstractFloat}
    plant_indices::Dict{Plant, Int}
    coeffs::Vector{T}
    lb::T
    indices::Vector{Int}

    function WaterValueCut(plant_indices::Dict{Plant, Int}, coeffs::Vector{T}, lb::T, indices::Vector{Int}) where T <: AbstractFloat
        new{T}(plant_indices, coeffs, lb, indices)
    end
end
function WaterValueCut(plants::Vector{Plant}, coeffs::Vector{T}, lb::T, indices::Vector{Int}) where T <: AbstractFloat
    length(plants) == length(coeffs) || error("Inconsistent number of coefficients and plants")
    plant_indices = Dict{Plant, Int}()
    for (i,p) in enumerate(plants)
        plant_indices[p] = i
    end
    return WaterValueCut(plant_indices, coeffs, lb, indices)
end
function Base.getindex(cut::WaterValueCut, plant::Plant)
    haskey(cut.plant_indices, plant) || error("$plant not present in water value cut")
    return cut.coeffs[cut.plant_indices[plant]]
end
function cut_lb(cut::WaterValueCut)
    return cut.lb
end
function cut_indices(cut::WaterValueCut)
    return cut.indices
end
function (cut::WaterValueCut)(M::AbstractVector)
    length(M) == length(cut.coeffs) || error("Inconsistent number of coefficients and reservoir values")
    return cut.lb-cut.coeffs⋅M
end

struct PolyhedralWaterValue{T <: AbstractFloat}
    cuts::Vector{WaterValueCut{T}}
    nindices::Int

    function PolyhedralWaterValue(cuts::Vector{WaterValueCut{T}}, nindices::Int) where T <: AbstractFloat
        return new{T}(cuts, nindices)
    end
end

# function PolyhedralWaterValue(plants::Vector{Plant}, values::Matrix{T}) where T <: AbstractFloat
#     n = size(values, 2)
#     cuts = Vector{WaterValueCut{T}}(undef, n)
#     for i = 1:n
#         cuts[i] = WaterValueCut(plants, values[1:end-1, i], values[end, i])
#     end
#     return PolyhedralWaterValue(cuts)
# end

# function PolyhedralWaterValue(plantfilename::String, watervaluefilename::String)
#     plants = Symbol.(readdlm(plantfilename, ',', String))[:]
#     values = readdlm(watervaluefilename, ',')
#     return PolyhedralWaterValue(plants, values)
# end

# function PolyhedralWaterValue(plants::Vector{Plant}, watervaluefilename::String)
#     values = readdlm(watervaluefilename, ',')
#     return PolyhedralWaterValue(plants, values)
# end

function PolyhedralWaterValue(filename::String)
    cuts, nindices = load_watervalue(filename)
    cuts = convert(Vector{WaterValueCut{Float64}}, cuts)
    return PolyhedralWaterValue(cuts, nindices)
end

function (water_value::PolyhedralWaterValue)(M::AbstractVector)
    values = [c(M) for c in water_value.cuts]
    return -maximum(values)
end
function cuts(water_value::PolyhedralWaterValue)
    return water_value.cuts
end
function ncuts(water_value::PolyhedralWaterValue)
    return length(water_value.cuts)
end
function nindices(water_value::PolyhedralWaterValue)
    return water_value.nindices
end
function save_watervalue(water_value::PolyhedralWaterValue; filename::String = "water_value.bson")
    cuts = water_value.cuts
    nindices = water_value.nindices
    @save filename cuts nindices
    return nothing
end
function load_watervalue(filename::String)
    @load filename cuts nindices
    return cuts, nindices
end
function Base.getindex(water_value::PolyhedralWaterValue, c::Int)
    0 <= c <= ncuts(water_value) || error("$c outside range of cuts")
    return water_value.cuts[c]
end
function Base.show(io::IO, water_value::PolyhedralWaterValue)
    print(io, "Polyhedral water value approximation consisting of $(ncuts(water_value)) linear cuts")
end
