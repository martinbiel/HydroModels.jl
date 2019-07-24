@hydromodel Stochastic EmptyReservoirs = begin
    # First stage
    # ========================================================
    @stage 1 begin
        @parameters begin
            horizon
            indices
            data
        end
        @unpack plants = indices
        @unpack hydrodata = data
        # Variables
        # ========================================================
        @variable(model, M₀[p = plants], lowerbound = 0, upperbound = hydrodata[p].M̄)
    end
    # Second stage
    # =======================================================
    @stage 2 begin
        @parameters begin
            horizon
            indices
            data
        end
        @unpack hours, plants, segments = indices
        @unpack hydrodata = data
        @uncertain ρ from EmptyReservoirsScenario
        # Variables
        # =======================================================
        # First stage
        @decision M₀
        # -------------------------------------------------------
        @variable(model, Q[p = plants, s = segments, t = hours], lowerbound = 0, upperbound = hydrodata[p].Q̄[s])
        @variable(model, S[p = plants, t = hours] >= 0)
        @variable(model, M[p = plants, t = hours], lowerbound = 0, upperbound = hydrodata[p].M̄)
        @variable(model, H[t = hours] >= 0)
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
        # Hydrological balance
        @constraint(model, hydro_constraints[p = plants, t = hours],
                    # Previous reservoir content
                    M[p,t] == (t > 1 ? M[p,t-1] : M₀[p])
                    # Inflow
                    + sum(Qf[i,t]
                          for i = intersect(hydrodata.Qu[p],plants))
                    + sum(Sf[i,t]
                          for i = intersect(hydrodata.Su[p],plants))
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
        @constraintref Qflow[1:length(plants),1:nhours(horizon)]
        @constraintref Sflow[1:length(plants),1:nhours(horizon)]
        for (pidx,p) = enumerate(plants)
            for t = hours
                if t - hydrodata[p].Rqh > 1
                    Qflow[pidx,t] = @constraint(model,
                                                Qf[p,t] == (hydrodata[p].Rqm/60)*sum(Q[p,s,t-(hydrodata[p].Rqh+1)]
                                                                                 for s = segments)
                                                + (1-hydrodata[p].Rqm/60)*sum(Q[p,s,t-hydrodata[p].Rqh]
                                                                          for s = segments)
                                                )
                elseif t - hydrodata[p].Rqh > 0
                    Qflow[pidx,t] = @constraint(model,
                                                Qf[p,t] == (1-hydrodata[p].Rqm/60)*sum(Q[p,s,t-hydrodata[p].Rqh]
                                                                                   for s = segments)
                                                )
                else
                    Qflow[pidx,t] = @constraint(model,
                                                Qf[p,t] == 0
                                                )
                end
                if t - hydrodata[p].Rsh > 1
                    Sflow[pidx,t] = @constraint(model,
                                                Sf[p,t] == (hydrodata[p].Rsm/60)*S[p,t-(hydrodata[p].Rsh+1)]
                                                + (1-hydrodata[p].Rsm/60)*S[p,t-hydrodata[p].Rsh]
                                                )
                elseif t - hydrodata[p].Rsh > 0
                    Sflow[pidx,t] = @constraint(model,
                                                Sf[p,t] == (1-hydrodata[p].Rsm/60)*S[p,t-hydrodata[p].Rsh]
                                                )
                else
                    Sflow[pidx,t] = @constraint(model,
                                                Sf[p,t] == 0
                                                )
                end
            end
        end
    end
end

function EmptyReservoirsModel(data::AbstractModelData, args...; kw...)
    return EmptyReservoirsModel(maximum_horizon(data), data, args...; kw...)
end
