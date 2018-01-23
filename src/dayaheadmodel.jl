mutable struct DayAheadModel <: StochasticHydroModel
    # Parameters
    # ========================================================
    horizon::Horizon           # Time horizon to simulate
    rivers::Vector{River}      # Rivers to include (can be all)
    areas::Vector{Area}        # Areas to include (can be all)

    # Model data
    # ========================================================
    modeldata::HydroModelData
    regulations::TradeRegulations
    scenariodata::Vector{DayAheadScenario}
    bidprices::AbstractVector

    # Model indices
    # ========================================================
    scenarios
    plants
    segments
    hours
    bids
    blocks
    hours_per_block

    # Model variables
    # ========================================================
    # Model variables
    # xt_i - Price independent bid volume each hour
    # xt_d - Price dependent bid volume each hour
    # xb   - Block bid volumes for each block
    # yt   - Dispatched volumes for each scenario/hour
    # yb   - Dispatched block volume for each scenario/block
    # z_up - Penalized imbalance for each scenario/hour
    # z_do - Rewarded imbalance for each scenario/hour
    # Q    - Discharge for each scenario/plant/segment/hour
    # S    - Spillage for each scenario/plant/hour
    # M    - Reservoir content for each scenario/plant/hour
    # H    - Production for each scenario/hour

    # Models and solvers
    internalmodels::Dict{Symbol,JuMPModel}
    optimsolver::AbstractMathProgSolver
    status::Dict{Symbol,Symbol}

    # Constructor
    # ========================================================
    function DayAheadModel(modeldata::HydroModelData,regulations::TradeRegulations,numscenarios::Int64, areas::Vector{Area}, rivers::Vector{River})
        model = new()
        model.horizon = Day()
        model.modeldata = modeldata
        model.regulations = regulations
        model.scenariodata = Vector{DayAheadScenario}(numscenarios)
        model.bidprices = Vector{Float64}()
        model.internalmodels = Dict{Symbol,JuMPModel}()

        model.status = Dict(:dep=>:Unplanned,:struct=>:Unplanned,:evp=>:Unplanned)

        initialize!(model,areas,rivers)

        return model
    end
end

DayAheadModel(modeldata::HydroModelData,numscenarios::Int64,area::Area) = DayAheadTermModel(modeldata,NordPoolRegulations(),numscenarios,[area],["All"])
DayAheadModel(modeldata::HydroModelData,numscenarios::Int64,areas::Vector{Area}) = DayAheadModel(modeldata,NordPoolRegulations(),numscenarios,areas,["All"])
DayAheadModel(modeldata::HydroModelData,numscenarios::Int64,area::Area,rivers...) = DayAheadModel(modeldata,NordPoolRegulations(),numscenarios,[area],[rivers...])
DayAheadModel(modeldata::HydroModelData,numscenarios::Int64,areas::Vector{Area},rivers...) = DayAheadModel(modeldata,NordPoolRegulations(),numscenarios,areas,[rivers...])
DayAheadModel(modeldata::HydroModelData,numscenarios::Int64,rivers...) = DayAheadModel(modeldata,NordPoolRegulations(),numscenarios,[0],[rivers...])
DayAheadModel(modeldata::HydroModelData,numscenarios::Int64) = DayAheadModel(modeldata,numscenarios,0,"All")

modelname(model::DayAheadModel) = "Day Ahead"
numscenarios(model::DayAheadModel) = length(model.scenariodata)

function changehorizon!(model::DayAheadModel,newhorizon::Int64)
    warn("Cannot change horizon of Day Ahead model.")
    throw(MethodError(changehorizon!, Tuple{DayAheadModel,Int64}))
end

function changehorizon!(model::DayAheadModel,newweeks::Int64,newdays::Int64)
    warn("Cannot change horizon of Day Ahead model.")
    throw(MethodError(changehorizon!, Tuple{DayAheadModel,Int64,Int64}))
end

function define_model_indices(model::DayAheadModel)
    model.scenarios = collect(1:numscenarios(model))
    model.bids = collect(1:length(model.bidprices))
    model.hours_per_block = [collect(h:ending) for h in model.hours for ending in model.hours[h+model.regulations.blockminlength-1:end]]
    model.blocks = collect(1:length(model.hours_per_block))
