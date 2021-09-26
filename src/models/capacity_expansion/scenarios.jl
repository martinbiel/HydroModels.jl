struct CapacityExpansionScenario{T₁,T₂} <: AbstractScenario
    probability::Probability
    ρ::PriceCurve{T₁,Float64}
    Q̃::InflowSequence{T₂,typeof(Skellefteälven),Float64}

    function CapacityExpansionScenario(ρ::PriceCurve{T₁,Float64}, Q̃::InflowSequence{T₂,typeof(Skellefteälven),Float64}; probability::AbstractFloat = 1.0) where {T₁,T₂}
        T₁ == 24*T₂ || error("Incompatible price period $T₁ and flow period $T₂.")
        return new{T₁,T₂}(Probability(probability), ρ, Q̃)
    end
end

function Base.zero(::Type{CapacityExpansionScenario{T₁,T₂}}) where {T₁,T₂}
    return CapacityExpansionScenario(zero(PriceCurve{T₁,Float64}), zero(InflowSequence{T₂,typeof(Skellefteälven),Float64}); probability = 1.0)
end

function StochasticPrograms.expected(ξ₁::CapacityExpansionScenario, ξ₂::CapacityExpansionScenario)
    ρ = mean([ξ₁.ρ, ξ₂.ρ])
    Q̃ = mean([ξ₁.Q̃, ξ₂.Q̃])
    expected = CapacityExpansionScenario(ρ, Q̃)
    return ExpectedScenario(expected)
end

struct RecurrentCapacityExpansionSampler{T₁,T₂} <: AbstractSampler{CapacityExpansionScenario{T₁,T₂}}
    date::Date
    plants::PlantCollection
    price_forecaster::Forecaster
    flow_forecaster::Forecaster
    electricity_price_rate::Float64
    horizon::Horizon

    function RecurrentCapacityExpansionSampler(date::Date,
                                               plants::PlantCollection,
                                               price_forecaster::Forecaster,
                                               flow_forecaster::Forecaster,
                                               electricity_price_rate::Float64,
                                               horizon::Horizon)
        T₁ = num_hours(horizon)
        T₂ = num_days(horizon)
        return new{T₁,T₂}(date, plants, price_forecaster, flow_forecaster, electricity_price_rate, horizon)
    end
end

function (sampler::RecurrentCapacityExpansionSampler)()
    price_rate = sampler.electricity_price_rate * rand()
    price_curve = forecast(sampler.price_forecaster, month(sampler.date))
    while !all(price_curve .>= 0)
        price_curve = forecast(sampler.price_forecaster, month(sampler.date))
    end
    for d = 1:num_days(sampler.horizon)-1
        date = sampler.date + Dates.Day(d)
        years_passed = Dates.value(Dates.Year(date) - Dates.Year(sampler.date))
        daily_curve = (1 + price_rate)^years_passed * forecast(sampler.price_forecaster, price_curve[end], month(date))
        while !all(daily_curve .>= 0)
            daily_curve = (1 + price_rate)^years_passed * forecast(sampler.price_forecaster, price_curve[end], month(date))
        end
        append!(price_curve, daily_curve[:])
    end
    flows = forecast(sampler.flow_forecaster, week(sampler.date))
    while !all(flows[:, 2] .>= 0)
        flows = forecast(sampler.flow_forecaster, week(sampler.date))
    end
    for w = 1:num_weeks(sampler.horizon)-1
        date = sampler.date + Dates.Week(w)
        weekly_flows = forecast(sampler.flow_forecaster, flows[:,end], week(date))
        while !all(weekly_flows[:, 2] .>= 0)
            weekly_flows = forecast(sampler.flow_forecaster, flows[:,end], week(date))
        end
        flows = hcat(flows, weekly_flows)
    end
    if size(flows, 2) < num_days(sampler.horizon)
        date = sampler.date + Dates.Week(num_weeks(sampler.horizon)-1)
        weekly_flows = forecast(sampler.flow_forecaster, flows[:,end], week(date))
        while !all(weekly_flows[:, 2] .>= 0)
            weekly_flows = forecast(sampler.flow_forecaster, flows[:,end], week(date))
        end
        flows = hcat(flows, weekly_flows[:,1:num_days(sampler.horizon)-size(flows,2)])
    end
    return CapacityExpansionScenario(PriceCurve(price_curve), InflowSequence(sampler.plants, flows))
end
