@define_scenario WeekAheadScenario = begin
    ρ::PriceCurve{168,Float64}
    Q̃::InflowSequence{7,typeof(Skellefteälven),Float64}

    @expectation begin
        ρ = mean([s.ρ for s in scenarios])
        Q̃ = mean([s.Q̃ for s in scenarios])
        return WeekAheadScenario(ρ, Q̃, probability = 1.0)
    end
end

@sampler RecurrentWeekAheadSampler = begin
    date::Date
    plants::PlantCollection
    price_forecaster::Forecaster
    flow_forecaster::Forecaster

    @sample WeekAheadScenario begin
        price_curve = Vector{Float64}()
        for d = 1:7
            daily_curve = forecast(sampler.price_forecaster, month(sampler.date))
            while !all(daily_curve .>= 0)
                daily_curve = forecast(sampler.price_forecaster, month(sampler.date))
            end
            append!(price_curve, daily_curve[:])
        end
        flows = forecast(sampler.flow_forecaster, week(sampler.date))
        while !all(flows[:, 2] .>= 0)
            flows = forecast(sampler.flow_forecaster, week(sampler.date))
        end
        return WeekAheadScenario(PriceCurve(price_curve), InflowSequence(sampler,plants, flows))
    end
end
