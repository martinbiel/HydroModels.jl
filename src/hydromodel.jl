using JuMP
using Clp

import Base.show

type HydroModelData
    # Plants
    # ========================================================
    plants       # All possible plant instances
    rivers       # Plants sorted according to river
    # Parameters
    # ========================================================
    M₀    # Initial reservoir contents
    M̅     # Maximum reservoir capacities
    H̅     # Maximal production
    Q̅     # Maximal discharge in each segment
    μ     # Marginal production equivalents in each segment
    S̱     # Minimum spillage for each plant
    Rqh   # Discharge flow time in whole hours
    Rqm   # Discharge flow time in remaining minutes
    Rsh   # Spillage flow time in whole hours
    Rsm   # Spillage flow time in remaining minutes
    Qd    # All discharge outlets located downstream (including itself)
    Qu    # Discharge outlet(s) located directly upstream
    Sd    # Spillage outlets located downstream (including itself)
    Su    # Spillage outlet(s) located directly upstream
    Qavg  # Yearly mean flow of each plant
    V     # Local inflow
    λ     # Expected price each hour
    λ_f   # Expected future price

    function HydroModelData()
        modeldata = new()
        return modeldata
    end
end

abstract HydroModel

type DeterministicHydroModel <: HydroModel
    # Parameters
    # ========================================================
    simtime::Int64           # Simulation time in hours
    nweeks::Int64            # Number of simulated weeks
    ndays::Int64             # Number of simulated days
    rivers::Vector{String}   # Rivers to include (can be all)


    # Model data
    # ========================================================
    modeldata::HydroModelData

    # Model indices
    # ========================================================
    plants
    segments
    hours

    # JuMP internals
    # ========================================================
    # Model variables
    Q            # Discharge for each plant/segment/hour
    S            # Spillage for each plant/hour
    M            # Reservoir content for each plant/hour
    H            # Production for each hour

    # Model and solver
    internalmodel
    optimsolver

    initialized::Bool  # Dirty flag for model data
    status::Symbol     # Planning status (:Unplanned,:Planned,:Failed)

    # Constructor
    # ========================================================
    function DeterministicHydroModel(simtime::Int64, rivers::Vector{String})
        model = new()
        model.simtime = simtime
        model.nweeks = div(simtime,168)
        model.ndays = div(mod(simtime,168),24)
        model.rivers = rivers
        model.modeldata = HydroModelData()
        model.initialized = false
        model.status = :Unplanned
        return model
    end

    function DeterministicHydroModel(nweeks::Int64, ndays::Int64, rivers::Vector{String})
        model = new()
        model.simtime = nweeks*168+ndays*24
        model.nweeks = nweeks
        model.ndays = ndays
        model.rivers = rivers
        model.modeldata = HydroModelData()
        model.initialized = false
        model.status = :Unplanned
        return model
    end
end

DeterministicHydroModel(simtime::Int64,river::String) = DeterministicHydroModel(simtime,[river])
DeterministicHydroModel(nweeks::Int64,ndays::Int64,river::String) = DeterministicHydroModel(nweeks,ndays,[river])
DeterministicHydroModel(simtime::Int64,rivers...) = DeterministicHydroModel(simtime,[rivers...])
DeterministicHydroModel(nweeks::Int64,ndays::Int64,rivers...) = DeterministicHydroModel(nweeks,ndays,[rivers...])

function horizonstring(model::HydroModel)
    horizonstr = ""
    if model.nweeks > 0
        horizonstr *= string("(",model.nweeks," week")
        if model.nweeks > 1
            horizonstr *= "s"
        end
    end
    if model.ndays > 0
        if model.nweeks > 0
            horizonstr *= string(", ",model.ndays," day")
        else
            horizonstr *= string("(",model.ndays," day")
        end
        if model.ndays > 1
            horizonstr *= "s)"
        else
            horizonstr *= ")"
        end
    else
        horizonstr *= ")"
    end
    return horizonstr
end

