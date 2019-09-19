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
            active_blocks(t) = findall(A->in(t,A),hours_per_block)
            # Variables
            # ========================================================
            @variable(model, xᴵ[t = hours] >= 0)
            @variable(model, xᴰ[i = bids, t = hours] >= 0)
            if use_blockbids
                @variable(model, xᴮ[i = blockbids, b = blocks], lowerbound = 0, upperbound = regulations.blocklimit)
            else
                @variable(model, xᴮ)
            end
            # Constraints
            # ========================================================
            # Increasing bid curve
            @constraint(model, bidcurve[i = bids[1:end-1], t = hours],
                xᴰ[i,t] <= xᴰ[i+1,t]
            )
            # Maximal bids
            if use_blockbids
                @constraint(model, maxhourlybids[t = hours],
                    xᴵ[t] + xᴰ[bids[end],t] + sum(xᴮ[i,b]
                        for i in blockbids for b in active_blocks(t))
                            <= 2*sum(hydrodata[p].H̄ for p in plants)
                )
            else
                @constraint(model, maxhourlybids[t = hours],
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
            @unpack hydrodata, water_value, regulations, intraday_trading, penalty_percentage, use_blockbids, bidlevels = data
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
            active_blocks(t) = findall(A->in(t,A),hours_per_block)
            # Variables
            # =======================================================
            # First stage
            @decision xᴵ xᴰ xᴮ
            # -------------------------------------------------------
            @variable(model, yᴴ[t = hours] >= 0)
            if use_blockbids
                @variable(model, yᴮ[b = blocks] >= 0)
            end
            if intraday_trading
                @variable(model, y⁺[t = hours] >= 0)
                @variable(model, y⁻[t = hours] >= 0)
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
                    sum((ρ[t]-regulations.dayaheadfee)*yᴴ[t]
                        for t = hours)
                    + sum(length(hours_per_block[b])*(mean(ρ[hours_per_block[b]])-regulations.dayaheadfee)*yᴮ[b]
                        for b = blocks))
            else
                @expression(model, net_profit,
                    sum((ρ[t]-regulations.dayaheadfee)*yᴴ[t]
                        for t in hours))
            end
            # Intraday
            if intraday_trading
                @expression(model, intraday,
                            sum((penalty(ξ,α,t)*y⁺[t] + regulations.intradayfee) - (reward(ξ,β,t) - regulations.intradayfee)*y⁻[t]
                                for t in hours))
            end
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
                yᴴ[t] == interpolate(ρ, bidlevels, xᴰ, t) + xᴵ[t]
            )
            if use_blockbids
                @constraint(model, bidblocks[b = blocks],
                    yᴮ[b] == sum(xᴮ[j,b]
                        for j in 1:ib(b)))
            end

            # Hydrological balance
            @constraint(model, hydro_constraints[p = plants, t = hours],
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
            @constraint(model, production[t = hours],
                H[t] == sum(hydrodata[p].μ[s]*Q[p,s,t]
                    for p in plants, s in segments)
            )
            # Load balance
            if intraday_trading
                if use_blockbids
                    @constraint(model, loadbalance[t = hours],
                        yᴴ[t] + sum(yᴮ[b] for b in active_blocks(t)) - H[t] == y⁺[t] - y⁻[t]
                    )
                else
                    @constraint(model, loadbalance[t = hours],
                        yᴴ[t] - H[t] == y⁺[t] - y⁻[t]
                    )
                end
            else
                if use_blockbids
                    @constraint(model, loadbalance[t = hours],
                        yᴴ[t] + sum(yᴮ[b] for b in active_blocks(t)) == H[t]
                    )
                else
                    @constraint(model, loadbalance[t = hours],
                        yᴴ[t] == H[t]
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
                                 for s in segments)
                            + (1-hydrodata[p].Rqm/60)*sum(Q[p,s,t-hydrodata[p].Rqh]
                                 for s in segments)
                        )
                    elseif t - hydrodata[p].Rqh > 0
                        Qflow[pidx,t] = @constraint(model,
                            Qf[p,t] == (1-hydrodata[p].Rqm/60)*sum(Q[p,s,t-hydrodata[p].Rqh]
                                 for s in segments)
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
