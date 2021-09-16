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
            @unpack hours, plants = indices
            @unpack hydrodata = data
            # Variables
            # ========================================================
            #@decision(model, maintenance_start[p in plants, t in hours], Bin)
            @decision(model, maintenance_period[p in plants, t in hours], Bin)
            # Objectives
            # ========================================================
            # Dummy first-stage objective in order to use Max sense
            @objective(model, Max, 0)
            # Constraints
            # ========================================================
            # Each plant has one starting maintenance hour
            # @constraint(model, single_start_hour[p in plants],
            #             sum(maintenance_start[p,t] for t in hours) == 1)
            # # For feasibility, ensure that there is time left to complete maintenance
            # @constraint(model, enough_time[p in plants, t in hours],
            #             (t + hydrodata[p].Mt)*maintenance_start[p,t] <= nhours(horizon))
            @constraint(model, maintenance_times[p in plants, t in hours],
                        maintenance_period[p,t] - (t > 2 ? maintenance_period[p,t-1] : 0) <= ((t + hydrodata[p].Mt - 1) <= nhours(horizon) ? maintenance_period[p,t+hydrodata[p].Mt-1] : 0))
            @constraint(model, maintenance_finished[p in plants],
                        sum(maintenance_period[p,t] for t in hours) == hydrodata[p].Mt)
            # Only allow one maintenance effort per hour
            @constraint(model, maintenance_concurrency[t in hours],
                        sum(maintenance_period[p,t] for p in plants) <= 1)
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
            @unpack hydrodata = data
            @uncertain ρ Q̃ from MaintenanceSchedulingScenario
            V = local_inflows(Q̃, hydrodata.Qu)
            # Variables
            # =======================================================
            # -------------------------------------------------------
            #@recourse(model, maintenance_period[p in plants, t in hours], Bin)
            @recourse(model, 0 <= Q[p = plants, s = segments, t = hours] <= hydrodata[p].Q̄[s])
            @recourse(model, S[p = plants, t = hours] >= 0)
            @recourse(model, 0 <= M[p = plants, t = hours] <= hydrodata[p].M̄)
            @recourse(model, H[t = hours] >= 0)
            @variable(model, Qf[p = plants, t = hours] >= 0)
            @variable(model, Sf[p = plants, t = hours] >= 0)
            # Objectives
            # ========================================================
            # Net profit
            @expression(model, net_profit,
                        sum(ρ[t]*H[t]
                            for t = hours))
            @objective(model, Max, net_profit)
            # Constraints
            # ========================================================
            # Match maintenance period with starting hour
            # @constraint(model, maintenance_times[p in plants, t in hours],
            #             maintenance_period[p,t] <= sum(maintenance_start[p,t′]
            #                                            for t′ in max(1, t - hydrodata[p].Mt + 1 - 1):min(t+1,nhours(horizon))))
            # Ensure that maintenance is finished
            # @constraint(model, maintenance_finished[p in plants],
            #             sum(maintenance_period[p,t] for t in hours) == hydrodata[p].Mt)
            # Only allow three parallel maintenance efforts per hour
            #@constraint(model, maintenance_concurrency[t in hours],
            #            sum(maintenance_period[p,t] for p in plants) <= 3)
            # Pause production during maintenance hours
            @constraint(model, pause_production[p in plants, s in segments, t in hours],
                        Q[p,s,t] <= (1 - maintenance_period[p,t])*hydrodata[p].Q̄[s])
            @constraint(model, pause_spillage[p in plants, t in hours],
                        S[p,t] <= (1 - maintenance_period[p,t])*hydrodata[p].M̄)
            # Hydrological balance
            @constraint(model, hydro_constraints[p = plants, t = hours],
                        # Previous reservoir content
                        M[p,t] == (t > 1 ? M[p,t-1] : hydrodata[p].M₀)
                        # Inflow
                        + sum(Qf[i,t] for i = intersect(hydrodata.Qu[p],plants))
                        + sum(Sf[i,t] for i = intersect(hydrodata.Su[p],plants))
                        # Local inflow
                        + V[p]
                        # Outflow
                        - sum(Q[p,s,t]
                              for s = segments)
                        - S[p,t]
                        )
            # Production
            @constraint(model, production[t = hours],
                        H[t] == sum(hydrodata[p].μ[s]*Q[p,s,t]
                                    for p = plants, s = segments)
                        )
            # Water flow: Discharge + Spillage
            Containers.@container [p = plants, t = hours] begin
                if t - hydrodata[p].Rqh > 1
                    @constraint(model,
                                Qf[p,t] == (hydrodata[p].Rqm/60)*sum(Q[p,s,t-(hydrodata[p].Rqh+1)]
                                                                     for s = segments)
                                + (1-hydrodata[p].Rqm/60)*sum(Q[p,s,t-hydrodata[p].Rqh]
                                                              for s = segments)
                                )
                elseif t - hydrodata[p].Rqh > 0
                    @constraint(model,
                                Qf[p,t] == (1-hydrodata[p].Rqm/60)*sum(Q[p,s,t-hydrodata[p].Rqh]
                                                                       for s = segments)
                                )
                else
                    @constraint(model,
                                Qf[p,t] == 0
                                )
                end
            end
            Containers.@container [p = plants,  t = hours] begin
                if t - hydrodata[p].Rsh > 1
                    @constraint(model,
                                Sf[p,t] == (hydrodata[p].Rsm/60)*S[p,t-(hydrodata[p].Rsh+1)]
                                + (1-hydrodata[p].Rsm/60)*S[p,t-hydrodata[p].Rsh]
                                )
                elseif t - hydrodata[p].Rsh > 0
                    @constraint(model,
                                Sf[p,t] == (1-hydrodata[p].Rsm/60)*S[p,t-hydrodata[p].Rsh]
                                )
                else
                    @constraint(model,
                                Sf[p,t] == 0
                                )
                end
            end
        end
    end
    return stochasticmodel
end
