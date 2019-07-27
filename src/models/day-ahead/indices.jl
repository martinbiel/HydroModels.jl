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

function HydroModels.modelindices(data::DayAheadData, horizon::Horizon; areas::Vector{Area} = [0], rivers::Vector{River} = [:All])
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(hydrodata(data),areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    bids = collect(1:length(data.bidlevels[1]))
    blockbids = collect(1:length(data.bidlevels[1])-2)
    hours_per_block = [collect(h:ending) for h in hours for ending in hours[h+data.regulations.blockminlength-1:end]]
    blocks = collect(1:length(hours_per_block))
    blocklevels = [blockbidlevel(b, data.bidlevels, hours_per_block) for b in blocks]
    maxperm = sortperm([b[4] for b in blocklevels])
    nblocks = div(data.regulations.nblockorders, length(data.bidlevels[1])-2)
    return DayAheadIndices(hours, plants, segments, bids, blockbids, collect(1:nblocks), hours_per_block[maxperm[end-nblocks+1:end]])
end

function blockbidlevel(b, bidlevels, hours_per_block)
    return mean([bidlevels[i][2:end-1] for i in hours_per_block[b]])
end