function show(io::IO, model::DeterministicHydroModel)
    if get(io, :multiline, false)
        if !model.initialized
            print(io,"Deterministic hydro power model. Not initialized.")
        else
            print(io,string("Deterministic hydro power model, including ",length(model.plants)," power stations, over a ",model.simtime," hour horizon ",horizonstring(model)))
        end
    else
        if !model.initialized
            println(io,"Deterministic hydro power model")
            print(io,"    Not initialized.")
        else
            println(io,"Deterministic hydro power model")
            println(io,string("    including ",length(model.plants)," power stations"))
            println(io,string("    over a ",model.simtime," hour horizon ",horizonstring(model)))
            println(io,"")
            if model.status == :NotPlanned
                print(io,"Not yet planned")
            elseif model.status == :Planned
                print(io,"Optimally planned")
            elseif model.status == :Failed
                print(io,"Could not be planned")
            else
                throw(ErrorException(string(model.status, " is not a valid model status")))
            end
        end
    end
end

function show(io::IO, ::MIME"text/plain", model::HydroModel)
    show(io,model)
end

type StochasticHydroModel <: HydroModel
    # Parameters
    # ========================================================
    rivers        # Rivers to include (can be all)
    simtime       # Simulation time in hours
    numscenarios  # Number of scenarios

    # Model data
    # ========================================================
    modeldata::HydroModelData

    # Model indices
    # ========================================================
    plants
    segments
    hours
    scenarios

    # Model variables
    # ========================================================

    # Constructor
    # ========================================================
    function StochasticHydroModel(rivers, simtime)
        model = new(rivers,simtime)
        model.modeldata = HydroModelData()
        return model
    end
end

function show(io::IO, model::StochasticHydroModel)
    if get(io, :multiline, false)
        if !model.initialized
            print(io,"Stochastic hydro power model. Not initialized.")
        else
            print(io,string("Stochastic hydro power model, including ",length(model.plants)," power stations, over a ",model.simtime," hour horizon ",horizonstring(model))," featuring ",model.numscenarios," scenarios")
        end
    else
        if !model.initialized
            println(io,"Stochastic hydro power model")
            print(io,"    Not initialized.")
        else
            println(io,"Stochastic hydro power model")
            println(io,string("    including ",length(model.plants)," power stations"))
            println(io,string("    over a ",model.simtime," hour horizon ",horizonstring(model)))
            println(io,string("    featuring ",model.numscenarios," scenarios"))
            println(io,"")
            if model.status == :Unplanned
                print(io,"Not yet planned")
            elseif model.status == :Optimal
                print(io,"Optimally planned")
            elseif model.status == :Failed
                print(io,"Could not be planned")
            else
                throw(ErrorException(string(model.status), " is not a valid model status"))
            end
        end
    end
end

function define_plants(plants)
    # if isdefined(HydroModels,:Plant) do not redefine plants
    def = parse("@enum Plant ")
    for (i,p) in enumerate(plants)
        push!(def.args,parse(string(p,"=",i)))
    end
    eval(def)
end

function define_rivers!(rivers,rivernames)
    for (p,rivername) in enumerate(rivernames)
        plant = Plant(p)
        if !haskey(rivers,rivername)
            rivers[rivername] = Plant[]
        end
        push!(rivers[rivername],plant)
    end
end

function define_plant_topology!(links, downstream_plants, upstream_plants)
    linker = (downstream_plants, current, links ) -> begin
        if current == 0
            return
        end
        push!(downstream_plants, Plant(current))
        linker(downstream_plants, links[current], links)
    end

    for (p,link) in enumerate(links)
        if link == 0
            continue
        end
        plant = Plant(p)
        d_plant = Plant(link)
        push!(downstream_plants[plant],plant)
        linker(downstream_plants[plant],link,links)
        push!(upstream_plants[d_plant],plant)
    end
end

function calculate_marginal_equivalents(Q̅,H̅)
    Q̅s = [0.75*Q̅ 0.25*Q̅]
    μs = zeros(2)
    for i = 1:length(Q̅s)
       μs[1] = H̅/(Q̅s[1] + 0.95*Q̅s[2])
       μs[2] = 0.95*μs[1]
    end
    return Q̅s,μs
end

function calculate_inflow(plant,w,upstream_plants)
    V = w[Int64(plant)]
    if !isempty(upstream_plants)
        V -= sum(w[Int64(p)] for p in upstream_plants)
    end
    return V
end

