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
    setsolver(hydromodel.internalmodel, optimsolver)
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

# struct DeterministicHydroModel <: AbstractHydroModel

# end

# function show(io::IO, hydromodel::DeterministicHydroModel)
#     if get(io, :multiline, false)
#         print(io,string("Deterministic Hydro Power Model : ", modelname(hydromodel), ", including ", length(plants(hydromodel.indices)), " power stations, over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
#     else
#         println(io,string("Deterministic Hydro Power Model : ", modelname(hydromodel)))
#         println(io,string("    including ", length(plants(hydromodel.indices)), " power stations"))
#         println(io,string("    over a ", nhours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
#         println(io,"")
#         if status(hydromodel) == :Unplanned
#             print(io,"Not yet planned")
#         elseif status(hydromodel) == :Planned
#             print(io,"Optimally planned")
#         elseif status(hydromodel) == :Failed
#             print(io,"Could not be planned")
#         else
#             error(string(hydromodel.status, " is not a valid model status"))
#         end
#     end
# end

# function define_problem!(hydromodel::DeterministicHydroModel)
#     model = Model()
#     hydromodel.generator(model,hydromodel.horizon,hydromodel.data,hydromodel.indices)
#     hydromodel.internalmodel = model
#     hydromodel.status = :Unplanned
#     nothing
# end

# function reload!(hydromodel::DeterministicHydroModel, data::AbstractModelData, args...)
#     hydromodel.data = data
#     reinitialize!(hydromodel,args...)
#     return hydromodel
# end

# function reinitialize!(hydromodel::DeterministicHydroModel, horizon::Horizon, args...)
#     hydromodel.horizon = horizon
#     hydromodel.indices = modelindices(hydromodel.data, horizon, args...)
#     define_problem!(hydromodel)
#     return hydromodel
# end

mutable struct StochasticHydroModel{D <: AbstractModelData,
                                    I <: AbstractModelIndices,
                                    SM <: StochasticModel,
                                    SP <: StochasticProgram} <: AbstractHydroModel
    name::String
    horizon::Horizon
    data::D
    indices::I
    stochasticmodel::SM
    internalmodel::SP
    status::Dict{Symbol,Symbol}

    function StochasticHydroModel(name::String,
                                  horizon::Horizon,
                                  data::AbstractModelData,
                                  modelgenerator::Function,
                                  scenarios::Vector{<:AbstractScenario}; kw...)
        D = typeof(data)
        indices = modelindices(data, horizon; kw...)
        I = typeof(indices)
        stochasticmodel = modelgenerator(horizon, data, indices)
        SM = typeof(stochasticmodel)
        sp = instantiate(stochasticmodel, scenarios; horizon = horizon, indices = indices, data = data)
        SP = typeof(sp)
        hydromodel = new{D,I,SM,SP}(name, horizon, data, indices, stochasticmodel, sp, Dict(:rp=>:Unplanned,:evp=>:Unplanned))
        return hydromodel
    end

    function StochasticHydroModel(name::String,
                                  horizon::Horizon,
                                  data::AbstractModelData,
                                  modelgenerator::Function,
                                  sampler::AbstractSampler{S},
                                  n::Integer; kw...) where S <: AbstractScenario
        D = typeof(data)
        indices = modelindices(data, horizon; kw...)
        I = typeof(indices)
        stochasticmodel = modelgenerator(horizon, data, indices)
        SM = typeof(stochasticmodel)
        sp = instantiate(stochasticmodel, sampler, n)
        SP = typeof(sp)
        hydromodel = new{D,I,SM,SP}(name, horizon, data, indices, stochasticmodel, sp, Dict(:rp=>:Unplanned,:evp=>:Unplanned))
        return hydromodel
    end
end

