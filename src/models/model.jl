abstract type AbstractHydroModel end

function Base.show(io::IO, ::MIME"text/plain", hydromodel::AbstractHydroModel)
    show(io,hydromodel)
end

horizon(hydromodel::AbstractHydroModel) = hydromodel.horizon

function changehorizon!(hydromodel::AbstractHydroModel, newhorizon::Horizon)
    hydromodel.horizon = newhorizon
    define_problem!(hydromodel)
    return hydromodel
end

function status(hydromodel::AbstractHydroModel)
    # Maybe internalModelLoaded here? check JuMP
    return hydromodel.status
end

function plan!(hydromodel::AbstractHydroModel; optimsolver = ClpSolver())
    setsolver(hydromodel.internalmodel,optimsolver)
    solvestatus = solve(hydromodel.internalmodel)
    if solvestatus == :Optimal
        hydromodel.status = :Planned
    else
        hydromodel.status = :Failed
    end
    return hydromodel
end

function production(hydromodel::AbstractHydroModel)
    status(hydromodel) == :Planned || error("Hydro model has not been planned yet")

    return ProductionPlan(hydromodel.horizon,hydromodel.modeldata,hydromodel.plants,hydromodel.internalmodel)
end

abstract type DeterministicHydroModel <: AbstractHydroModel end

