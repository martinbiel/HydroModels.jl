@with_kw struct TradeRegulations{T <: AbstractFloat}
    lot::T = 0.1                  # Trade lot in MWh
    dayaheadfee::T = 0.04         # Fee for day ahead trades (EUR/MWh)
    intradayfee::T = 0.11         # Fee for intraday trades (EUR/MWh)
    blocklimit::T = 500.0         # Maximum volume (MWh) in block orders
    blockminlength::Int = 3       # Minimum amount of consecutive hours in block orders
    imbalancelimit::T = 200.0     # Maximum volume (MWh) that has to be settled in the intraday market
    lowerorderlimit::T = -500.0   # Lower technical order price limit (EUR)
    upperorderlimit::T = 3000.0   # Upper technical order price limit (EUR)
end
NordPoolRegulations() = TradeRegulations{Float64}()

struct DayAheadIndices <: AbstractModelIndices
    hours::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
    bids::Vector{Int}
    blockbids::Vector{Int}
    blocks::Vector{Int}
    hours_per_block::Vector{Vector{Int}}
end
plants(indices::ShortTermIndices) = indices.plants

struct DayAheadData{T <: AbstractFloat}
    plantdata::HydroModelData{T,2}
    pricedata::PriceData{T}
    regulations::TradeRegulations{T}
    bidprices::Vector{T}

    function (::Type{DayAheadData})(plantdata::HydroPlantCollection{T,2},pricedata::PriceData{T},regulations::TradeRegulations{T},bidprices::Vector{T}) where T <: AbstractFloat
        return new{T}(plantdata,pricedata,regulations,bidprices)
    end
end
function DayAheadData(plantfilename::String,pricefilename::PriceCurve)
    regulations = NordPoolRegulations()
    ShortTermData(HydroPlantCollection(plantfilename),PriceData(pricefilename),regulations,bidprices(regulations))
end

function bidprices(pricedata::Pricedata,regulations::TradeRegulations)
    λ_max = 1.1*maximum(pricedata.λ[1:24,1:nscenarios(model)])
    λ_min = 0.9*minimum(pricedata.λ[1:24,1:nscenarios(model)])
    bidprices = collect(linspace(λ_min,λ_max,3))
    prepend!(bidprices,regulations.lowerorderlimit)
    push!(bidprices,regulations.upperorderlimit)
    return bidprices
end

function modelindices(horizon::Horizon, data::DayAheadData, scenarios::Vector{<:AbstractScenarioData}, areas::Vector{Area}, rivers::Vector{River})
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(data.plantdata,areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    bids = collect(1:length(data.bidprices))
    blockbids = collect(1:length(data.bidprices)-2)
    hours_per_block = [collect(h:ending) for h in hours for ending in hours[h+data.regulations.blockminlength-1:end]]
    blocks = collect(1:length(model.hours_per_block))
    return DayAheadIndices(hours, plants, segments, bids, blockbids, hours_per_block, blocks)
end

struct DayAheadScenario{T <: AbstractFloat} <: AbstractScenarioData
    π::T                 # Scenario probability
    ρ::Vector{T}         # Market price per hour
    ρ̅::Vector{T}         # Average market price per block

    function (::Type{DayAheadScenario})(π::AbstractFloat,ρ::AbstractVector,ρ̅::AbstractVector)
        T = promote_type(typeof(π),eltype(ρ),eltype(ρ̅),Float32)
        return new{T}(π,ρ,ρ̅)
    end
end

function StochasticPrograms.expected(scenarios::Vector{DayAheadScenario})
    π = 1.0
    ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:24]
    ρ̅ = mean([s.ρ̅ for s in scenarios])
    return DayAheadScenario(π,ρ,ρ̅)
end

penalty(scenario::DayAheadScenario,t) = 1.1*scenario.ρ[t]
reward(scenario::DayAheadScenario,t) = 0.9*scenario.ρ[t]

include("orderstrategy.jl")
include("day_ahead_model.jl")
