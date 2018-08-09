mutable struct DayAheadScenario{T <: AbstractFloat} <: AbstractScenarioData
    π::Probability       # Scenario probability
    ρ::PriceCurve{T}     # Market price per hour

    function (::Type{DayAheadScenario})(π::AbstractFloat,ρ::PriceCurve{T}) where T <: AbstractFloat
        return new{T}(π,ρ)
    end
end

function DayAheadScenarios(data::DayAheadData,npricecurves::Integer)
    scenarios = Vector{DayAheadScenario}(npricecurves)
    π = 1/npricecurves
    for i in 1:npricecurves
        ρ = data.pricedata[i]
        scenarios[i] = DayAheadScenario(π,ρ)
    end
    return scenarios
end

function StochasticPrograms.expected(scenarios::Vector{DayAheadScenario})
    isempty(scenarios) && return DayAheadScenario(1.0,PriceCurve(zeros(24)))
    π = 1.0
    ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:nhours(Day())]
    return DayAheadScenario(π,PriceCurve(ρ))
end

penalty(scenario::DayAheadScenario,t) = 1.1*scenario.ρ[t]
reward(scenario::DayAheadScenario,t) = 0.9*scenario.ρ[t]

struct DayAheadSampler <: AbstractSampler{DayAheadScenario}
    distribution::FullNormal

    function (::Type{DayAheadSampler})(data::DayAheadData)
        distribution = fit(MvNormal,reduce(hcat,[c.λ for c in data.pricedata.curves]))
        return new(distribution)
    end
end

function (sampler::DayAheadSampler)()
    ρ = rand(sampler.distribution,1)[:]
    while any(ρ .<= 0)
        # Ensure that prices are never negative
        ρ = rand(sampler.distribution,1)[:]
    end
    π = pdf(sampler.distribution,ρ)[1]
    return DayAheadScenario(π,PriceCurve(ρ))
end