end

function define_bid_prices(model::DayAheadModel)
    λ_max = 1.1*maximum(model.modeldata.λ[1:24,1:numscenarios(model)])
    λ_min = 0.9*minimum(model.modeldata.λ[1:24,1:numscenarios(model)])
    model.bidprices = collect(linspace(λ_min,λ_max,3))
    prepend!(model.bidprices,model.regulations.lowerorderlimit)
    push!(model.bidprices,model.regulations.upperorderlimit)
end

function define_scenarios(model::DayAheadModel)
    π = 1/numscenarios(model)
    for s in 1:numscenarios(model)
        ρ = model.modeldata.λ[1:24,s]
        ρ̅ = Vector{Float64}(length(model.blocks))
        for block in model.blocks
            ρ̅[block] = mean(ρ[model.hours_per_block[block]])
         end
        model.scenariodata[s] = DayAheadScenario(π,ρ,ρ̅)
    end
end

function define_specific_model(model::DayAheadModel)
    define_bid_prices(model)
    define_model_indices(model)
    define_scenarios(model)
end

function define_dep_problem(model::DayAheadModel)
    @assert length(model.modeldata.λ) >= hours(model.horizon) "Not enough price data for day ahead model"
    @assert size(model.modeldata.λ,2) >= numscenarios(model) "Not enough price data for chosen number of scenarios"
    model.internalmodels[:dep] = Model()
    internalmodel = model.internalmodels[:dep]

    params = model.modeldata
    regulations = model.regulations
    scenarios = model.scenariodata
    bidprices = model.bidprices

    # Define JuMP model
    # ========================================================
    # Variables
    # ========================================================
    @variable(internalmodel,xt_i[t = model.hours] >= 0)
    @variable(internalmodel,xt_d[i = model.bids, t = model.hours] >= 0)
    @variable(internalmodel,xb[i = model.bids, b = model.blocks],lowerbound = 0, upperbound = regulations.blocklimit)
    @variable(internalmodel,yt[s = model.scenarios, t = model.hours] >= 0)
    @variable(internalmodel,yb[s = model.scenarios, b = model.blocks] >= 0)
    @variable(internalmodel,z_up[s = model.scenarios, t = model.hours] >= 0)
    @variable(internalmodel,z_do[s = model.scenarios, t = model.hours] >= 0)
    @variable(internalmodel,Q[s = model.scenarios, p = model.plants, q = model.segments, t = model.hours],lowerbound = 0, upperbound = params.Q̅[(p,q)])
    @variable(internalmodel,S[s = model.scenarios, p = model.plants, t = model.hours] >= 0)
    @variable(internalmodel,M[s = model.scenarios, p = model.plants, t = model.hours],lowerbound = 0,upperbound = params.M̅[p])
    @variable(internalmodel,H[s = model.scenarios, t = model.hours] >= 0)
    @variable(internalmodel,Qf[s = model.scenarios, p = model.plants, t = model.hours] >= 0)
    @variable(internalmodel,Sf[s = model.scenarios, p = model.plants, t = model.hours] >= 0)

    # Objectives
    # ========================================================
    # Net profit
    @expression(internalmodel, net_profit,
                sum(scenarios[s].π*(sum((scenarios[s].ρ[t]-0.04)*yt[s,t]
                                        for t = model.hours)
                                    + sum(length(model.hours_per_block[b])*(scenarios[s].ρ̅[b]-0.04)*yb[s,b]
                                          for b = model.blocks)
                                    - sum(penalty(scenarios[s],t)*z_up[s,t] - reward(scenarios[s],t)*z_do[s,t]
                                          for t = model.hours))
                    for s in model.scenarios))
    # Value of stored water
    @expression(internalmodel,value_of_stored_water,
                sum(scenarios[s].π*params.λ_f*sum(M[s,p,hours(model.horizon)]*sum(params.μ[i,1]
                                                                                for i = params.Qd[p])
                                                       for p = model.plants)
                for s = model.scenarios))
    # Define objective
    @objective(internalmodel, Max, net_profit + value_of_stored_water)

    # Constraints
    # ========================================================
    # Increasing bid curve
    @constraint(internalmodel,bidcurve[i = model.bids[1:end-1], t = model.hours],
                xt_d[i,t] <= xt_d[i+1,t]
                )
    # Maximal bids
    @constraint(internalmodel,maxhourlybids[t = model.hours],
                xt_i[t] + xt_d[model.bids[end],t] + sum(xb[i,b] for i = model.bids for b = find(A->in(t,A),model.hours_per_block)) <= 1.1*sum(params.H̅[p] for p in model.plants)
                )

    # Bid-dispatch links
    ih(t,s) = findlast(bidprices .<= scenarios[s].ρ[t])
    ib(b,s) = findlast(bidprices .<= scenarios[s].ρ̅[b])
    @constraint(internalmodel,hourlybids[s = model.scenarios, t = model.hours],
                yt[s,t] == ((scenarios[s].ρ[t] - bidprices[ih(t,s)])/(bidprices[ih(t,s)+1]-bidprices[ih(t,s)]))*xt_d[ih(t,s)+1,t]
                + ((bidprices[ih(t,s)+1]-scenarios[s].ρ[t])/(bidprices[ih(t,s)+1]-bidprices[ih(t,s)]))*xt_d[ih(t,s),t]
                + xt_i[t]
                )
    @constraint(internalmodel,blockbids[s = model.scenarios, b = model.blocks],
                yb[s,b] == sum(xb[j,b]
                               for j = 1:ib(b,s)))

    # Hydrological balance
    @constraint(internalmodel,hydro_constraints[s = model.scenarios, p = model.plants, t = model.hours],
                # Previous reservoir content
                M[s,p,t] == (t > 1 ? M[s,p,t-1] : params.M₀[p])
                # Inflow
                + sum(Qf[s,i,t]
                      for i = intersect(params.Qu[p],model.plants))
                + sum(Sf[s,i,t]
                      for i = intersect(params.Su[p],model.plants))
                # Local inflow
                + params.V[p]
                + (t <= params.Rqh[p] ? 1 : 0)*sum(params.Qavg[i]
                                                   for i = params.Qu[p])
                + (t == (params.Rqh[p] + 1) ? 1 : 0)*sum(params.Qavg[i]*(1-params.Rqm[p]/60)
                                                         for i = params.Qu[p])
                # Outflow
                - sum(Q[s,p,q,t]
                      for q = model.segments)
                - S[s,p,t]
                )

    # Discharge flow + Spillage flow
    @constraintref Qflow[1:numscenarios(model),1:length(model.plants),1:hours(model.horizon)]
    @constraintref Sflow[1:numscenarios(model),1:length(model.plants),1:hours(model.horizon)]
    for s in model.scenarios
        for (pidx,p) in enumerate(model.plants)
            for t in model.hours
                if t - params.Rqh[p] > 1
                    Qflow[s,pidx,t] = @constraint(internalmodel,
                                                  Qf[s,p,t] == (params.Rqm[p]/60)*sum(Q[s,p,q,t-(params.Rqh[p]+1)]
                                                                                  for q = model.segments)
                                                + (1-params.Rqm[p]/60)*sum(Q[s,p,q,t-params.Rqh[p]]
                                                                           for q = model.segments)
                                                )
                elseif t - params.Rqh[p] > 0
                    Qflow[s,pidx,t] = @constraint(internalmodel,
                                                  Qf[s,p,t] == (1-params.Rqm[p]/60)*sum(Q[s,p,q,t-params.Rqh[p]]
                                                                                        for q = model.segments)
                                                  )
                else
                    Qflow[s,pidx,t] = @constraint(internalmodel,
                                                  Qf[s,p,t] == 0
                                                  )
                end
                if t - params.Rsh[p] > 1
                    Sflow[s,pidx,t] = @constraint(internalmodel,
                                                  Sf[s,p,t] == (params.Rsm[p]/60)*S[s,p,t-(params.Rsh[p]+1)]
                                                + (1-params.Rsm[p]/60)*S[s,p,t-params.Rsh[p]]
                                                  )
                elseif t - params.Rsh[p] > 0
                    Sflow[s,pidx,t] = @constraint(internalmodel,
                                                  Sf[s,p,t] == (1-params.Rsm[p]/60)*S[s,p,t-params.Rsh[p]]
                                                  )
                else
                    Sflow[s,pidx,t] = @constraint(internalmodel,
                                                  Sf[s,p,t] == 0
                                                  )
                end
            end
        end
    end

    # Production
    @constraint(internalmodel,production[s = model.scenarios, t = model.hours],
                H[s,t] == sum(params.μ[p,q]*Q[s,p,q,t]
                            for p = model.plants, q = model.segments)
                )

    # Load balance
    @constraint(internalmodel,loadbalance[s = model.scenarios, t = model.hours],
                yt[s,t] + sum(yb[s,b]
                                        for b = find(A->in(t,A),model.hours_per_block))
                - H[s,t] == z_up[s,t] - z_do[s,t]
                )
