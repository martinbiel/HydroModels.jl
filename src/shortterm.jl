
mutable struct ShortTermModel <: DeterministicHydroModel
    # Parameters
    # ========================================================
    horizon::Horizon           # Time horizon to simulate
    rivers::Vector{String}     # Rivers to include (can be all)

    # Model data
    # ========================================================
    modeldata::HydroModelData

    # Model indices
    # ========================================================
    plants
    segments
    hours

    # Model and solver
    internalmodel::JuMPModel
    optimsolver::AbstractMathProgSolver
    status::Symbol

    # Constructor
    # ========================================================
    function ShortTermModel(modeldata::HydroModelData, horizon::Horizon, areas::Vector{Area}, rivers::Vector{River})
        model = new()
        model.horizon = horizon
        model.rivers = rivers
        model.modeldata = modeldata
        model.status = :Unplanned

        initialize!(model,areas,rivers)

        return model
    end
end

ShortTermModel(modeldata::HydroModelData,horizon::Horizon,area::Area) = ShortTermModel(modeldata,horizon,[area],["All"])
ShortTermModel(modeldata::HydroModelData,horizon::Horizon,areas::Vector{Area}) = ShortTermModel(modeldata,horizon,areas,["All"])
ShortTermModel(modeldata::HydroModelData,horizon::Horizon,area::Area,rivers...) = ShortTermModel(modeldata,horizon,[area],[rivers...])
ShortTermModel(modeldata::HydroModelData,horizon::Horizon,areas::Vector{Area},rivers...) = ShortTermModel(modeldata,horizon,areas,[rivers...])
ShortTermModel(modeldata::HydroModelData,horizon::Horizon,rivers...) = ShortTermModel(modeldata,horizon,[0],[rivers...])
ShortTermModel(modeldata::HydroModelData,horizon::Horizon) = ShortTermModel(modeldata,horizon,0,"All")

modelname(model::ShortTermModel) = "Short Term"

function define_planning_problem(model::ShortTermModel)
    @assert length(model.modeldata.λ) >= hours(model.horizon) "Not enough price data for chosen horizon"
    model.internalmodel = Model()
    params = model.modeldata

    # Define JuMP model
    # ========================================================
    # Variables
    # ========================================================
    @variable(model.internalmodel,Q[p = model.plants, s = model.segments, t = model.hours],lowerbound = 0, upperbound = params.Q̅[(p,s)])
    @variable(model.internalmodel,S[p = model.plants, t = model.hours] >= 0)
    @variable(model.internalmodel,M[p = model.plants, t = model.hours],lowerbound = 0,upperbound = params.M̅[p])
    @variable(model.internalmodel,H[t = model.hours] >= 0)
    @variable(model.internalmodel, Qf[p = model.plants, t = model.hours] >= 0)
    @variable(model.internalmodel, Sf[p = model.plants, t = model.hours] >= 0)

    # Objectives
    # ========================================================
    # Net profit
    @expression(model.internalmodel, net_profit, sum(params.λ[t]*H[t] for t = model.hours))
    # Value of stored water
    @expression(model.internalmodel,value_of_stored_water,
                params.λ_f*sum(M[p,hours(model.horizon)]*sum(params.μ[i,1]
                                                      for i = params.Qd[p])
                               for p = model.plants))
    # Define objective
    @objective(model.internalmodel, Max, net_profit + value_of_stored_water)

    # Constraints
    # ========================================================
    # Hydrological balance
    @constraint(model.internalmodel,hydro_constraints[p = model.plants, t = model.hours],
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
                - sum(Q[p,s,t]
                      for s = model.segments)
                - S[p,t]
                )
    # Water flow
    # Discharge flow
    @constraintref Qflow[1:length(model.plants),1:hours(model.horizon)]
    @constraintref Sflow[1:length(model.plants),1:hours(model.horizon)]
    for (pidx,p) = enumerate(model.plants)
        for t = model.hours
            if t - params.Rqh[p] > 1
                Qflow[pidx,t] = @constraint(model.internalmodel,
                                            Qf[p,t] == (params.Rqm[p]/60)*sum(Q[p,s,t-(params.Rqh[p]+1)]
                                                                              for s = model.segments)
                                            + (1-params.Rqm[p]/60)*sum(Q[p,s,t-params.Rqh[p]]
                                                                       for s = model.segments)
                                            )
            elseif t - params.Rqh[p] > 0
                Qflow[pidx,t] = @constraint(model.internalmodel,
                                            Qf[p,t] == (1-params.Rqm[p]/60)*sum(Q[p,s,t-params.Rqh[p]]
                                                                                for s = model.segments)
                                            )
            else
                Qflow[pidx,t] = @constraint(model.internalmodel,
                                            Qf[p,t] == 0
                                            )
            end
            if t - params.Rsh[p] > 1
                Sflow[pidx,t] = @constraint(model.internalmodel,
                                            Sf[p,t] == (params.Rsm[p]/60)*S[p,t-(params.Rsh[p]+1)]
                                            + (1-params.Rsm[p]/60)*S[p,t-params.Rsh[p]]
                                            )
            elseif t - params.Rsh[p] > 0
                Sflow[pidx,t] = @constraint(model.internalmodel,
                                            Sf[p,t] == (1-params.Rsm[p]/60)*S[p,t-params.Rsh[p]]
                                            )
            else
                Sflow[pidx,t] = @constraint(model.internalmodel,
                                            Sf[p,t] == 0
                                            )
            end
        end
    end

    # Production
    @constraint(model.internalmodel,production[t = model.hours],
                H[t] == sum(params.μ[p,s]*Q[p,s,t]
                            for p = model.plants, s = model.segments)
                )
end
