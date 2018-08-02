struct DayAheadIndices <: AbstractModelIndices
    hours::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
    bids::Vector{Int}
    blockbids::Vector{Int}
    blocks::Vector{Int}
    hours_per_block::Vector{Vector{Int}}
end
plants(indices::DayAheadIndices) = indices.plants

function modelindices(data::DayAheadData, horizon::Horizon, areas::Vector{Area}, rivers::Vector{River})
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(hydrodata(data),areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    bids = collect(1:length(data.bidprices))
    blockbids = collect(1:length(data.bidprices)-2)
    hours_per_block = [collect(h:ending) for h in hours for ending in hours[h+data.regulations.blockminlength-1:end]]
    blocks = collect(1:length(hours_per_block))
    return DayAheadIndices(hours, plants, segments, bids, blockbids, blocks, hours_per_block)
end
