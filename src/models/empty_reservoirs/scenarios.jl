@scenario EmptyReservoirsScenario = begin
    ρ::PriceCurve{Float64}

    @zero begin
        return EmptyReservoirsScenario(PriceCurve(zeros(24)), probability = 1.0)
    end

    @expectation begin
        π = 1.0
        ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:length(scenarios[1].ρ)]
        return EmptyReservoirsScenario(PriceCurve(ρ), probability = 1.0)
    end
end

@sampler RecurrentEmptyReservoirsSampler = begin
    date::Date
    horizon::Horizon
    price_forecaster::Forecaster{:price}

    @sample EmptyReservoirsScenario begin
        price_curve = Vector{Float64}()
        for d = 1:nhours(sampler.horizon)
            daily_curve = forecast(sampler.price_forecaster, month(sampler.date + Dates.Day(d)))
            while !all(daily_curve .>= 0)
                daily_curve = forecast(sampler.price_forecaster, month(sampler.date + Dates.Day(d)))
            end
            append!(price_curve, daily_curve)
        end
        return EmptyReservoirsScenario(PriceCurve(price_curve))
    end
end
