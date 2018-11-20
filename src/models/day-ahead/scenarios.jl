@scenario DayAhead = begin
    ρ::PriceCurve{Float64}

    @zero begin
        return DayAheadScenario(PriceCurve(zeros(24)), probability = 1.0)
    end

    @expectation begin
        π = 1.0
        ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:nhours(Day())]
        return DayAheadScenario(PriceCurve(ρ), probability = 1.0)
    end
end

function DayAheadScenarios(data::DayAheadData, npricecurves::Integer)
    scenarios = Vector{DayAheadScenario}(npricecurves)
    π = 1/npricecurves
    for i in 1:npricecurves
        ρ = data.pricedata[i]
        scenarios[i] = DayAheadScenario(ρ, probability = π)
    end
    return scenarios
end

penalty(scenario::DayAheadScenario,t) = 1.1*scenario.ρ[t]
reward(scenario::DayAheadScenario,t) = 0.9*scenario.ρ[t]

@sampler DayAhead = begin
    distribution::FullNormal

    function (::Type{DayAheadSampler})(data::DayAheadData)
        distribution = fit(MvNormal,reduce(hcat,[c.λ for c in data.pricedata.curves]))
        return new(distribution)
    end

    @sample begin
        ρ = rand(sampler.distribution,1)[:]
        while any(ρ .<= 0)
            # Ensure that prices are never negative
            ρ = rand(sampler.distribution,1)[:]
        end
        π = pdf(sampler.distribution,ρ)[1]
        return DayAheadScenario(PriceCurve(ρ), probability = π)
    end
end

# struct DayAheadSampler <: AbstractSampler{DayAheadScenario}
#     distribution::FullNormal

#     function (::Type{DayAheadSampler})(data::DayAheadData)
#         distribution = fit(MvNormal,reduce(hcat,[c.λ for c in data.pricedata.curves]))
#         return new(distribution)
#     end
# end

# function (sampler::DayAheadSampler)()
#     ρ = rand(sampler.distribution,1)[:]
#     while any(ρ .<= 0)
#         # Ensure that prices are never negative
#         ρ = rand(sampler.distribution,1)[:]
#     end
#     π = pdf(sampler.distribution,ρ)[1]
#     return DayAheadScenario(π,PriceCurve(ρ))
# end
