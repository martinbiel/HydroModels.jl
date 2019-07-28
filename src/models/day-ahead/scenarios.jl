@scenario DayAheadScenario = begin
    ρ::PriceCurve{Float64}
    Q̃::Vector{Float64}

    @zero begin
        return DayAheadScenario(PriceCurve(zeros(24)), Vector{Float64}(), probability = 1.0)
    end

    @expectation begin
        π = 1.0
        ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:nhours(HydroModels.Day())]
        Q̃ = mean([s.Q̃ for s in scenarios])
        return DayAheadScenario(PriceCurve(ρ), Q̃, probability = 1.0)
    end
end

function penalty(scenario::DayAheadScenario, t)
    if 8 <= t <= 12 || 17 <= t <= 24
        return 1.15*scenario.ρ[t]
    else
        return 1.1*scenario.ρ[t]
    end
end
function reward(scenario::DayAheadScenario, t)
    if 12 <= t <= 18 || 17 <= t <= 24
        return 0.85*scenario.ρ[t]
    else
        return 0.9*scenario.ρ[t]
    end
end

function local_inflows(scenario::DayAheadScenario, plants::Vector{Plant}, upstream_plants::Dict{Plant, Vector{Plant}})
    discharges = Dict{Plant, Float64}()
    for (i,p) in enumerate(plants)
        discharges[p] = scenario.Q̃[i]
    end
    local_inflows = Dict{Plant, Float64}()
    for (i,p) in enumerate(plants)
        local_inflows[p] = calculate_inflow(p, discharges, upstream_plants[p])
    end
    return local_inflows
end

function mean_flows(scenario::DayAheadScenario, plants::Vector{Plant})
    mean_flows = Dict{Plant, Float64}()
    for (i,p) in enumerate(plants)
        mean_flows[p] = scenario.Q̃[i]
    end
    return mean_flows
end

function calculate_inflow(plant::Plant, w::Dict{Plant,<:AbstractFloat}, upstream_plants::Vector{Plant})
    V = w[plant]
    if !isempty(upstream_plants)
        V -= sum(w[p] for p in upstream_plants)
    end
    return max(0, V)
end

# @sampler MVNormalSampler = begin
#     distribution::FullNormal
#     function MVNormalSampler(data::DayAheadData)
#         distribution = fit(MvNormal,reduce(hcat,[c.λ for (d,c) in data.pricedata.curves]))
#         return new(distribution)
#     end
#     @sample DayAheadScenario begin
#         ρ = rand(sampler.distribution,1)[:]
#         while any(ρ .<= 0)
#             # Ensure that prices are never negative
#             ρ = rand(sampler.distribution,1)[:]
#         end
#         π = pdf(sampler.distribution,ρ)[1]
#         return DayAheadScenario(PriceCurve(ρ), probability = π)
#     end
# end

struct RecurrentDayAheadSampler <: AbstractSampler{DayAheadScenario}
    date::Date
    price_forecaster::Forecaster{:price}
    flow_forecaster::Forecaster{:flow}
end

function (sampler::RecurrentDayAheadSampler)()
    price_curve = forecast(sampler.price_forecaster, month(sampler.date))
    while !all(price_curve .>= 0)
        price_curve = forecast(sampler.price_forecaster, month(sampler.date))
    end
    flows = forecast(sampler.flow_forecaster, week(sampler.date))
    while !all(flows[:, 2] .>= 0)
        flows = forecast(sampler.flow_forecaster, week(sampler.date))
    end
    return DayAheadScenario(PriceCurve(price_curve), flows[:, 2])
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