function Base.show(io::IO, hydromodel::DeterministicHydroModel)
    if get(io, :multiline, false)
        print(io,string("Deterministic Hydro Power Model : ", modelname(hydromodel), ", including ", length(plants(hydromodel.indices)), " power stations, over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
    else
        println(io,string("Deterministic Hydro Power Model : ", modelname(hydromodel)))
        println(io,string("    including ", length(plants(hydromodel.indices)), " power stations"))
        println(io,string("    over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
        println(io,"")
        if status(hydromodel) == :Unplanned
            print(io,"Not yet planned")
        elseif status(hydromodel) == :Planned
            print(io,"Optimally planned")
        elseif status(hydromodel) == :Failed
            print(io,"Could not be planned")
        else
            error(string(hydromodel.status, " is not a valid model status"))
        end
    end
end

function define_problem!(hydromodel::DeterministicHydroModel)
    model = Model()
    hydromodel.generator(model,hydromodel.horizon,hydromodel.data,hydromodel.indices)
    hydromodel.internalmodel = model
    nothing
end

function reinitialize!(hydromodel::DeterministicHydroModel, args...)
    hydromodel.indices = modelindices(horizon(hydromodel),hydromodel.data,args...)
    define_problem!(hydromodel)
    return hydromodel
end

function reinitialize!(hydromodel::DeterministicHydroModel, newhorizon::Horizon, args...)
    hydromodel.horizon = newhorizon
    hydromodel.indices = indices(newhorizon,hydromodel.data,args...)
    define_problem!(hydromodel)
    return hydromodel
end

abstract type StochasticHydroModel <: AbstractHydroModel end

function Base.show(io::IO, hydromodel::StochasticHydroModel)
    if get(io, :multiline, false)
        print(io,string("Stochastic Hydro Power Model : ", modelname(hydromodel), ", including ", length(plants(hydromodel.indices)), " power stations, over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)), " featuring ", nscenarios(hydromodel), " scenarios")
    else
        println(io,string("Stochastic Hydro Power Model : ", modelname(hydromodel)))
        println(io,string("    including ", length(plants(hydromodel.indices)), " power stations"))
        println(io,string("    over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
        println(io,string("    featuring ", nscenarios(hydromodel), " scenarios"))
        println(io,"")
        showstatus(io,hydromodel)
    end
end

showstatus(hydromodel::StochasticHydroModel) = showstatus(Base.STDOUT,hydromodel)
function showstatus(io::IO,hydromodel::StochasticHydroModel)
    statstrs = Dict(:Unplanned=>"Not yet planned",:Planned=>"Optimally planned",:Failed=>"Could not be planned")
    println(io,string("Recourse Problem: ", statstrs[status(hydromodel;variant=:rp)]))
    print(io,string("Expected Value Problem: ", statstrs[status(hydromodel;variant=:evp)]))
end

function status(hydromodel::StochasticHydroModel; variant = :rp)
    return hydromodel.status[variant]
end

nscenarios(hydromodel::StochasticHydroModel) = length(hydromodel.scenarios)

function define_problem!(hydromodel::StochasticHydroModel)
    model = StochasticProgram(hydromodel.scenarios)
    hydromodel.generator(model,hydromodel.horizon,hydromodel.data,hydromodel.indices)
    hydromodel.internalmodel = model
    nothing
end

function reinitialize!(hydromodel::StochasticHydroModel, args...)
    hydromodel.indices = modelindices(horizon(hydromodel),hydromodel.data,hydromodel.scenarios,args...)
    define_problem!(hydromodel)
    return hydromodel
end

function reinitialize!(hydromodel::StochasticHydroModel, newhorizon::Horizon, args...)
    hydromodel.horizon = newhorizon
    hydromodel.indices = indices(newhorizon,hydromodel.data,hydromodel.scenarios,args...)
    define_problem!(hydromodel)
    return hydromodel
end

function plan!(hydromodel::StochasticHydroModel; variant = :rp, optimsolver = ClpSolver())
    setsolver(hydromodel.internalmodel,optimsolver)
    solvestatus = if variant == :rp
        solve(hydromodel.internalmodel)
    elseif variant == :evp
        evp = EVP(hydromodel.internalmodel,optimsolver)
        solve(evp)
    else
        error("Unknown variant: ",variant)
    end

    if solvestatus == :Optimal
        hydromodel.status[variant] = :Planned
    else
        hydromodel.status[variant] = :Failed
    end
    return hydromodel
end
plan_rp!(hydromodel::StochasticHydroModel) = plan!(hydromodel,:rp)
plan_evp!(hydromodel::StochasticHydroModel) = plan!(hydromodel,:evp)

macro hydromodel(variant,def)
    @capture(def,name_Symbol = modeldef_) || error("Invalid syntax. Expected modelname = begin JuMPdef end")
    modelname = Symbol(name,:Model)

    code = if variant == :Deterministic
        code = @q begin
            mutable struct $(esc(modelname)){$(esc(:D)) <: AbstractModelData, $(esc(:I)) <: AbstractModelIndices} <: DeterministicHydroModel
                horizon::Horizon
                data::$(esc(:D))
                indices::$(esc(:I))
                generator::Function
                status::Symbol
                internalmodel::JuMP.Model

                function (::$(esc(:Type)){$(esc(modelname))})(horizon::Horizon,data::AbstractModelData,args...)
                    D = typeof(data)
                    generator = ($(esc(:model)),$(esc(:horizon)),$(esc(:data)),$(esc(:indices))) -> begin
                        $(esc(modeldef))
                    end
                    indices = modelindices(horizon,data,args...)
                    I = typeof(indices)
                    hydromodel = new{I,D}(horizon,data,indices,generator,:Unplanned)
                    define_problem!(hydromodel)
                    return hydromodel
                end
            end

            $(esc(:modelname))(::$(esc(modelname))) = join(split($(esc(string(name))),r"(?<!^)(?=[A-Z])")," ")
        end
        code
    elseif variant == :Stochastic
        code = @q begin
            mutable struct $(esc(modelname)){$(esc(:D)) <: AbstractModelData, $(esc(:I)) <: AbstractModelIndices, $(esc(:S)) <: AbstractScenarioData} <: StochasticHydroModel
                horizon::Horizon
                data::$(esc(:D))
                indices::$(esc(:I))
                scenarios::Vector{$(esc(:S))}
                generator::Function
                status::Dict{Symbol,Symbol}
                internalmodel::JuMP.Model

                function (::$(esc(:Type)){$(esc(modelname))})(horizon::Horizon,data::AbstractModelData,scenarios::Vector{<:AbstractScenarioData},args...)
                    D = typeof(data)
                    generator = ($(esc(:model)),$(esc(:horizon)),$(esc(:data)),$(esc(:indices))) -> begin
                        $(esc(modeldef))
                    end
                    indices = modelindices(horizon,data,scenarios,args...)
                    I = typeof(indices)
                    S = eltype(scenarios)
                    hydromodel = new{D,I,S}(horizon,data,indices,scenarios,generator,Dict{Symbol,Symbol}(:rp=>:Unplanned,:evp=>:Unplanned))
                    define_problem!(hydromodel)
                    return hydromodel
                end
            end

            $(esc(:modelname))(::$(esc(modelname))) = join(split($(esc(string(name))),r"(?<!^)(?=[A-Z])")," ")
        end
        code
    else
        error("Invalid model variant. Specify Deterministic for deterministic models and Stochastic for stochastic models.")
    end

    return prettify(code)
end
macro deterministic(def)
    return :(@hydromodel Deterministic $def)
end
macro stochastic(def)
    return :(@hydromodel Stochastic $def)
end
