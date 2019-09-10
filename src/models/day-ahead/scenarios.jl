@scenario DayAheadScenario = begin
    ρ::PriceCurve{24,Float64}
    Q̃::Inflows{typeof(Skellefteälven),Float64}

    @expectation begin
        ρ = mean([s.ρ for s in scenarios])
        Q̃ = mean([s.Q̃ for s in scenarios])
        return DayAheadScenario(ρ, Q̃, probability = 1.0)
    end
end

function penalty(scenario::DayAheadScenario, t)
    if 8 <= t <= 12 || 17 <= t <= 24
        return 1.15*scenario.ρ[t]
    else
        return 1.1*scenario.ρ[t]
    end
end
function penalty(scenario::DayAheadScenario, α, t)
    α == 0.0 && return penalty(scenario, t)
    return α*scenario.ρ[t]
end
function reward(scenario::DayAheadScenario, t)
    if 8 <= t <= 12 || 17 <= t <= 24
        return 0.85*scenario.ρ[t]
    else
        return 0.9*scenario.ρ[t]
    end
end
function reward(scenario::DayAheadScenario, β, t)
    β == 0.0 && return reward(scenario, t)
    return β*scenario.ρ[t]
end

@sampler RecurrentDayAheadSampler = begin
    date::Date
    plants::PlantCollection
    price_forecaster::Forecaster
    flow_forecaster::Forecaster

    @sample DayAheadScenario begin
        price_curve = forecast(sampler.price_forecaster, month(sampler.date))
        while !all(price_curve .>= 0)
            price_curve = forecast(sampler.price_forecaster, month(sampler.date))
        end
        flows = forecast(sampler.flow_forecaster, week(sampler.date))
        while !all(flows[:, 2] .>= 0)
            flows = forecast(sampler.flow_forecaster, week(sampler.date))
        end
        return DayAheadScenario(PriceCurve(price_curve), Inflows(sampler.plants, flows[:, 2]))
    end
end

function generate_bidlevels(sampler::AbstractSampler{DayAheadScenario})
    price_curves = [sampler().ρ for i = 1:1000]
    bidlevels = zeros(5,24)
    for i = 1:24
        hourly_prices = [p[i] for p in price_curves]
        μ = mean(hourly_prices)
        σ = std(hourly_prices)
        bidlevels[1,i] = μ - 2*σ
        bidlevels[2,i] = μ - σ
        bidlevels[3,i] = μ
        bidlevels[4,i] = μ + σ
        bidlevels[5,i] = μ + 2*σ
    end
    return bidlevels
end
