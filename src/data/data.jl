include("horizon.jl")
include("segmenter.jl")
include("plantdata.jl")
include("pricedata.jl")

Scenario = Int

abstract type AbstractModelIndices end
plants(indices::AbstractModelIndices) = error("Not implemented.")

abstract type AbstractModelData end

modelindices(horizon::Horizon,data::AbstractModelData,args...) = error("No definition of modelindices for ", typeof(data))
modelindices(horizon::Horizon,data::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},args...) = error("No definition of modelindices for ", typeof(data), " and ", eltype(scenarios))
