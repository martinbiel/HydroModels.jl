abstract type HydroModel end

function show(io::IO, ::MIME"text/plain", model::HydroModel)
    show(io,model)
end

function initialize!(model::HydroModel, areas::Vector{Area}, rivers::Vector{River}; kwargs...)
    model.hours = collect(1:hours(model.horizon))
    model.plants = plants_in_areas_and_rivers(model.modeldata,areas,rivers)
    if isempty(model.plants)
        error("No plants in given set of price areas and rivers")
    end
    model.segments = collect(1:2)

    define_specific_model(model)
    define_planning_problem(model; kwargs...)
    return model
end

define_specific_model(model::HydroModel) = nothing

function changehorizon!(model::HydroModel,newhorizon::Horizon)
    model.horizon = newhorizon
    define_specific_model(model)
    define_planning_problem(model)
    return model
end

function status(model::HydroModel)
    # Maybe internalModelLoaded here? check JuMP
    return model.status
end

function plan!(model::HydroModel; optimsolver = ClpSolver())
    model.optimsolver = optimsolver
    setsolver(model.internalmodel,optimsolver)
    solvestatus = solve(model.internalmodel)
    if solvestatus == :Optimal
        model.status = :Planned
    else
        model.status = :Failed
    end
    return model
end

function production(model::HydroModel)
    @assert status(model) == :Planned "Hydro model has not been planned yet"

    return ProductionPlan(model.horizon,model.modeldata,model.plants,model.internalmodel)
end