function define_plant_parameters(modeldata::HydroModelData,
                                 plantnames,
                                 dischargelinks,
                                 spillagelinks,
                                 productionmax,
                                 dischargemax,
                                 spillagemin,
                                 reservoircap,
                                 yearlymeanflows,
                                 dischargeflowtimes,
                                 spillageflowtimes,
                                 rivers)

    Vsf = 0.2278           # Scale factor for local inflow (0.2278)
    δ = 0.363              # Initial reservoir content factor (0.363)
    M_end = 0.89           # Target water level as factor of M_0 (0.89)

    # Define Plant enum
    define_plants(plantnames)

    modeldata.plants = instances(Plant)
    modeldata.rivers = Dict{String,Vector{Plant}}()
    define_rivers!(modeldata.rivers,rivers)

    # Initialize parameter dictionaries
    modeldata.M₀ = Dict{Plant,Float64}()
    modeldata.M̅ = Dict{Plant,Float64}()
    modeldata.H̅ = Dict{Plant,Float64}()
    modeldata.Q̅ = Dict{Tuple{Plant,Int64},Float64}()
    modeldata.μ = Dict{Tuple{Plant,Int64},Float64}()
    modeldata.S̱ = Dict{Plant,Float64}()
    modeldata.Rqh = Dict{Plant,Float64}()
    modeldata.Rqm = Dict{Plant,Float64}()
    modeldata.Rsh = Dict{Plant,Float64}()
    modeldata.Rsm = Dict{Plant,Float64}()
    modeldata.Qd = Dict{Plant,Vector{Plant}}()
    modeldata.Qu = Dict{Plant,Vector{Plant}}()
    modeldata.Sd = Dict{Plant,Vector{Plant}}()
    modeldata.Su = Dict{Plant,Vector{Plant}}()
    for p in instances(Plant)
        modeldata.Qd[p] = Plant[]
        modeldata.Qu[p] = Plant[]
        modeldata.Sd[p] = Plant[]
        modeldata.Su[p] = Plant[]
    end
    modeldata.Qavg = Dict{Plant,Float64}()
    modeldata.V = Dict{Plant,Float64}()

    w = Vsf*yearlymeanflows

    define_plant_topology!(dischargelinks, modeldata.Qd, modeldata.Qu)
    define_plant_topology!(spillagelinks, modeldata.Sd, modeldata.Su)

    nplants = length(plantnames)
    for i in 1:nplants
        p = Plant(i)
        modeldata.M₀[p] = δ*reservoircap[i]
        modeldata.M̅[p] = reservoircap[i]
        Q̅s,μs = calculate_marginal_equivalents(dischargemax[i],productionmax[i])
        modeldata.H̅[p] = productionmax[i]
        modeldata.Q̅[(p,1)] = Q̅s[1]
        modeldata.Q̅[(p,2)] = Q̅s[2]
        modeldata.μ[(p,1)] = μs[1]
        modeldata.μ[(p,2)] = μs[2]
        modeldata.S̱[p] = spillagemin[i]
        modeldata.Rqh[p] = floor(Int64,dischargeflowtimes[i]/60);
        modeldata.Rqm[p] = mod(dischargeflowtimes[i],60);
        modeldata.Rsh[p] = floor(Int64,spillageflowtimes[i]/60);
        modeldata.Rsm[p] = mod(spillageflowtimes[i],60);
        modeldata.Qavg[p] = w[i]
        modeldata.V[p] = calculate_inflow(p,w,modeldata.Qu[p])
    end
end

function define_price_parameters(model::HydroModel, pricedata::Matrix)
    @assert length(pricedata) >= model.simtime "Not enough price data for chosen horizon"
    @assert size(pricedata,1) == 24 || size(pricedata,1) == 168 "Prices should be defined daily or weekly"
    model.modeldata.λ = pricedata
    model.modeldata.λ_f = mean(pricedata)
end

function define_model_parameters(model::HydroModel, plantdata::Matrix, pricedata::Matrix)
    @assert size(plantdata,2) == 12 "Invalid plant data format"

    define_plant_parameters(model.modeldata,
                            plantdata[:,1],
                            plantdata[:,2],
                            plantdata[:,3],
                            plantdata[:,4],
                            plantdata[:,5],
                            plantdata[:,6],
                            plantdata[:,7],
                            plantdata[:,8],
                            plantdata[:,9],
                            plantdata[:,10],
                            plantdata[:,11])
    define_price_parameters(model, pricedata)
end

function define_model_parameters(model::HydroModel, plantfilename::String, pricefilename::String)
    plantdata = readcsv(plantfilename)
    pricedata = readcsv(pricefilename)
    define_model_parameters(model,plantdata[2:end,:],pricedata[2:end,:])
end

