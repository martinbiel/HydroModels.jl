function MaintenanceSchedulingModel(data::MaintenanceSchedulingData, scenarios::Vector{<:MaintenanceSchedulingScenario}; kw...)
    return StochasticHydroModel("Maintenance scheduling", HydroModels.Day(), data, MaintenanceSchedulingModelDef, scenarios; kw...)
end

function MaintenanceSchedulingModel(data::MaintenanceSchedulingData, sampler::RecurrentMaintenanceSchedulingSampler, n::Integer; kw...)
    return StochasticHydroModel("Maintenance scheduling", HydroModels.Day(), data, MaintenanceSchedulingModelDef, sampler, n; kw...)
end

function MaintenanceSchedulingModelDef(horizon::Horizon, data::MaintenanceSchedulingData, indices::MaintenanceSchedulingIndices)
    stochasticmodel = @stochastic_model begin
        # First stage
        # ========================================================
        @stage 1 begin
            @parameters begin
                horizon = horizon
                indices = indices
                data = data
            end
            @unpack hours, plants, bids = indices
            @unpack hydrodata = data
            # Variables
            # ========================================================
            #@decision(model, maintenance_start[p in plants, t in hours], Bin)
            @decision(model, xᴵ[t in hours] >= 0)
            @decision(model, xᴰ[i in bids, t in hours] >= 0)
            @decision(model, maintenance_period[p in plants, t in hours], Bin)
            # Objectives
            # ========================================================
            # Dummy first-stage objective in order to use Max sense
            @objective(model, Max, 0)
            # Constraints
            # ========================================================
            # Maintenance period should be a consecutive period
            @constraint(model, maintenance_times[p in plants, t in hours],
                        maintenance_period[p,t] - (t > 2 ? maintenance_period[p,t-1] : 0) <= ((t + hydrodata[p].Mt - 1) <= num_hours(horizon) ? maintenance_period[p,t+hydrodata[p].Mt-1] : 0))
            # Ensure maintenance is finished
            @constraint(model, maintenance_finished[p in plants],
                        sum(maintenance_period[p,t] for t in hours) == hydrodata[p].Mt)
            # Increasing bid curve
            @constraint(model, bidcurve[i in bids[1:end-1], t in hours],
                xᴰ[i,t] <= xᴰ[i+1,t]
            )
            # Maximal bids
            @constraint(model, maxhourlybids[t in hours],
                        xᴵ[t] + xᴰ[bids[end],t] <= 2*sum(hydrodata[p].H̄ for p in plants)
                        )
        end
        # Second stage
        # =======================================================
        @stage 2 begin
            @parameters begin
                horizon = horizon
                indices = indices
                data = data
            end
            @unpack hours, plants, segments = indices
            @unpack hydrodata, bidlevels = data
            @uncertain ρ Q̃ from ξ::MaintenanceSchedulingScenario
            V = local_inflows(Q̃, hydrodata.Qu)
            # Auxilliary functions
            ih(t) = begin
                idx = findlast(bidlevels[t] .<= ρ[t])
                return idx == nothing ? -1 : idx
            end
            interpolate(ρ, bidlevels, xᴰ, t) = begin
                lower = ((ρ[t] - bidlevels[t][ih(t)])/(bidlevels[t][ih(t)+1]-bidlevels[t][ih(t)]))*xᴰ[ih(t)+1,t]
                upper = ((bidlevels[t][ih(t)+1]-ρ[t])/(bidlevels[t][ih(t)+1]-bidlevels[t][ih(t)]))*xᴰ[ih(t),t]
                return lower + upper
            end
            # Variables
            # =======================================================
            # -------------------------------------------------------
            @recourse(model, yᴴ[t in hours] >= 0)
            @recourse(model, y⁺[t in hours] >= 0)
            @recourse(model, y⁻[t in hours] >= 0)
            @recourse(model, 0 <= Q[p in plants, s in segments, t in hours] <= Q̄(hydrodata, p, s))
            @recourse(model, S[p in plants, t in hours] >= 0)
            @recourse(model, 0 <= M[p in plants, t in hours] <= hydrodata[p].M̄)
            @recourse(model, H[t in hours] >= 0)
            @variable(model, Qf[p in plants, t in hours] >= 0)
            @variable(model, Sf[p in plants, t in hours] >= 0)
            # Objectives
            # ========================================================
            # Net profit
            @expression(model, net_profit,
                        sum(ρ[t]*H[t]
                            for t in hours))
            # Intraday
            @expression(model, intraday,
                        sum(penalty(ξ,t)*y⁺[t] - reward(ξ,t)*y⁻[t]
                            for t in hours))
            # Define objective
            @objective(model, Max, net_profit - intraday)
            # Constraints
            # ========================================================
            # Bid-dispatch links
            @constraint(model, hourlybids[t in hours],
                yᴴ[t] == interpolate(ρ, bidlevels, xᴰ, t) + xᴵ[t]
            )
            # Pause production during maintenance hours
            @constraint(model, pause_production[p in plants, s in segments, t in hours],
                        Q[p,s,t] <= (1 - maintenance_period[p,t])*Q̄(hydrodata, p, s))
            # Hydrological balance
            @constraint(model, hydro_constraints[p in plants, t in hours],
                        # Previous reservoir content
                        M[p,t] == (t > 1 ? M[p,t-1] : hydrodata[p].M₀)
                        # Inflow
                        + sum(Qf[i,t] for i in intersect(hydrodata.Qu[p],plants))
                        + sum(Sf[i,t] for i in intersect(hydrodata.Su[p],plants))
                        # Local inflow
                        + V[p]
                        # Outflow
                        - sum(Q[p,s,t]
                              for s in segments)
                        - S[p,t]
                        )
            # Production
            @constraint(model, production[t in periods],
                        H[t] == sum(marginal_production(Resolution(1), μ(hydrodata, p, s)) * Q[p,s,t]
                                    for p in plants, s in segments)
                        )
            # Load balance
            @constraint(model, loadbalance[t in hours],
                        yᴴ[t] - H[t] == y⁺[t] - y⁻[t]
                        )
            # Water flow: Discharge + Spillage
            @constraint(model, discharge_flow_time[p in plants, t in periods],
                        Qf[p,t] == (t - water_flow_time(Resolution(1), hydrodata[p].Rq) > 0 ?
                        overflow(Resolution(1), hydrodata[p].Rq) * sum(Q[p,s,t-water_flow_time(Resolution(1), hydrodata[p].Rq)]
                                                                    for s in segments) : 0.0)
                        + (t - water_flow_time(Resolution(1), hydrodata[p].Rq) > 1 ?
                        historic_flow(Resolution(1), hydrodata[p].Rq)*sum(Q[p,s,t-(water_flow_time(Resolution(1), hydrodata[p].Rq)+1)]
                                                                       for s in segments) : 0.0))
            @constraint(model, spillage_flow_time[p in plants, t in periods],
                        Sf[p,t] == (t - water_flow_time(Resolution(1), hydrodata[p].Rs) > 0 ?
                        overflow(Resolution(1), hydrodata[p].Rs) * S[p,t-water_flow_time(Resolution(1), hydrodata[p].Rs)] : 0.0)
                        + (t - water_flow_time(Resolution(1), hydrodata[p].Rs) > 1 ?
                        historic_flow(Resolution(1), hydrodata[p].Rs)*S[p,t-(water_flow_time(Resolution(1), hydrodata[p].Rq)+1)] : 0.0))
        end
    end
    return stochasticmodel
end
