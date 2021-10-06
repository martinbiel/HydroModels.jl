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
            active_blocks(t) = findall(A->in(t,A), hours_per_block)
            # Variables
            # ========================================================
            @decision(model, xᴵ[t in hours] >= 0)
            @decision(model, xᴰ[i in bids, t = hours] >= 0)
            if use_blockbids
                @decision(model, 0 <= xᴮ[i = blockbids, b = blocks] <= regulations.blocklimit)
            end
            # Constraints
            # ========================================================
            # Increasing bid curve
            @constraint(model, bidcurve[i in bids[1:end-1], t in hours],
                xᴰ[i,t] <= xᴰ[i+1,t]
            )
            # Maximal bids
            if use_blockbids
                @constraint(model, maxhourlybids[t in hours],
                    xᴵ[t] + xᴰ[bids[end],t] + sum(xᴮ[i,b]
                        for i in blockbids for b in active_blocks(t))
                            <= 2*sum(hydrodata[p].H̄ for p in plants)
                )
            else
                @constraint(model, maxhourlybids[t in hours],
                    xᴵ[t] + xᴰ[bids[end],t] <= 2*sum(hydrodata[p].H̄ for p in plants)
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
            @unpack hydrodata, water_value, regulations, intraday_trading, simple_water_value, penalty_percentage, use_blockbids, bidlevels = data
            α = penalty_percentage
            β = α == 0.0 ? 0.0 : 1/α
            @uncertain ρ Q̃ from ξ::DayAheadScenario
            V = local_inflows(Q̃, hydrodata.Qu)
            # Auxilliary functions
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
            interpolate(ρ, bidlevels, xᴰ, t) = begin
                lower = ((ρ[t] - bidlevels[t][ih(t)])/(bidlevels[t][ih(t)+1]-bidlevels[t][ih(t)]))*xᴰ[ih(t)+1,t]
                upper = ((bidlevels[t][ih(t)+1]-ρ[t])/(bidlevels[t][ih(t)+1]-bidlevels[t][ih(t)]))*xᴰ[ih(t),t]
                return lower + upper
            end
            active_blocks(t) = findall(A->in(t,A), hours_per_block)
            # Variables
            # =======================================================
            # -------------------------------------------------------
            @variable(model, yᴴ[t in hours] >= 0)
            if use_blockbids
                @variable(model, yᴮ[b in blocks] >= 0)
            end
            if intraday_trading
                @variable(model, y⁺[t in hours] >= 0)
                @variable(model, y⁻[t in hours] >= 0)
            end
            @variable(model, 0 <= Q[p in plants, s in segments, t in hours] <= Q̄(hydrodata, p, s))
            @variable(model, S[p in plants, t in hours] >= 0)
            @variable(model, 0 <= M[p in plants, t in hours] <= hydrodata[p].M̄)
            if !simple_water_value
                @variable(model, W[i in 1:nindices(water_value)])
            end
            @variable(model, H[t in hours] >= 0)
            @variable(model, Qf[p in plants, t in hours] >= 0)
            @variable(model, Sf[p in plants, t in hours] >= 0)

            # Objectives
            # ========================================================
            # Net profit
            if use_blockbids
                @expression(model, net_profit,
                    sum((ρ[t]-regulations.dayaheadfee)*yᴴ[t]
                        for t in hours)
                    + sum(length(hours_per_block[b])*(mean(ρ[hours_per_block[b]])-regulations.dayaheadfee)*yᴮ[b]
                        for b in blocks))
            else
                @expression(model, net_profit,
                    sum((ρ[t]-regulations.dayaheadfee)*yᴴ[t]
                        for t in hours))
            end
            # Intraday
            if intraday_trading
                @expression(model, intraday,
                            sum((penalty(ξ,t) + regulations.intradayfee)*y⁺[t] - (reward(ξ,t) - regulations.intradayfee)*y⁻[t]
                                for t in hours))
            end
            # Value of stored water
            if simple_water_value
                @expression(model, value_of_stored_water,
                            mean(ρ)*sum(M[p,num_hours(horizon)]*sum(marginal_production(Resolution(1), μ(hydrodata, i, 1))
                                                                    for i in hdata.Qd[p])
                                       for p = plants))
            else
                @expression(model, value_of_stored_water, -sum(W[i] for i in 1:nindices(water_value)))
            end
            # Define objective
            if intraday_trading
                @objective(model, Max, net_profit - intraday + value_of_stored_water)
            else
                @objective(model, Max, net_profit + value_of_stored_water)
            end

            # Constraints
            # ========================================================
            # Bid-dispatch links
            @constraint(model, hourlybids[t in hours],
                yᴴ[t] == interpolate(ρ, bidlevels, xᴰ, t) + xᴵ[t]
            )
            if use_blockbids
                @constraint(model, bidblocks[b in blocks],
                    yᴮ[b] == sum(xᴮ[j,b]
                        for j in 1:ib(b)))
            end

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
                - sum(Q[p,s,t] for s in segments)
                - S[p,t]
            )
            # Production
            @constraint(model, production[t in hours],
                        H[t] == sum(marginal_production(Resolution(1), μ(hydrodata, p, s)) * Q[p,s,t]
                                    for p in plants, s in segments)
                        )
            # Load balance
            if intraday_trading
                if use_blockbids
                    @constraint(model, loadbalance[t in hours],
                        yᴴ[t] + sum(yᴮ[b] for b in active_blocks(t)) - H[t] == y⁺[t] - y⁻[t]
                    )
                else
                    @constraint(model, loadbalance[t in hours],
                        yᴴ[t] - H[t] == y⁺[t] - y⁻[t]
                    )
                end
            else
                if use_blockbids
                    @constraint(model, loadbalance[t in hours],
                        yᴴ[t] + sum(yᴮ[b] for b in active_blocks(t)) == H[t]
                    )
                else
                    @constraint(model, loadbalance[t in hours],
                        yᴴ[t] == H[t]
                    )
                end
            end
            # Water flow: Discharge + Spillage
            @constraint(model, discharge_flow_time[p in plants, t in hours],
                        Qf[p,t] == (t - water_flow_time(Resolution(1), hydrodata[p].Rq) > 0 ?
                        overflow(Resolution(1), hydrodata[p].Rq) * sum(Q[p,s,t-water_flow_time(Resolution(1), hydrodata[p].Rq)]
                                                                    for s in segments) : 0.0)
                        + (t - water_flow_time(Resolution(1), hydrodata[p].Rq) > 1 ?
                        historic_flow(Resolution(1), hydrodata[p].Rq)*sum(Q[p,s,t-(water_flow_time(Resolution(1), hydrodata[p].Rq)+1)]
                                                                       for s in segments) : 0.0))
            @constraint(model, spillage_flow_time[p in plants, t in hours],
                        Sf[p,t] == (t - water_flow_time(Resolution(1), hydrodata[p].Rs) > 0 ?
                        overflow(Resolution(1), hydrodata[p].Rs) * S[p,t-water_flow_time(Resolution(1), hydrodata[p].Rs)] : 0.0)
                        + (t - water_flow_time(Resolution(1), hydrodata[p].Rs) > 1 ?
                        historic_flow(Resolution(1), hydrodata[p].Rs)*S[p,t-(water_flow_time(Resolution(1), hydrodata[p].Rq)+1)] : 0.0))
            # Water value
            if !simple_water_value
                @constraint(model, water_value_approximation[c in 1:ncuts(water_value)],
                            sum(water_value[c][p]*M[p,num_hours(horizon)]
                                for p in plants)
                            + sum(W[i]
                                  for i in cut_indices(water_value[c])) >= cut_lb(water_value[c]))
            end
        end
    end
    return stochasticmodel
end