function show(io::IO, hydromodel::StochasticHydroModel)
    if get(io, :multiline, false)
        print(io,string("Stochastic Hydro Power Model : ", modelname(hydromodel), ", including ", length(plants(hydromodel.indices)), " power stations, over a ", num_hours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)), " featuring ", num_scenarios(hydromodel.internalmodel), " scenarios")
    else
        println(io,string("Stochastic Hydro Power Model : ", modelname(hydromodel)))
        println(io,string("    including ", length(plants(hydromodel.indices)), " power stations"))
        println(io,string("    over a ", num_hours(hydromodel.horizon), " hour horizon ", horizonstring(hydromodel.horizon)))
        println(io,string("    featuring ", num_scenarios(hydromodel.internalmodel), " scenarios"))
        println(io,"")
        showstatus(io,hydromodel)
    end
end

function modelname(hydromodel::StochasticHydroModel)
    return hydromodel.name
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

function reload!(hydromodel::StochasticHydroModel, horizon::Horizon, data::AbstractModelData, sampler::AbstractSampler, n::Integer; kw...)
    hydromodel.data = data
    reinitialize!(hydromodel, horizon, sampler, n; kw...)
    return hydromodel
end

function reinitialize!(hydromodel::StochasticHydroModel, horizon::Horizon; kw...)
    hydromodel.horizon = horizon
    hydromodel.indices = modelindices(hydromodel.data, horizon; kw...)
    scenariodata = scenarios(hydromodel.internalmodel)
    hydromodel.internalmodel = instantiate(hydromodel.stochasticmodel,
                                           scenariodata;
                                           horizon = hydromodel.horizon,
                                           indices = hydromodel.indices,
                                           data = hydromodel.data)
    hydromodel.status[:rp] = :Unplanned
    hydromodel.status[:evp] = :Unplanned
    return hydromodel
end

function reinitialize!(hydromodel::StochasticHydroModel, horizon::Horizon, sampler::AbstractSampler, n::Integer; kw...)
    hydromodel.horizon = horizon
    hydromodel.indices = modelindices(hydromodel.data, horizon; kw...)
    hydromodel.internalmodel = instantiate(hydromodel.stochasticmodel,
                                           sampler,
                                           n;
                                           horizon = hydromodel.horizon,
                                           indices = hydromodel.indices,
                                           data = hydromodel.data)
    hydromodel.status[:rp] = :Unplanned
    hydromodel.status[:evp] = :Unplanned
    return hydromodel
end

function plan!(hydromodel::StochasticHydroModel; variant = :rp, optimsolver = GLPKSolverLP())
    if variant == :rp
        StochasticPrograms.optimize!(hydromodel.internalmodel)
    elseif variant == :evp
        evp = EVP(hydromodel.internalmodel, solver = optimsolver)
        solve(evp)
    else
        error("Unknown variant: ",variant)
    end

    if termination_status(hydromodel.internalmodel) == MOI.OPTIMAL
        hydromodel.status[variant] = :Planned
    else
        hydromodel.status[variant] = :Failed
    end
    return hydromodel
end
plan_rp!(hydromodel::StochasticHydroModel) = plan!(hydromodel,:rp)
plan_evp!(hydromodel::StochasticHydroModel) = plan!(hydromodel,:evp)

# macro hydromodel(variant,def)
#     @capture(def,name_Symbol = modeldef_) || error("Invalid syntax. Expected modelname = begin JuMPdef end")
#     modelname = Symbol(name,:Model)
#     # Fix horizon if applicable
#     fixhorizondef = Expr(:block)
#     modeldef = postwalk(modeldef) do x
#         @capture(x, @fixhorizon horizon_) || return x
#         fixhorizondef = @q begin
#             function $(esc(modelname))(data::AbstractModelData, args...; kw...)
#                 return $(esc(modelname))($horizon, data, args...; kw...)
#             end
#             function reload!(hydromodel::$(esc(modelname)), args...; kw...)
#                 reload!(hydromodel, $horizon, args...; kw...)
#                 return hydromodel
#             end
#             function reinitialize!(hydromodel::$(esc(modelname)), args...; kw...)
#                 reinitialize!(hydromodel, $horizon, args...; kw...)
#                 return hydromodel
#             end
#         end
#         return :()
#     end
#     # Define new deterministic/stochastic model type
#     code = if variant == :Deterministic
#         code = @q begin
#             mutable struct $(esc(modelname)){$(esc(:D)) <: AbstractModelData,
#                                              $(esc(:I)) <: AbstractModelIndices} <: DeterministicHydroModel
#                 horizon::Horizon
#                 data::$(esc(:D))
#                 indices::$(esc(:I))
#                 generator::Function
#                 status::Symbol
#                 internalmodel::JuMP.Model

