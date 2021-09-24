struct CapacityExpansionScenario{T₁,T₂} <: AbstractScenario
    probability::Probability
    ρ::PriceCurve{T₁,Float64}
    Q̃::InflowSequence{T₂,typeof(Skellefteälven),Float64}

    function CapacityExpansionScenario(ρ::PriceCurve{T₁,Float64}, Q̃::InflowSequence{T₂,typeof(Skellefteälven),Float64}; probability::AbstractFloat = 1.0) where {T₁,T₂}
        @assert T₁ == 24*T₂
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

@sampler RecurrentCapacityExpansionSampler = begin
    date::Date
    plants::PlantCollection
    price_forecaster::Forecaster
    flow_forecaster::Forecaster
    horizon::Horizon

    @sample CapacityExpansionScenario{24*365,365} begin
        price_curve = forecast(sampler.price_forecaster, month(sampler.date))
        while !all(price_curve .>= 0)
            price_curve = forecast(sampler.price_forecaster, month(sampler.date))
        end
        for d = 1:num_days(sampler.horizon)-1
            date = sampler.date + Dates.Day(d)
            daily_curve = forecast(sampler.price_forecaster, price_curve[end], month(date))
            while !all(daily_curve .>= 0)
                daily_curve = forecast(sampler.price_forecaster, price_curve[end], month(date))
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
            flows = hcat(flows, weekly_flows[:,num_days(sampler.horizon)-size(flows,2)])
        end
        return CapacityExpansionScenario(PriceCurve(price_curve), InflowSequence(sampler.plants, flows))
    end
end
