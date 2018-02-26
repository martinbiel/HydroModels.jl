@with_kw struct TradeRegulations{T <: AbstractFloat}
    lot::T = 0.1                  # Trade lot in MWh
    dayaheadfee::T = 0.04         # Fee for day ahead trades (EUR/MWh)
    intradayfee::T = 0.11         # Fee for intraday trades (EUR/MWh)
    blocklimit::T = 500.0         # Maximum volume (MWh) in block orders
    blockminlength::Int = 3       # Minimum amount of consecutive hours in block orders
    imbalancelimit::T = 200.0     # Maximum volume (MWh) that has to be settled in the intraday market
    lowerorderlimit::T = -500.0   # Lower technical order price limit (EUR)
    upperorderlimit::T = 3000.0   # Upper technical order price limit (EUR)
end
NordPoolRegulations() = TradeRegulations{Float64}()

struct DayAheadIndices <: AbstractModelIndices
    hours::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
    bids::Vector{Int}
    blockbids::Vector{Int}
    blocks::Vector{Int}
    hours_per_block::Vector{Vector{Int}}
end
plants(indices::DayAheadIndices) = indices.plants

struct DayAheadData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    regulations::TradeRegulations{T}
    bidprices::Vector{T}
    λ̄::T

    function (::Type{DayAheadData})(plantdata::HydroPlantCollection{T,2},regulations::TradeRegulations{T},bidprices::Vector{T},λ̄::T) where T <: AbstractFloat
        return new{T}(plantdata,regulations,bidprices,λ̄)
    end
end
function DayAheadData(plantfilename::String,pricefilename::String,λ̱::AbstractFloat,λ̄::AbstractFloat)
    regulations = NordPoolRegulations()
    bidprices = collect(linspace(λ̱,λ̄,3))
    prepend!(bidprices,regulations.lowerorderlimit)
    push!(bidprices,regulations.upperorderlimit)
    prices = PriceData(pricefilename)
    DayAheadData(HydroPlantCollection(plantfilename),regulations,bidprices,expected(prices))
end

struct DayAheadScenario{T <: AbstractFloat} <: AbstractScenarioData
    π::T                 # Scenario probability
    ρ::PriceCurve{T}     # Market price per hour

    function (::Type{DayAheadScenario})(π::AbstractFloat,ρ::PriceCurve{T}) where T <: AbstractFloat
        return new{T}(π,ρ)
    end
end

function DayAheadScenarios(pricefilename::String,npricecurves::Integer)
    scenarios = Vector{DayAheadScenario}(npricecurves)
    pricedata = PriceData(pricefilename)
    π = 1/npricecurves
    for i in 1:npricecurves
        ρ = pricedata[i][Day()]
        scenarios[i] = DayAheadScenario(π,ρ)
    end
    return scenarios
end

function StochasticPrograms.expected(scenarios::Vector{DayAheadScenario})
    π = 1.0
    ρ = [mean([s.ρ[i] for s in scenarios]) for i in 1:nhours(Day())]
    return DayAheadScenario(π,PriceCurve(ρ))
end

penalty(scenario::DayAheadScenario,t) = 1.1*scenario.ρ[t]
reward(scenario::DayAheadScenario,t) = 0.9*scenario.ρ[t]

function modelindices(data::DayAheadData, horizon::Horizon, scenarios::Vector{<:AbstractScenarioData}, areas::Vector{Area}, rivers::Vector{River})
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(hydrodata(data),areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    bids = collect(1:length(data.bidprices))
    blockbids = collect(1:length(data.bidprices)-2)
    hours_per_block = [collect(h:ending) for h in hours for ending in hours[h+data.regulations.blockminlength-1:end]]
    blocks = collect(1:length(hours_per_block))
    return DayAheadIndices(hours, plants, segments, bids, blockbids, blocks, hours_per_block)
end

@hydromodel Stochastic DayAhead = begin
    @unpack hours, plants, segments, bids, blockbids, blocks, hours_per_block = indices
    hdata = hydrodata(data)
    regulations = data.regulations
    ph = data.bidprices
    pb = ph[2:end-1]

    # First stage
    # ========================================================
    @first_stage model = begin
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
                    xt_i[t] + xt_d[bids[end],t] + sum(xb[i,b] for i = blockbids for b = find(A->in(t,A),hours_per_block)) <= 1.1*sum(hdata[p].H̄ for p in plants)
                    )
    end

    # Second stage
    # =======================================================
    @second_stage model = begin
        @unpack ρ = scenario
        ih(t) = findlast(ph .<= ρ[t])
        ib(b) = findlast(pb .<= mean(ρ[hours_per_block[b]]))
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
                    yt[t] + sum(yb[b] for b = find(A->in(t,A),hours_per_block)) - H[t] == z_up[t] - z_do[t]
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

function strategy(model::DayAheadModel; variant = :rp)
    status(model; variant = variant) == :Planned || error("Hydro model has not been planned yet")

    return OrderStrategy(model)
end
