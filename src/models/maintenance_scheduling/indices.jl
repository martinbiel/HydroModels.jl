struct MaintenanceSchedulingIndices <: AbstractModelIndices
    hours::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
end
plants(indices::MaintenanceSchedulingIndices) = indices.plants

function HydroModels.modelindices(data::MaintenanceSchedulingData, horizon::Horizon; areas::Vector{Area} = [0], rivers::Vector{River} = [:All])
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(hydrodata(data),areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    return MaintenanceSchedulingIndices(hours, plants, segments)
end
