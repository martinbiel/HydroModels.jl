struct TradeRegulations
    lot::Real               # Trade lot in MWh
    dayaheadfee::Real       # Fee for day ahead trades (EUR/MWh)
    intradayfee::Real       # Fee for intraday trades (EUR/MWh)
    blocklimit::Real        # Maximum volume (MWh) in block orders
    blockminlength::Integer # Minimum amount of consecutive hours in block orders
    imbalancelimit::Real    # Maximum volume (MWh) that has to be settled in the intraday market
    lowerorderlimit::Real   # Lower technical order price limit (EUR)
    upperorderlimit::Real   # Upper technical order price limit (EUR)
end
NordPoolRegulations() = TradeRegulations(0.1,0.04,0.11,500,3,200,-500,3000)

struct DayAheadScenario
    π::Real                 # Scenario probability
    ρ::AbstractVector       # Market price per hour
    ρ̅::AbstractVector       # Average market price per block
end

function expected(scenarios::Vector{DayAheadScenario})
    π = 1
    ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:24]
    ρ̅ = mean([s.ρ̅ for s in scenarios])
    return DayAheadScenario(π,ρ,ρ̅)
end

penalty(scenario::DayAheadScenario,t) = 1.1*scenario.ρ[t]
reward(scenario::DayAheadScenario,t) = 0.9*scenario.ρ[t]
