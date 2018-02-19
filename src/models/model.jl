abstract type AbstractHydroModel end

function Base.show(io::IO, ::MIME"text/plain", model::AbstractHydroModel)
    show(io,model)
end

abstract type DeterministicHydroModel <: AbstractHydroModel end
function Base.show(io::IO, model::DeterministicHydroModel)
    if get(io, :multiline, false)
        print(io,string("Deterministic Hydro Power Model : ",modelname(model),", including ", length(plants(model.indices))," power stations, over a ", nhours(model.horizon)," hour horizon ",horizonstring(model.horizon)))
    else
        println(io,string("Deterministic Hydro Power Model : ",modelname(model)))
        println(io,string("    including ",length(plants(model.indices))," power stations"))
        println(io,string("    over a ",nhours(model.horizon)," hour horizon ",horizonstring(model.horizon)))
        println(io,"")
        if status(model) == :Unplanned
            print(io,"Not yet planned")
        elseif status(model) == :Planned
            print(io,"Optimally planned")
        elseif status(model) == :Failed
            print(io,"Could not be planned")
        else
            error(string(model.status, " is not a valid model status"))
        end
    end
end

horizon(model::AbstractHydroModel) = model.horizon

function define_problem!(hydromodel::AbstractHydroModel)
    model = Model()
    hydromodel.generator(model,hydromodel.data,hydromodel.indices,hydromodel.horizon)
    hydromodel.internalmodel = model
    nothing
end

function reinitialize!(model::AbstractHydroModel, args...)
    model.indices = indices(model.data, horizon(model), args...)

    define_problem!(model)
    return model
end

function reinitialize!(model::AbstractHydroModel, newhorizon::Horizon, args...)
    model.horizon = newhorizon
    model.indices = indices(model.data, newhorizon, args...)

    define_problem!(model)
    return model
end

function changehorizon!(model::AbstractHydroModel, newhorizon::Horizon)
    model.horizon = newhorizon
    define_problem!(model)
    return model
end

function status(model::AbstractHydroModel)
    # Maybe internalModelLoaded here? check JuMP
    return model.status
end

function plan!(model::AbstractHydroModel; optimsolver = ClpSolver())
    setsolver(model.internalmodel,optimsolver)
    solvestatus = solve(model.internalmodel)
    if solvestatus == :Optimal
        model.status = :Planned
    else
        model.status = :Failed
    end
    return model
end

function production(model::AbstractHydroModel)
    @assert status(model) == :Planned "Hydro model has not been planned yet"

    return ProductionPlan(model.horizon,model.modeldata,model.plants,model.internalmodel)
end

macro hydromodel(args)
    @capture(args,name_Symbol = modeldef_) || error("Invalid syntax. Expected modelname = begin JuMPdef end")

    modelname = Symbol(name,:Model)

    code = @q begin
        mutable struct $(esc(modelname)){$(esc(:I)) <: AbstractModelIndices, $(esc(:D)) <: AbstractModelData} <: DeterministicHydroModel
            data::$(esc(:D))
            horizon::Horizon
            indices::$(esc(:I))
            generator::Function
            status::Symbol
            internalmodel::JuMP.Model

            function (::$(esc(:Type)){$(esc(modelname))})(data::AbstractModelData,horizon::Horizon,args...)
                D = typeof(data)
                generator = ($(esc(:model)),$(esc(:data)),$(esc(:indices)),$(esc(:horizon))) -> begin
                    $(esc(modeldef))
                end
                indices = modelindices(data,horizon,args...)
                I = typeof(indices)
                hydromodel = new{I,D}(data,horizon,indices,generator,:Unplanned)
                define_problem!(hydromodel)
                return hydromodel
            end
        end

        $(esc(:modelname))(::$(esc(modelname))) = join(split($(esc(string(name))),r"(?<!^)(?=[A-Z])")," ")
    end

    return prettify(code)
end
