@scenario WeekAheadScenario = begin
    ρ::PriceCurve{Float64}
    Q̃::Matrix{Float64}

    @zero begin
        return WeekAheadScenario(PriceCurve(zeros(24)), zeros(15, 7), probability = 1.0)
    end

    @expectation begin
        π = 1.0
        ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:nhours(HydroModels.Week())]
        Q̃ = mean([s.Q̃ for s in scenarios])
        return WeekAheadScenario(PriceCurve(ρ), Q̃, probability = 1.0)
    end
end

function local_inflows(scenario::WeekAheadScenario, plants::Vector{Plant}, upstream_plants::Dict{Plant, Vector{Plant}})
    discharges = Vector{Dict{Plant, Float64}}(undef, 7)
    for d = 1:7
        discharges[d] = Dict{Plant, Float64}()
        for (i,p) in enumerate(plants)
            discharges[d][p] = scenario.Q̃[i,d]
        end
    end
    local_inflows = Vector{Dict{Plant, Float64}}(undef, 7)
    for d = 1:7
        local_inflows[d] = Dict{Plant, Float64}()
        for (i,p) in enumerate(plants)
            local_inflows[d][p] = calculate_inflow(p, discharges[d], upstream_plants[p])
        end
    end
    return local_inflows
end

function mean_flows(scenario::WeekAheadScenario, plants::Vector{Plant})
    mean_flows = Dict{Plant, Float64}()
    for (i,p) in enumerate(plants)
        mean_flows[p] = scenario.Q̃[i,1]
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

struct RecurrentWeekAheadSampler <: AbstractSampler{WeekAheadScenario}
    date::Date
    price_forecaster::Forecaster{:price}
    flow_forecaster::Forecaster{:flow}
end

function (sampler::RecurrentWeekAheadSampler)()
    price_curve = Vector{Float64}()
    for d = 1:7
        daily_curve = forecast(sampler.price_forecaster, month(sampler.date))
        while !all(daily_curve .>= 0)
            daily_curve = forecast(sampler.price_forecaster, month(sampler.date))
        end
        append!(price_curve, daily_curve)
    end
    flows = forecast(sampler.flow_forecaster, week(sampler.date))
    while !all(flows[:, 2] .>= 0)
        flows = forecast(sampler.flow_forecaster, week(sampler.date))
    end
    return WeekAheadScenario(PriceCurve(price_curve), flows)
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
