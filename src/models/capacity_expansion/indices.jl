struct CapacityExpansionIndices <: AbstractModelIndices
    periods::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
    levels::Vector{Int}
end
plants(indices::CapacityExpansionIndices) = indices.plants

function HydroModels.modelindices(data::CapacityExpansionData, horizon::Horizon; areas::Vector{Area} = [0], rivers::Vector{River} = [:All])
    periods = collect(1:num_periods(data.resolution, horizon))
    plants = plants_in_areas_and_rivers(hydrodata(data), areas, rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    levels = collect(1:length(data.investment_levels))
    return CapacityExpansionIndices(periods, plants, segments, levels)
end