function define_model_indices(model::DeterministicHydroModel)
    # Model indices
    if model.rivers[1] == "All"
        model.plants = [instances(Plant)...]
    else
        model.plants = Plant[]
        for river in model.rivers
            if !haskey(model.modeldata.rivers,river)
                throw(ArgumentError(string("Invalid river name: ",river)))
            end
            append!(model.plants,model.modeldata.rivers[river])
        end
    end
    model.segments = collect(1:2)
    model.hours = collect(1:model.simtime)
end

function define_planning_problem(model::HydroModel)
    model.internalmodel = Model(solver = model.optimsolver)
    params = model.modeldata

    # Define JuMP model
    # ========================================================
    # Variables
    # ========================================================
    model.Q = @variable(model.internalmodel,Q[p = model.plants, s = model.segments, t = model.hours],lowerbound = 0, upperbound = params.Q̅[(p,s)])
    model.S = @variable(model.internalmodel,S[p = model.plants, t = model.hours] >= 0)
    model.M = @variable(model.internalmodel,M[p = model.plants, t = model.hours],lowerbound = 0,upperbound = params.M̅[p])
    model.H = @variable(model.internalmodel,H[t = model.hours] >= 0)
    @variable(model.internalmodel, Qf[p = model.plants, t = model.hours] >= 0)
    @variable(model.internalmodel, Sf[p = model.plants, t = model.hours] >= 0)

    # Objectives
    # ========================================================
    # Net profit
    @expression(model.internalmodel, net_profit, sum(params.λ[t]*H[t] for t = model.hours))
    # Value of stored water
    @expression(model.internalmodel,value_of_stored_water,
                params.λ_f*sum(M[p,model.simtime]*sum(params.μ[i,1]
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
    @constraintref Qflow[1:length(model.plants),1:model.simtime]
    @constraintref Sflow[1:length(model.plants),1:model.simtime]
    for p = model.plants
        pidx = model.rivers[1] == "All" ? Int64(p) : findfirst(model.plants,p)
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
    @constraint(model.internalmodel,production[t = 1:model.simtime],
                H[t] == sum(params.μ[p,s]*Q[p,s,t]
                            for p = model.plants, s = model.segments)
                )

    model.status = :NotPlanned
end

function changehorizon!(model::HydroModel,newhorizon::Int64)
    model.simtime = newhorizon
    model.nweeks = div(newhorizon,168)
    model.ndays = div(newhorizon,24)
    model.hours = collect(1:model.simtime)
    define_planning_problem(model)
    return model
end

function changehorizon!(model::HydroModel,newweeks::Int64,newdays::Int64)
    model.simtime = 168*newweeks+24*newdays
    model.nweeks = newweeks
    model.ndays = newdays
    model.hours = collect(1:model.simtime)
    define_planning_problem(model)
    return model
end

function initialize!(model::HydroModel,modeldata::HydroModelData,optimsolver = ClpSolver())
    model.optimsolver = optimsolver
    model.modeldata = modeldata
    define_model_indices(model)
    define_planning_problem(model)
    model.initialized = true
    return model
end

function initialize!(model::HydroModel,plantfilename::String,pricefilename::String,optimsolver = ClpSolver())
    model.optimsolver = optimsolver
    define_model_parameters(model,plantfilename,pricefilename)
    define_model_indices(model)
    define_planning_problem(model)
    model.initialized = true
    return model
end

function plan!(model::HydroModel)
    @assert model.initialized "Hydro model has not been initialized."
    status = solve(model.internalmodel)
    if status == :Optimal
        model.status = :Planned
    else
        model.status = :Failed
    end
    return model
end

# Macros
# macro deterministic(definitionexpr::Expr)
#     dump(definitionexpr)
#     rivers = Vector{String}()
#     nweeks = 0
#     ndays = 0
#     plantdata = ""
#     pricedata = ""
#     for arg in definitionexpr.args
#         if arg.head != :(=)
#             error("Invalid argument syntax")
#         end
#         if arg.args[1] == :rivers
#             rivers = arg.args[2].args
#         elseif arg.args[1] == :horizon
#             nweeks = arg.args[2].args[1]
#             ndays = arg.args[2].args[3]
#         elseif arg.args[1] == :data
#             plantdata = arg.args[2]
#         elseif arg.args[1] == :prices
#             pricedata = arg.args[2]
#         end
#     end
#     modeldef = quote
#         model = DeterministicHydroModel(nweeks,ndays,rivers)
#         initialize!(model,plantdata,pricedata)
#         model
#     end
#     return modeldef
# end
