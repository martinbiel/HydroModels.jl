function CapacityExpansionModel(data::CapacityExpansionData, scenarios::Vector{<:CapacityExpansionScenario}; horizon = HydroModels.Year(), kw...)
    return StochasticHydroModel("Capacity expansion", horizon, data, CapacityExpansionModelDef, scenarios; kw...)
end

function CapacityExpansionModel(data::CapacityExpansionData, sampler::RecurrentCapacityExpansionSampler, n::Integer; horizon = HydroModels.Year(), kw...)
    return StochasticHydroModel("Capacity expansion", horizon, data, CapacityExpansionModelDef, sampler, n; kw...)
end

function CapacityExpansionModelDef(horizon::Horizon, data::CapacityExpansionData, indices::CapacityExpansionIndices)
    stochasticmodel = @stochastic_model begin
        # First stage
        # ========================================================
        @stage 1 begin
            @parameters begin
                horizon = horizon
                indices = indices
                data = data
            end
            @unpack plants, levels = indices
            @unpack hydrodata, investment_levels = data

            # Variables
            # ========================================================
            @decision(model, 0 <= ΔH̄ <= 1000)
            @decision(model, ΔH[p in plants] >= 0)
            # Objectives
            # ========================================================
            # Minimize cost of expansion (in MEUR)
            @objective(model, Max, -equivalent_cost(data, horizon) * ΔH̄)
            # Constraints
            # ========================================================
            # Distribute chosen expansion over plants
            @constraint(model, distribute_expansion,
                        sum(ΔH[p] for p in plants) == ΔH̄)
        end
        # Second stage
        # =======================================================
        @stage 2 begin
            @parameters begin
                horizon = horizon
                indices = indices
                data = data
            end
            @unpack periods, plants, segments = indices
            @unpack hydrodata, resolution = data
            @uncertain ρ Q̃ from ξ::CapacityExpansionScenario
            V = local_inflow_sequence(Q̃, hydrodata.Qu)
            # Variables
            # =======================================================
            # -------------------------------------------------------
            @recourse(model, Q[p in plants, s in segments, t in periods] >= 0)
            @recourse(model, S[p in plants, t in periods] >= 0)
            @recourse(model, 0 <= M[p in plants, t in periods] <= water_volume(resolution, hydrodata[p].M̄))
            @recourse(model, H[t in periods] >= 0)
            @variable(model, Qf[p in plants, t in periods] >= 0)
            @variable(model, Sf[p in plants, t in periods] >= 0)
            # Objectives
            # ========================================================
            # Net profit
            @expression(model, net_profit,
                        sum(HydroModels.mean_price(resolution, ρ, t)*H[t]
                            for t in periods))
            # Define objective (in MEUR)
            @objective(model, Max, net_profit / 1e6)
            # Constraints
            # ========================================================
            # Capacity expansion
            @constraint(model, capacity_expansion[p in plants, s in segments, t in periods],
                        Q[p,s,t] <= Q̄(hydrodata, p, s) + %(hydrodata, s) * (hydrodata[p].Q̄ / hydrodata[p].H̄) * ΔH[p])
            # Hydrological balance
            @constraint(model, hydro_constraints[p in plants, t in periods],
                        # Previous reservoir content
                        M[p,t] == (t > 1 ? M[p,t-1] : water_volume(resolution, hydrodata[p].M₀))
                        # Inflow
                        + sum(Qf[i,t] for i in intersect(hydrodata.Qu[p],plants))
                        + sum(Sf[i,t] for i in intersect(hydrodata.Su[p],plants))
                        # Local inflow
                        + HydroModels.mean_flow(resolution, V, t, p)
                        # Outflow
                        - sum(Q[p,s,t]
                              for s in segments)
                        - S[p,t]
                        )
            # Production
            @constraint(model, production[t in periods],
                        H[t] == sum(marginal_production(resolution, μ(hydrodata, p, s)) * Q[p,s,t]
                                    for p in plants, s in segments)
                        )
            # Water flow: Discharge + Spillage
            @constraint(model, discharge_flow_time[p in plants, t in periods],
                        Qf[p,t] == (t - water_flow_time(resolution, hydrodata[p].Rq) > 0 ?
                        overflow(resolution, hydrodata[p].Rq) * sum(Q[p,s,t-water_flow_time(resolution, hydrodata[p].Rq)]
                                                                    for s in segments) : 0.0)
                        + (t - water_flow_time(resolution, hydrodata[p].Rq) > 1 ?
                        historic_flow(resolution, hydrodata[p].Rq)*sum(Q[p,s,t-(water_flow_time(resolution, hydrodata[p].Rq)+1)]
                                                                       for s in segments) : 0.0))
            @constraint(model, spillage_flow_time[p in plants, t in periods],
                        Sf[p,t] == (t - water_flow_time(resolution, hydrodata[p].Rs) > 0 ?
                        overflow(resolution, hydrodata[p].Rs) * S[p,t-water_flow_time(resolution, hydrodata[p].Rs)] : 0.0)
                        + (t - water_flow_time(resolution, hydrodata[p].Rs) > 1 ?
                        historic_flow(resolution, hydrodata[p].Rs)*S[p,t-(water_flow_time(resolution, hydrodata[p].Rq)+1)] : 0.0))
        end
    end
    return stochasticmodel
end
