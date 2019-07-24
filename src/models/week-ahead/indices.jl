struct WeekAheadIndices <: AbstractModelIndices
    hours::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
end
plants(indices::WeekAheadIndices) = indices.plants

function HydroModels.modelindices(data::WeekAheadData, horizon::Horizon; areas::Vector{Area} = [0], rivers::Vector{River} = [:All])
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(hydrodata(data),areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    return WeekAheadIndices(hours, plants, segments)
end
