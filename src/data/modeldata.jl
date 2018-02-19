include("horizon.jl")
include("segmenter.jl")
include("plantdata.jl")
include("pricedata.jl")

abstract type AbstractModelIndices end
plants(indices::AbstractModelIndices) = error("Not implemented.")

abstract type AbstractModelData end
modelindices(data::AbstractModelData,horizon::Horizon,args...) = error("Not implemented.")
