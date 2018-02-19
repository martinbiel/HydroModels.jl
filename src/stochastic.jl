Scenario = Int

abstract type StochasticHydroModel <: AbstractHydroModel end

function Base.show(io::IO, model::StochasticHydroModel)
    if get(io, :multiline, false)
        print(io,string("Stochastic Hydro Power Model : ",modelname(model),", including ",length(model.plants)," power stations, over a ",hours(model.horizon)," hour horizon ",horizonstring(model.horizon))," featuring ",numscenarios(model)," scenarios")
    else
        println(io,string("Stochastic Hydro Power Model : ",modelname(model)))
        println(io,string("    including ",length(model.plants)," power stations"))
        println(io,string("    over a ",hours(model.horizon)," hour horizon ",horizonstring(model.horizon)))
        println(io,string("    featuring ",numscenarios(model)," scenarios"))
        println(io,"")
        showstatus(io,model)
    end
end

function showstatus(io::IO,model::StochasticHydroModel)
    statstrs = Dict(:Unplanned=>"Not yet planned",:Planned=>"Optimally planned",:Failed=>"Could not be planned")
    println(io,string("Deterministic Equivalent Problem: ", statstrs[status(model;variant=:dep)]))
    println(io,string("Deterministic Equivalent Problem (StructJuMP): ", statstrs[status(model;variant=:struct)]))
    print(io,string("Expected Value Problem: ", statstrs[status(model;variant=:evp)]))
end
showstatus(model::StochasticHydroModel) = showstatus(Base.STDOUT,model)

function status(model::StochasticHydroModel; variant = :dep)
    return model.status[variant]
end

numscenarios(model::StochasticHydroModel) = length(model.scenariodata)

function define_specific_model(model::StochasticHydroModel)
    # Model indices
    model.scenarios = collect(1:numscenarios(model))
end

function define_planning_problem(model::StochasticHydroModel)
    define_dep_problem(model)
    define_dep_structjump_problem(model)
    define_evp_problem(model)
end

function plan!(model::StochasticHydroModel; variant = :dep, optimsolver = ClpSolver())
    @assert haskey(model.internalmodels,variant) string("Hydro model variant ",variant," has not been initialized.")
    model.optimsolver = optimsolver
    setsolver(model.internalmodels[variant],optimsolver)
    solvestatus = solve(model.internalmodels[variant])
    if solvestatus == :Optimal
        model.status[variant] = :Planned
    else
        model.status[variant] = :Failed
    end
    return model
end

plan_dep!(model::StochasticHydroModel) = plan!(model,:dep)
plan_struct_dep!(model::StochasticHydroModel) = plan!(model,:struct)
plan_evp!(model::StochasticHydroModel) = plan!(model,:evp)
