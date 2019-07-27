function DayAheadModel(data::DayAheadData, scenarios::Vector{<:DayAheadScenario}; kw...)
    return StochasticHydroModel("Day-Ahead", HydroModels.Day(), data, DayAheadModelDef, scenarios; kw...)
end

function DayAheadModel(data::DayAheadData, sampler::RecurrentDayAheadSampler, n::Integer; kw...)
    return StochasticHydroModel("Day-Ahead", HydroModels.Day(), data, DayAheadModelDef, sampler, n; kw...)
end

function DayAheadModelDef(horizon::Horizon, data::DayAheadData, indices::DayAheadIndices)
    stochasticmodel = @stochastic_model begin
        # First stage
        # ========================================================
        @stage 1 begin
            @parameters begin
                horizon = horizon
                indices = indices
                data = data
            end
            @unpack hours, plants, bids, blockbids, blocks, hours_per_block = indices
            @unpack hydrodata, regulations, use_blockbids = data
            # Variables
            # ========================================================
            @variable(model, xt_i[t = hours] >= 0)
            @variable(model, xt_d[i = bids, t = hours] >= 0)
            if use_blockbids
                @variable(model, xb[i = blockbids, b = blocks], lowerbound = 0, upperbound = regulations.blocklimit)
            else
                @variable(model, xb)
            end
            # Constraints
            # ========================================================
            # Increasing bid curve
            @constraint(model, bidcurve[i = bids[1:end-1], t = hours],
                        xt_d[i,t] <= xt_d[i+1,t]
                        )
            # Maximal bids
            if use_blockbids
                @constraint(model, maxhourlybids[t = hours],
                            xt_i[t] + xt_d[bids[end],t] + sum(xb[i,b] for i = blockbids for b = findall(A->in(t,A),hours_per_block))<= 1.1*sum(hydrodata[p].H̄ for p in plants)
                            )
            else
                @constraint(model, maxhourlybids[t = hours],
                            xt_i[t] + xt_d[bids[end],t] <= 1.1*sum(hydrodata[p].H̄ for p in plants)
                            )
            end
        end
        # Second stage
        # =======================================================
        @stage 2 begin
            @parameters begin
                horizon = horizon
                indices = indices
                data = data
            end
            @unpack hours, plants, segments, blocks, hours_per_block = indices
            @unpack hydrodata, water_value, regulations, intraday_trading, use_blockbids, bidlevels = data
            @uncertain ρ from ξ::DayAheadScenario
            Q̃ = mean_flows(ξ, plants)
            V = local_inflows(ξ, plants, hydrodata.Qu)
            ih(t) = begin
                idx = findlast(bidlevels[t] .<= ρ[t])
                return idx == nothing ? -1 : idx
            end
            function blockbidlevel(b)
                return mean([bidlevels[i][2:end-1] for i in hours_per_block[b]])
            end
            ib(b) = begin
                idx = findlast(blockbidlevel(b) .<= mean(ρ[hours_per_block[b]]))
                return idx == nothing ? -1 : idx
            end
            # Variables
            # =======================================================
            # First stage
            @decision xt_i xt_d xb
            # -------------------------------------------------------
            @variable(model, yt[t = hours] >= 0)
            if use_blockbids
                @variable(model, yb[b = blocks] >= 0)
            end
            if intraday_trading
                @variable(model, z_up[t = hours] >= 0)
                @variable(model, z_do[t = hours] >= 0)
            end
            @variable(model, Q[p = plants, s = segments, t = hours], lowerbound = 0, upperbound = hydrodata[p].Q̄[s])
            @variable(model, S[p = plants, t = hours] >= 0)
            @variable(model, M[p = plants, t = hours], lowerbound = 0, upperbound = hydrodata[p].M̄)
            @variable(model, W[i = 1:nindices(water_value)])
            @variable(model, H[t = hours] >= 0)
            @variable(model, Qf[p = plants, t = hours] >= 0)
            @variable(model, Sf[p = plants, t = hours] >= 0)

            # Objectives
            # ========================================================
            # Net profit
            if use_blockbids
                @expression(model, net_profit,
                            sum((ρ[t]-regulations.dayaheadfee)*yt[t]
                                for t = hours)
                            + sum(length(hours_per_block[b])*(mean(ρ[hours_per_block[b]])-regulations.dayaheadfee)*yb[b]
                                  for b = blocks))
            else
                @expression(model, net_profit,
                            sum((ρ[t]-regulations.dayaheadfee)*yt[t]
                                for t = hours))
            end
            # Intraday
            @expression(model, intraday,
                        sum(penalty(scenario,t)*z_up[t] - reward(scenario,t)*z_do[t]
                            for t = hours))
            # Value of stored water
            @expression(model, value_of_stored_water, -sum(W[i] for i in 1:nindices(water_value)))
            # Define objective
            if intraday_trading
                @objective(model, Max, net_profit - intraday + value_of_stored_water)
            else
                @objective(model, Max, net_profit + value_of_stored_water)
            end

            # Constraints
            # ========================================================
            # Bid-dispatch links
            @constraint(model, hourlybids[t = hours],
                        yt[t] == ((ρ[t] - bidlevels[t][ih(t)])/(bidlevels[t][ih(t)+1]-bidlevels[t][ih(t)]))*xt_d[ih(t)+1,t]
                        + ((bidlevels[t][ih(t)+1]-ρ[t])/(bidlevels[t][ih(t)+1]-bidlevels[t][ih(t)]))*xt_d[ih(t),t]
                        + xt_i[t]
                        )
            if use_blockbids
                @constraint(model, bidblocks[b = blocks],
                            yb[b] == sum(xb[j,b]
                                         for j = 1:ib(b)))
            end

            # Hydrological balance
            @constraint(model, hydro_constraints[p = plants, t = hours],
                        # Previous reservoir content
                        M[p,t] == (t > 1 ? M[p,t-1] : hydrodata[p].M₀)
                        # Inflow
                        + sum(Qf[i,t]
                              for i = intersect(hydrodata.Qu[p],plants))
                        + sum(Sf[i,t]
                              for i = intersect(hydrodata.Su[p],plants))
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
            # Load balance
            if intraday_trading
                if use_blockbids
                    @constraint(model, loadbalance[t = hours],
                                yt[t] + sum(yb[b] for b = findall(A->in(t,A),hours_per_block)) - H[t] == z_up[t] - z_do[t]
                                )
                else
                    @constraint(model, loadbalance[t = hours],
                                yt[t] - H[t] == z_up[t] - z_do[t]
                                )
                end
            else
                if use_blockbids
                    @constraint(model, loadbalance[t = hours],
                                yt[t] + sum(yb[b] for b = findall(A->in(t,A),hours_per_block)) == H[t])
                else
                    @constraint(model, loadbalance[t = hours],
                                yt[t] == H[t]
                                )
                end
            end
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
            # Water value
            @constraint(model, water_value_approximation[c = 1:ncuts(water_value)],
                        sum(water_value[c][p]*M[p,nhours(horizon)]
                            for p in plants)
                        + sum(W[i]
                              for i in cut_indices(water_value[c])) >= cut_lb(water_value[c]))
        end
    end
    return stochasticmodel
end
