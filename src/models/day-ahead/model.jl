@hydromodel Stochastic DayAhead = begin
    # First stage
    # ========================================================
    @first_stage model = begin
        horizon, indices, data = stage
        @unpack hours, plants, bids, blockbids, blocks, hours_per_block = indices
        hdata = hydrodata(data)
        regulations = data.regulations
        # Variables
        # ========================================================
        @variable(model, xt_i[t = hours] >= 0)
        @variable(model, xt_d[i = bids, t = hours] >= 0)
        @variable(model, xb[i = blockbids, b = blocks], lowerbound = 0, upperbound = regulations.blocklimit)
        # Constraints
        # ========================================================
        # Increasing bid curve
        @constraint(model, bidcurve[i = bids[1:end-1], t = hours],
                    xt_d[i,t] <= xt_d[i+1,t]
                    )
        # Maximal bids
        @constraint(model, maxhourlybids[t = hours],
                    xt_i[t] + xt_d[bids[end],t] + sum(xb[i,b] for i = blockbids for b = findall(A->in(t,A),hours_per_block)) <= 1.1*sum(hdata[p].H̄ for p in plants)
                    )
    end

    # Second stage
    # =======================================================
    @second_stage model = begin
        horizon, indices, data = stage
        @unpack hours, plants, segments, blocks, hours_per_block = indices
        hdata = hydrodata(data)
        regulations = data.regulations
        ph = data.bidprices
        pb = ph[2:end-1]
        @unpack ρ = scenario
        ih(t) = begin
            idx = findlast(ph .<= ρ[t])
            return idx == nothing ? -1 : idx
        end
        ib(b) = begin
            idx = findlast(pb .<= mean(ρ[hours_per_block[b]]))
            return idx == nothing ? -1 : idx
        end
        # Variables
        # =======================================================
        # First stage
        @decision xt_i xt_d xb
        # -------------------------------------------------------
        @variable(model, yt[t = hours] >= 0)
        @variable(model, yb[b = blocks] >= 0)
        @variable(model, z_up[t = hours] >= 0)
        @variable(model, z_do[t = hours] >= 0)
        @variable(model, Q[p = plants, s = segments, t = hours], lowerbound = 0, upperbound = hdata[p].Q̄[s])
        @variable(model, S[p = plants, t = hours] >= 0)
        @variable(model, M[p = plants, t = hours], lowerbound = 0, upperbound = hdata[p].M̄)
        @variable(model, H[t = hours] >= 0)
        @variable(model, Qf[p = plants, t = hours] >= 0)
        @variable(model, Sf[p = plants, t = hours] >= 0)

        # Objectives
        # ========================================================
        # Net profit
        @expression(model, net_profit,
                    sum((ρ[t]-0.04)*yt[t]
                        for t = hours)
                    + sum(length(hours_per_block[b])*(mean(ρ[hours_per_block[b]])-0.04)*yb[b]
                          for b = blocks)
                    - sum(penalty(scenario,t)*z_up[t] - reward(scenario,t)*z_do[t]
                          for t = hours))
        # Value of stored water
        @expression(model, value_of_stored_water,
                    data.λ̄*sum(M[p,nhours(horizon)]*sum(hdata[i].μ[1]
                                                   for i = hdata.Qd[p])
                          for p = plants))
        # Define objective
        @objective(model, Max, net_profit + value_of_stored_water)

        # Constraints
        # ========================================================
        # Bid-dispatch links
        @constraint(model, hourlybids[t = hours],
                    yt[t] == ((ρ[t] - ph[ih(t)])/(ph[ih(t)+1]-ph[ih(t)]))*xt_d[ih(t)+1,t]
                         + ((ph[ih(t)+1]-ρ[t])/(ph[ih(t)+1]-ph[ih(t)]))*xt_d[ih(t),t]
                         + xt_i[t]
                    )
        @constraint(model, bidblocks[b = blocks],
                    yb[b] == sum(xb[j,b]
                                 for j = 1:ib(b)))

        # Hydrological balance
        @constraint(model, hydro_constraints[p = plants, t = hours],
                    # Previous reservoir content
                    M[p,t] == (t > 1 ? M[p,t-1] : hdata[p].M₀)
                    # Inflow
                    + sum(Qf[i,t]
                          for i = intersect(hdata.Qu[p],plants))
                    + sum(Sf[i,t]
                          for i = intersect(hdata.Su[p],plants))
                    # Local inflow
                    + hdata[p].V
                    + (t <= hdata[p].Rqh ? 1 : 0)*sum(hdata[i].Q̃
                                                      for i = hdata.Qu[p])
                    + (t == (hdata[p].Rqh + 1) ? 1 : 0)*sum(hdata[i].Q̃*(1-hdata[p].Rqm/60)
                                                            for i = hdata.Qu[p])
                    # Outflow
                    - sum(Q[p,s,t]
                          for s = segments)
                    - S[p,t]
                    )
        # Production
        @constraint(model, production[t = hours],
                    H[t] == sum(hdata[p].μ[s]*Q[p,s,t]
                                for p = plants, s = segments)
                    )
        # Load balance
        @constraint(model, loadbalance[t = hours],
                    yt[t] + sum(yb[b] for b = findall(A->in(t,A),hours_per_block)) - H[t] == z_up[t] - z_do[t]
                    )
        # Water flow: Discharge + Spillage
        @constraintref Qflow[1:length(plants),1:nhours(horizon)]
        @constraintref Sflow[1:length(plants),1:nhours(horizon)]
        for (pidx,p) = enumerate(plants)
            for t = hours
                if t - hdata[p].Rqh > 1
                    Qflow[pidx,t] = @constraint(model,
                                                Qf[p,t] == (hdata[p].Rqm/60)*sum(Q[p,s,t-(hdata[p].Rqh+1)]
                                                                                 for s = segments)
                                                + (1-hdata[p].Rqm/60)*sum(Q[p,s,t-hdata[p].Rqh]
                                                                          for s = segments)
                                                )
                elseif t - hdata[p].Rqh > 0
                    Qflow[pidx,t] = @constraint(model,
                                                Qf[p,t] == (1-hdata[p].Rqm/60)*sum(Q[p,s,t-hdata[p].Rqh]
                                                                                   for s = segments)
                                                )
                else
                    Qflow[pidx,t] = @constraint(model,
                                                Qf[p,t] == 0
                                                )
                end
                if t - hdata[p].Rsh > 1
                    Sflow[pidx,t] = @constraint(model,
                                                Sf[p,t] == (hdata[p].Rsm/60)*S[p,t-(hdata[p].Rsh+1)]
                                                + (1-hdata[p].Rsm/60)*S[p,t-hdata[p].Rsh]
                                                )
                elseif t - hdata[p].Rsh > 0
                    Sflow[pidx,t] = @constraint(model,
                                                Sf[p,t] == (1-hdata[p].Rsm/60)*S[p,t-hdata[p].Rsh]
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

DayAheadModel(modeldata::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},area::Area,river::River) = DayAheadModel(Day(),modeldata,scenarios,[area],[river])
DayAheadModel(modeldata::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},area::Area) = DayAheadModel(Day(),modeldata,scenarios,[area],[:All])
DayAheadModel(modeldata::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},areas::Vector{Area}) = DayAheadModel(Day(),modeldata,scenarios,areas,[:All])
DayAheadModel(modeldata::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},river::River) = DayAheadModel(Day(),modeldata,scenarios,[0],[river])
DayAheadModel(modeldata::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},rivers::Vector{River}) = DayAheadModel(Day(),modeldata,scenarios,[0],rivers)
DayAheadModel(modeldata::AbstractModelData,scenarios::Vector{<:AbstractScenarioData}) = DayAheadModel(Day(),modeldata,scenarios,[0],[:All])

DayAheadModel(modeldata::AbstractModelData,sampler::AbstractSampler,n::Integer,area::Area,river::River) = DayAheadModel(Day(),modeldata,sampler,n,[area],[river])
DayAheadModel(modeldata::AbstractModelData,sampler::AbstractSampler,n::Integer,area::Area) = DayAheadModel(Day(),modeldata,sampler,n,[area],[:All])
DayAheadModel(modeldata::AbstractModelData,sampler::AbstractSampler,n::Integer,areas::Vector{Area}) = DayAheadModel(Day(),modeldata,sampler,n,areas,[:All])
DayAheadModel(modeldata::AbstractModelData,sampler::AbstractSampler,n::Integer,river::River) = DayAheadModel(Day(),modeldata,sampler,n,[0],[river])
DayAheadModel(modeldata::AbstractModelData,sampler::AbstractSampler,n::Integer,rivers::Vector{River}) = DayAheadModel(Day(),modeldata,sampler,n,[0],rivers)
DayAheadModel(modeldata::AbstractModelData,sampler::AbstractSampler,n::Integer) = DayAheadModel(Day(),modeldata,sampler,n,[0],[:All])