end

function define_dep_structjump_problem(model::DayAheadModel)
    @assert length(model.modeldata.λ) >= hours(model.horizon) "Not enough price data for day ahead model"
    @assert size(model.modeldata.λ,2) >= numscenarios(model) "Not enough price data for chosen number of scenarios"

    model.internalmodels[:struct] = StructuredModel(num_scenarios = numscenarios(model))
    internalmodel = model.internalmodels[:struct]
    internalmodel.objSense = :Max
    params = model.modeldata
    regulations = model.regulations
    scenarios = model.scenariodata
    bidprices = model.bidprices

    ih(t,s) = findlast(bidprices .<= scenarios[s].ρ[t])
    ib(b,s) = findlast(bidprices .<= scenarios[s].ρ̅[b])

    # Define StructJuMP model
    # ========================================================
    # First stage
    # ========================================================
    # Variables
    # ========================================================
    @variable(internalmodel,xt_i[t = model.hours] >= 0)
    @variable(internalmodel,xt_d[i = model.bids, t = model.hours] >= 0)
    @variable(internalmodel,xb[i = model.bids, b = model.blocks],lowerbound = 0, upperbound = regulations.blocklimit)
    # Constraints
    # ========================================================
    # Increasing bid curve
    @constraint(internalmodel,bidcurve[i = model.bids[1:end-1], t = model.hours],
                xt_d[i,t] <= xt_d[i+1,t]
                )
    # Maximal bids
    @constraint(internalmodel,maxhourlybids[t = model.hours],
                xt_i[t] + xt_d[model.bids[end],t] + sum(xb[i,b] for i = model.bids for b = find(A->in(t,A),model.hours_per_block)) <= 1.1*sum(params.H̅[p] for p in model.plants)
                )

    # Second stage
    # =======================================================
    for s in 1:numscenarios(model)
        block = StructuredModel(parent = internalmodel, id = s)
        # Variables
        # =======================================================
        @variable(block,yt[t = model.hours] >= 0)
        @variable(block,yb[b = model.blocks] >= 0)
        @variable(block,z_up[t = model.hours] >= 0)
        @variable(block,z_do[t = model.hours] >= 0)
        @variable(block,Q[p = model.plants, q = model.segments, t = model.hours],lowerbound = 0,upperbound = params.Q̅[(p,q)])
        @variable(block,S[p = model.plants, t = model.hours] >= 0)
        @variable(block,M[p = model.plants, t = model.hours],lowerbound = 0,upperbound = params.M̅[p])
        @variable(block,H[t = model.hours] >= 0)
        @variable(block, Qf[p = model.plants, t = model.hours] >= 0)
        @variable(block, Sf[p = model.plants, t = model.hours] >= 0)

        # Objectives
        # ========================================================
        # Net profit
        @expression(block, net_profit,
                    sum((scenarios[s].ρ[t]-0.04)*yt[t]
                        for t = model.hours)
                    + sum(length(model.hours_per_block[b])*(scenarios[s].ρ̅[b]-0.04)*yb[b]
                          for b = model.blocks)
                    - sum(penalty(scenarios[s],t)*z_up[t] - reward(scenarios[s],t)*z_do[t]
                          for t = model.hours))
        # Value of stored water
        @expression(block,value_of_stored_water,
        params.λ_f*sum(M[p,hours(model.horizon)]*sum(params.μ[i,1]
                                                for i = params.Qd[p])
                       for p = model.plants))
        # Define objective
        @objective(block, Max, net_profit + value_of_stored_water)

        # Constraints
        # ========================================================
        # Bid-dispatch links
        @constraint(block,hourlybids[t = model.hours],
                    yt[t] == ((scenarios[s].ρ[t] - bidprices[ih(t,s)])/(bidprices[ih(t,s)+1]-bidprices[ih(t,s)]))*xt_d[ih(t,s)+1,t]
                    + ((bidprices[ih(t,s)+1]-scenarios[s].ρ[t])/(bidprices[ih(t,s)+1]-bidprices[ih(t,s)]))*xt_d[ih(t,s),t]
                    + xt_i[t]
                    )
        @constraint(block,blockbids[b = model.blocks],
                    yb[b] == sum(xb[j,b]
                                 for j = 1:ib(b,s)))

        # Hydrological balance
        @constraint(block,hydro_constraints[p = model.plants, t = model.hours],
                    # Previous reservoir content
                    M[p,t] == (t > 1 ? M[p,t-1] : params.M₀[p])
                    # Inflow
                    + sum(Qf[i,t]
                          for i = intersect(params.Qu[p],model.plants))
                    + sum(Sf[i,t]
                          for i = intersect(params.Su[p],model.plants))
                    # Local inflow
                    + params.V[p]
                    + (t <= params.Rqh[p] ? 1 : 0)*sum(params.Qavg[i]
                                                       for i = params.Qu[p])
                    + (t == (params.Rqh[p] + 1) ? 1 : 0)*sum(params.Qavg[i]*(1-params.Rqm[p]/60)
                                                             for i = params.Qu[p])
                    # Outflow
                    - sum(Q[p,q,t]
                          for q = model.segments)
                    - S[p,t]
                    )
        # Production
        @constraint(block,production[t = model.hours],
                    H[t] == sum(params.μ[p,q]*Q[p,q,t]
                                for p = model.plants, q = model.segments)
                    )
        # Load balance
        @constraint(block,loadbalance[t = model.hours],
                    yt[t] + sum(yb[b] for b = find(A->in(t,A),model.hours_per_block)) - H[t] == z_up[t] - z_do[t]
                    )
        # Discharge flow + Spillage flow
        @constraintref Qflow[1:length(model.plants),1:hours(model.horizon)]
        @constraintref Sflow[1:length(model.plants),1:hours(model.horizon)]
        for (pidx,p) in enumerate(model.plants)
            for t = model.hours
                if t - params.Rqh[p] > 1
                    Qflow[pidx,t] = @constraint(block,
                                                Qf[p,t] == (params.Rqm[p]/60)*sum(Q[p,q,t-(params.Rqh[p]+1)]
                                                                                  for q = model.segments)
                                                + (1-params.Rqm[p]/60)*sum(Q[p,q,t-params.Rqh[p]]
                                                                           for q = model.segments)
                                                )
                elseif t - params.Rqh[p] > 0
                    Qflow[pidx,t] = @constraint(block,
                                                Qf[p,t] == (1-params.Rqm[p]/60)*sum(Q[p,q,t-params.Rqh[p]]
                                                                                    for q = model.segments)
                                                )
                else
                    Qflow[pidx,t] = @constraint(block,
                                                Qf[p,t] == 0
                                                )
                end
                if t - params.Rsh[p] > 1
                    Sflow[pidx,t] = @constraint(block,
                                                Sf[p,t] == (params.Rsm[p]/60)*S[p,t-(params.Rsh[p]+1)]
                                                + (1-params.Rsm[p]/60)*S[p,t-params.Rsh[p]]
                                                )
                elseif t - params.Rsh[p] > 0
                    Sflow[pidx,t] = @constraint(block,
                                                Sf[p,t] == (1-params.Rsm[p]/60)*S[p,t-params.Rsh[p]]
                                                )
                else
                    Sflow[pidx,t] = @constraint(block,
                                                Sf[p,t] == 0
                                                )
                end
            end
        end
    end
