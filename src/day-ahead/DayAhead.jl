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

struct DayAheadScenario{T <: AbstractFloat}
    π::T                 # Scenario probability
    ρ::Vector{T}         # Market price per hour
    ρ̅::Vector{T}         # Average market price per block

    function (::Type{DayAheadScenario})(π::AbstractFloat,ρ::AbstractVector,ρ̅::AbstractVector)
        T = promote_type(typeof(π),eltype(ρ),eltype(ρ̅),Float32)
        return new{T}(π,ρ,ρ̅)
    end
end

function expected(scenarios::Vector{DayAheadScenario})
    π = 1.0
    ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:24]
    ρ̅ = mean([s.ρ̅ for s in scenarios])
    return DayAheadScenario(π,ρ,ρ̅)
end

penalty(scenario::DayAheadScenario,t) = 1.1*scenario.ρ[t]
reward(scenario::DayAheadScenario,t) = 0.9*scenario.ρ[t]

include("orderstrategy.jl")
include("day_ahead_model.jl")