#                 function $(esc(modelname))(horizon::Horizon, data::AbstractModelData; args...)
#                     D = typeof(data)
#                     generator = ($(esc(:model)), $(esc(:horizon)), $(esc(:data)), $(esc(:indices))) -> begin
#                         $(esc(modeldef))
#                     end
#                     indices = modelindices(data, horizon; kw...)
#                     I = typeof(indices)
#                     hydromodel = new{D,I}(horizon, data, indices, generator, :Unplanned)
#                     define_problem!(hydromodel)
#                     return hydromodel
#                 end
#             end
#             $fixhorizondef
#         end
#         code
#     elseif variant == :Stochastic
#         modeldef = @q begin
#             @stochastic_model begin
#                 $modeldef
#             end
#         end
#         code = @q begin
#             mutable struct $(esc(modelname)){$(esc(:D)) <: AbstractModelData,
#                                              $(esc(:I)) <: AbstractModelIndices,
#                                              $(esc(:SM)) <: StochasticModel,
#                                              $(esc(:SP)) <: StochasticProgram} <: StochasticHydroModel
#                 horizon::Horizon
#                 data::$(esc(:D))
#                 indices::$(esc(:I))
#                 stochasticmodel::$(esc(:SM))
#                 internalmodel::$(esc(:SP))
#                 status::Dict{Symbol,Symbol}

#                 function $(esc(modelname))(horizon::Horizon,
#                                            data::AbstractModelData,
#                                            scenarios::Vector{<:AbstractScenario}; kw...)
#                     D = typeof(data)
#                     indices = modelindices(data, horizon; kw...)
#                     I = typeof(indices)
#                     stochasticmodel = $(esc(modeldef))
#                     SM = typeof(stochasticmodel)
#                     sp = instantiate(stochasticmodel, scenarios; horizon = horizon, indices = indices, data = data)
#                     SP = typeof(sp)
#                     hydromodel = new{D,I,SM,SP}(horizon, data, indices, stochasticmodel, sp, Dict(:rp=>:Unplanned,:evp=>:Unplanned))
#                     return hydromodel
#                 end

#                 function $(esc(modelname))(horizon::Horizon,
#                                            data::AbstractModelData,
#                                            sampler::AbstractSampler{S},
#                                            n::Integer; kw...) where S <: AbstractScenario
#                     D = typeof(data)
#                     indices = modelindices(data, horizon; kw...)
#                     I = typeof(indices)
#                     stochasticmodel = $(esc(modeldef))
#                     SM = typeof(stochasticmodel)
#                     sp = instantiate(stochasticmodel, sampler, n; horizon = horizon, indices = indices, data = data)
#                     SP = typeof(sp)
#                     hydromodel = new{D,I,SM,SP}(horizon, data, indices, stochasticmodel, sp, Dict(:rp=>:Unplanned,:evp=>:Unplanned))
#                     return hydromodel
#                 end
#             end
#             $fixhorizondef
#         end
#         code
#     else
#         error("Invalid model variant. Specify Deterministic for deterministic models and Stochastic for stochastic models.")
#     end

#     return prettify(code)
# end
# macro deterministic(def)
#     return :(@hydromodel Deterministic $def)
# end
# macro stochastic(def)
#     return :(@hydromodel Stochastic $def)
# end