end

function define_evp_problem(model::DayAheadModel)
    @assert length(model.modeldata.λ) >= hours(model.horizon) "Not enough price data for day ahead model"
    @assert size(model.modeldata.λ,2) >= numscenarios(model) "Not enough price data for chosen number of scenarios"
    model.internalmodels[:evp] = Model()
    internalmodel = model.internalmodels[:evp]
    params = model.modeldata
    regulations = model.regulations
    scenario = expected(model.scenariodata)
    bidprices = model.bidprices

    # Define JuMP model
    # ========================================================
    # Variables
    # ========================================================
    @variable(internalmodel,xt_i[t = model.hours] >= 0)
    @variable(internalmodel,xt_d[i = model.bids, t = model.hours] >= 0)
    @variable(internalmodel,xb[i = model.bids, b = model.blocks], lowerbound = 0, upperbound = regulations.blocklimit)
    @variable(internalmodel,yt[t = model.hours] >= 0)
    @variable(internalmodel,yb[b = model.blocks] >= 0)
    @variable(internalmodel,z_up[t = model.hours] >= 0)
    @variable(internalmodel,z_do[t = model.hours] >= 0)
    @variable(internalmodel,Q[p = model.plants, q = model.segments, t = model.hours],lowerbound = 0, upperbound = params.Q̅[(p,q)])
    @variable(internalmodel,S[p = model.plants, t = model.hours] >= 0)
    @variable(internalmodel,M[p = model.plants, t = model.hours],lowerbound = 0,upperbound = params.M̅[p])
    @variable(internalmodel,H[t = model.hours] >= 0)
    @variable(internalmodel, Qf[p = model.plants, t = model.hours] >= 0)
    @variable(internalmodel, Sf[p = model.plants, t = model.hours] >= 0)

    # Objectives
    # ========================================================
    # Net profit
    @expression(internalmodel, net_profit,
                (sum((scenario.ρ[t]-0.04)*yt[t]
                     for t = model.hours)
                 + sum(length(model.hours_per_block[b])*(scenario.ρ̅[b]-0.04)*yb[b]
                       for b = model.blocks)
                 - sum(penalty(scenario,t)*z_up[t] - reward(scenario,t)*z_do[t]
                       for t = model.hours))
                )
    # Value of stored water
    @expression(internalmodel,value_of_stored_water,
                params.λ_f*sum(M[p,hours(model.horizon)]*sum(params.μ[i,1]
                                                      for i = params.Qd[p])
                               for p = model.plants)
                )
    # Define objective
    @objective(internalmodel, Max, net_profit + value_of_stored_water)

    # Constraints
    # ========================================================
    # Increasing bid curve
    @constraint(internalmodel,bidcurve[i = model.bids[1:end-1], t = model.hours],
                xt_d[i,t] <= xt_d[i+1,t]
                )

    # Maximal bids
    @constraint(internalmodel,maxhourlybids[t = model.hours],
                xt_i[t] + xt_d[model.bids[end],t] + sum(xb[i,b] for i = model.bids for b = find(A->in(t,A),model.hours_per_block)) <= 1.1*sum(params.H̅[p] for p in model.plants)
                )

    # Bid-dispatch links
    ih(t) = findlast(bidprices .<= scenario.ρ[t])
    ib(b) = findlast(bidprices .<= scenario.ρ̅[b])
    @constraint(internalmodel,hourlybids[t = model.hours],
                yt[t] == ((scenario.ρ[t] - bidprices[ih(t)])/(bidprices[ih(t)+1]-bidprices[ih(t)]))*xt_d[ih(t)+1,t]
                + ((bidprices[ih(t)+1]-scenario.ρ[t])/(bidprices[ih(t)+1]-bidprices[ih(t)]))*xt_d[ih(t),t]
                + xt_i[t]
                )
    @constraint(internalmodel,blockbids[b = model.blocks],
                yb[b] == sum(xb[j,b]
                             for j = 1:ib(b)))

    # Hydrological balance
    @constraint(internalmodel,hydro_constraints[p = model.plants, t = model.hours],
                # Previous reservoir content
                M[p,t] == (t > 1 ? M[p,t-1] : params.M₀[p])
                # Inflow
                + sum(Qf[i,t]
                      for i = intersect(params.Qu[p],model.plants))
                + sum(Sf[i,t]
                      for i = intersect(params.Su[p],model.plants))
                # Local inflow
                + params.V[p]
                + (t <= params.Rqh[p] ? 1 : 0)*sum(params.Qavg[i]
                                                   for i = params.Qu[p])
                + (t == (params.Rqh[p] + 1) ? 1 : 0)*sum(params.Qavg[i]*(1-params.Rqm[p]/60)
                                                         for i = params.Qu[p])
                # Outflow
                - sum(Q[p,q,t]
                      for q = model.segments)
                - S[p,t]
                )

    # Discharge flow + Spillage flow
    @constraintref Qflow[1:length(model.plants),1:hours(model.horizon)]
    @constraintref Sflow[1:length(model.plants),1:hours(model.horizon)]
    for (pidx,p) in enumerate(model.plants)
        for t in model.hours
            if t - params.Rqh[p] > 1
                Qflow[pidx,t] = @constraint(internalmodel,
                                            Qf[p,t] == (params.Rqm[p]/60)*sum(Q[p,q,t-(params.Rqh[p]+1)]
                                                                              for q = model.segments)
                                            + (1-params.Rqm[p]/60)*sum(Q[p,q,t-params.Rqh[p]]
                                                                       for q = model.segments)
                                            )
            elseif t - params.Rqh[p] > 0
                Qflow[pidx,t] = @constraint(internalmodel,
                                            Qf[p,t] == (1-params.Rqm[p]/60)*sum(Q[p,q,t-params.Rqh[p]]
                                                                                for q = model.segments)
                                            )
            else
                Qflow[pidx,t] = @constraint(internalmodel,
                                            Qf[p,t] == 0
                                            )
            end
            if t - params.Rsh[p] > 1
                Sflow[pidx,t] = @constraint(internalmodel,
                                            Sf[p,t] == (params.Rsm[p]/60)*S[p,t-(params.Rsh[p]+1)]
                                            + (1-params.Rsm[p]/60)*S[p,t-params.Rsh[p]]
                                            )
            elseif t - params.Rsh[p] > 0
                Sflow[pidx,t] = @constraint(internalmodel,
                                            Sf[p,t] == (1-params.Rsm[p]/60)*S[p,t-params.Rsh[p]]
                                            )
            else
                Sflow[pidx,t] = @constraint(internalmodel,
                                            Sf[p,t] == 0
                                            )
            end
        end
    end

    # Production
    @constraint(internalmodel,production[t = model.hours],
                H[t] == sum(params.μ[p,q]*Q[p,q,t]
                            for p = model.plants, q = model.segments)
                )

    # Load balance
    @constraint(internalmodel,loadbalance[t = model.hours],
                yt[t] + sum(yb[b] for b = find(A->in(t,A),model.hours_per_block)) - H[t] == z_up[t] - z_do[t]
                )
