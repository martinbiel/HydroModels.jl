include("rivers.jl")
include("horizon.jl")
include("resolution.jl")
include("segmenter.jl")
include("hydrodata.jl")
include("water_value.jl")
include("pricedata.jl")
include("flowdata.jl")
include("forecaster.jl")

Scenario = Int

abstract type AbstractModelIndices end

function plants(indices::AbstractModelIndices)
    :plants ∈ fieldnames(typeof(indices)) || error("Model indices do not contain hydro plants")
    return indices.plants
end

abstract type AbstractModelData end

function hydrodata(data::AbstractModelData)
    :hydrodata ∈ fieldnames(typeof(data)) || error("Model data does not contain hydro data")
    return data.hydrodata
end

modelindices(data::AbstractModelData; kw...) = error("No definition of modelindices for ", typeof(data), " with arguments: ", args...)
