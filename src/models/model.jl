abstract type AbstractHydroModel end

function show(io::IO, ::MIME"text/plain", hydromodel::AbstractHydroModel)
    show(io,hydromodel)
end

function modelname(hydromodel::M) where M <: AbstractHydroModel
    typename = string(M)
    chompname = match(r"(?:[^{]*\.)*([A-Za-z]+)(?:{.*})*",typename)
    modelname = split(chompname.captures[1],"Model")[1]
    return join(split(modelname,r"(?<!^)(?=[A-Z])")," ")
end

horizon(hydromodel::AbstractHydroModel) = hydromodel.horizon

function status(hydromodel::AbstractHydroModel)
    # Maybe internalModelLoaded here? check JuMP
    return hydromodel.status
end

function plan!(hydromodel::AbstractHydroModel; optimsolver = GLPKSolverLP())
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

    return HydroProductionPlan(hydromodel)
end

abstract type DeterministicHydroModel <: AbstractHydroModel end

function show(io::IO, hydromodel::DeterministicHydroModel)
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
    hydromodel.status = :Unplanned
    nothing
end

function reload!(hydromodel::DeterministicHydroModel, data::AbstractModelData, args...)
    hydromodel.data = data
    reinitialize!(hydromodel,args...)
    return hydromodel
end

function reinitialize!(hydromodel::DeterministicHydroModel, horizon::Horizon, args...)
    hydromodel.horizon = horizon
    hydromodel.indices = modelindices(hydromodel.data, horizon, args...)
    define_problem!(hydromodel)
    return hydromodel
end

abstract type StochasticHydroModel <: AbstractHydroModel end

function show(io::IO, hydromodel::StochasticHydroModel)
    if get(io, :multiline, false)
        print(io,string("Stochastic Hydro Power Model : ", modelname(hydromodel), ", including ", length(plants(hydromodel.indices)), " power stations, over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)), " featuring ", nscenarios(hydromodel.internalmodel), " scenarios")
    else
        println(io,string("Stochastic Hydro Power Model : ", modelname(hydromodel)))
        println(io,string("    including ", length(plants(hydromodel.indices)), " power stations"))
        println(io,string("    over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
        println(io,string("    featuring ", nscenarios(hydromodel.internalmodel), " scenarios"))
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

function reload!(hydromodel::StochasticHydroModel, horizon::Horizon, data::AbstractModelData, scenarios::Vector{<:AbstractScenario}, args...)
    StochasticPrograms.remove_subproblems!(hydromodel.internalmodel)
    add_scenarios!(hydromodel.internalmodel, scenarios)
    hydromodel.data = data
    reinitialize!(hydromodel, horizon, args...)
    return hydromodel
end

function reload!(hydromodel::StochasticHydroModel, horizon::Horizon, data::AbstractModelData, n::Integer, args...)
    StochasticPrograms.remove_subproblems!(hydromodel.internalmodel)
    sample!(hydromodel.internalmodel, n)
    hydromodel.data = data
    reinitialize!(hydromodel, horizon, args...)
    return hydromodel
end

function reinitialize!(hydromodel::StochasticHydroModel, horizon::Horizon, args...)
    hydromodel.horizon = horizon
    hydromodel.indices = modelindices(hydromodel.data, horizon, args...)
    stagedata = (hydromodel.horizon, hydromodel.indices, hydromodel.data)
    set_first_stage_data!(hydromodel.internalmodel, stagedata)
    set_second_stage_data!(hydromodel.internalmodel, stagedata)
    hydromodel.generator(hydromodel.internalmodel)
    hydromodel.status[:rp] = :Unplanned
    hydromodel.status[:evp] = :Unplanned
    return hydromodel
end

function plan!(hydromodel::StochasticHydroModel; variant = :rp, optimsolver = GLPKSolverLP())
    solvestatus = if variant == :rp
        solve(hydromodel.internalmodel, solver=optimsolver)
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
                    indices = modelindices(data,horizon,args...)
                    I = typeof(indices)
                    hydromodel = new{D,I}(horizon,data,indices,generator,:Unplanned)
                    define_problem!(hydromodel)
                    return hydromodel
                end
            end
        end
        code
    elseif variant == :Stochastic
        code = @q begin
            mutable struct $(esc(modelname)){$(esc(:D)) <: AbstractModelData, $(esc(:I)) <: AbstractModelIndices, $(esc(:SP)) <: StochasticProgram} <: StochasticHydroModel
                horizon::Horizon
                data::$(esc(:D))
                indices::$(esc(:I))
                generator::Function
                status::Dict{Symbol,Symbol}
                internalmodel::$(esc(:SP))

                function (::$(esc(:Type)){$(esc(modelname))})(horizon::Horizon,data::AbstractModelData,scenarios::Vector{<:AbstractScenario},args...)
                    D = typeof(data)
                    generator = ($(esc(:model))) -> begin
                        $(esc(modeldef))
                    end
                    indices = modelindices(data,horizon,args...)
                    I = typeof(indices)
                    stagedata = (horizon, indices, data)
                    stochasticprogram = StochasticProgram(stagedata, stagedata, scenarios)
                    generator(stochasticprogram)
                    SP = typeof(stochasticprogram)
                    hydromodel = new{D,I,SP}(horizon, data, indices, generator, Dict{Symbol,Symbol}(:rp=>:Unplanned,:evp=>:Unplanned), stochasticprogram)
                    return hydromodel
                end

                function (::$(esc(:Type)){$(esc(modelname))})(horizon::Horizon, data::AbstractModelData, sampler::AbstractSampler{S}, n::Integer, args...) where S <: AbstractScenario
                    D = typeof(data)
                    generator = ($(esc(:model))::StochasticProgram) -> begin
                        $(esc(modeldef))
                    end
                    indices = modelindices(data, horizon, args...)
                    I = typeof(indices)
                    stagedata = (horizon, indices, data)
                    stochasticprogram = StochasticProgram(stagedata, stagedata, S)
                    generator(stochasticprogram)
                    SP = typeof(stochasticprogram)
                    hydromodel = new{D,I,SP}(horizon, data, indices, generator, Dict{Symbol,Symbol}(:rp=>:Unplanned,:evp=>:Unplanned), SSA(stochasticprogram, sampler, n))
                    return hydromodel
                end
            end
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