end

function evp_production(model::DayAheadModel)
    @assert status(model, variant = :evp) == :Planned "Hydro model has not been planned yet"
    return ProductionPlan(model.horizon,model.modeldata,model.plants,model.internalmodels[:evp])
end

function production(model::DayAheadModel, scenario::Int64; variant = :dep)
    if (variant == :evp)
        throw(ArgumentError("Use evp_production for the production from the expected value problem"))
    end
    @assert status(model; variant = variant) == :Planned "Hydro model has not been planned yet"
    if !(scenario >= 1 && scenario <= numscenarios(model))
        throw(ArgumentError(@sprintf("Given scenario %d outside range of stochastic hydro model",scenario)))
    end

    modelvariant = model.internalmodels[variant]

    if variant == :struct
        return ProductionPlan(model.horizon,model.modeldata,model.plants,getchildren(modelvariant)[scenario])
    else
        return ProductionPlan(model.horizon,model.modeldata,model.plants,modelvariant,scenario)
    end
end

function production(model::DayAheadModel; variant = :dep)
    @assert status(model; variant = variant) == :Planned "Hydro model has not been planned yet"

    return mean([production(model,scenario) for scenario in 1:numscenarios(model)])
end

function strategy(model::DayAheadModel; variant = :dep)
    @assert status(model; variant = variant) == :Planned "Hydro model has not been planned yet"

    return OrderStrategy(model.horizon,model.regulations,model.bidprices,model.internalmodels[variant])
end
