@define_scenario MaintenanceSchedulingScenario = begin
    ρ::PriceCurve{24,Float64}
    Q̃::Inflows{typeof(Skellefteälven),Float64}

    @expectation begin
        ρ = mean([s.ρ for s in scenarios])
        Q̃ = mean([s.Q̃ for s in scenarios])
        return MaintenanceSchedulingScenario(ρ, Q̃, probability = 1.0)
    end
end

@sampler RecurrentMaintenanceSchedulingSampler = begin
    date::Date
    plants::PlantCollection
    price_forecaster::Forecaster
    flow_forecaster::Forecaster

    @sample MaintenanceSchedulingScenario begin
        price_curve = forecast(sampler.price_forecaster, month(sampler.date))
        while !all(price_curve .>= 0)
            price_curve = forecast(sampler.price_forecaster, month(sampler.date))
        end
        flows = forecast(sampler.flow_forecaster, week(sampler.date))
        while !all(flows[:, 2] .>= 0)
            flows = forecast(sampler.flow_forecaster, week(sampler.date))
        end
        return MaintenanceSchedulingScenario(PriceCurve(price_curve), Inflows(sampler.plants, flows[:, 2]))
    end
end
