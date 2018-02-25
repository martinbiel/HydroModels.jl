include("horizon.jl")
include("segmenter.jl")
include("hydrodata.jl")
include("pricedata.jl")

Scenario = Int

abstract type AbstractModelIndices end

function plants(indices::AbstractModelIndices)
    :plants ∈ fieldnames(indices) || error("Model indices do not contain hydro plants")
    return indices.plants
end

abstract type AbstractModelData end

function hydrodata(data::AbstractModelData)
    :hydrodata ∈ fieldnames(data) || error("Model data does not contain hydro data")
    return data.hydrodata
end

modelindices(data::AbstractModelData,args...) = error("No definition of modelindices for ", typeof(data))
modelindices(data::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},args...) = error("No definition of modelindices for ", typeof(data), " and ", eltype(scenarios))
