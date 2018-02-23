struct HydroPlan{T <: AbstractFloat}
    Q::Vector{T} # Discharge each hour
    S::Vector{T} # Spillage each hour
    M::Vector{T} # Reservoir content each hour
    H::Vector{T} # Resulting electricity production each hour

    function (::Type{HydroPlan})(Q::AbstractVector,S::AbstractVector,M::AbstractVector,H::AbstractVector)
        T = promote_type(eltype(Q),eltype(S),eltype(M),eltype(H),Float32)
        return new{T}(convert(Vector{T},Q),convert(Vector{T},S),convert(Vector{T},M),convert(Vector{T},H))
    end
end

struct HydroProductionPlan{T <: AbstractFloat}
    horizon::Horizon                        # Planning horizon
    modeldata::HydroPlantCollection{T,2}

    total_plan::HydroPlan{T}                     # Accumulation of individual plans
    individual_plans::Dict{Plant,HydroPlan{T}}   # Plans for each hydro power plant

    function (::Type{HydroProductionPlan})(horizon::Horizon,data::HydroPlantCollection{T,2},plan::HydroPlan{T},plans::Dict{Plant,HydroPlan{T}}) where T <: AbstractFloat
        return new{T}(horizon,data,plan,plans)
    end
end
Base.eltype(::HydroProductionPlan{T}) where T <: AbstractFloat = T

function HydroProductionPlan(model::AbstractHydroModel)
    optmodel = model.internalmodel
    horizon = HydroModels.horizon(model)
    data = hydrodata(model.data)
    plants = HydroModels.plants(model.indices)

    (haskey(optmodel.objDict,:Q) && haskey(optmodel.objDict,:S) && haskey(optmodel.objDict,:M) && haskey(optmodel.objDict,:H)) || error("Given model does not model hydro power production")

    Q = getvalue(optmodel.objDict[:Q])
    S = getvalue(optmodel.objDict[:S])
    M = getvalue(optmodel.objDict[:M])
    H = getvalue(optmodel.objDict[:H])

    individual_plans = Dict{Plant,HydroPlan{eltype(data)}}()

    for plant in plants
        individual_plans[plant] = HydroPlan([Q[plant,1,t] + Q[plant,2,t] for t in 1:nhours(horizon)],
                                            [S[plant,t] for t in 1:nhours(horizon)],
                                            [M[plant,t] for t in 1:nhours(horizon)],
                                            [data[plant].μ[1]*Q[plant,1,t] + data[plant].μ[2]*Q[plant,2,t] for t in 1:nhours(horizon)])
    end

    total_plan = HydroPlan(sum(p.Q for p in values(individual_plans)),
                           sum(p.S for p in values(individual_plans)),
                           sum(p.M for p in values(individual_plans)),
                           sum(p.H for p in values(individual_plans)))

    total_plan.H ≈ H.innerArray || error("Difference in total production")

    return HydroProductionPlan(model.horizon,
                               data,
                               total_plan,
                               individual_plans)
end

# function HydroProductionPlan(horizon::Horizon,modeldata::HydroModelData,plants::Vector{Plant},model::JuMPModel,scenario::Int64)
#     @assert haskey(model.objDict,:Q) && haskey(model.objDict,:S) && haskey(model.objDict,:M) && haskey(model.objDict,:H) "Given JuMP model does not model hydro power production"

#     Q = getvalue(model.objDict[:Q])
#     S = getvalue(model.objDict[:S])
#     M = getvalue(model.objDict[:M])
#     H = getvalue(model.objDict[:H])
#     μ = modeldata.μ

#     individual_plans = Dict{Plant,Plan}()

#     for plant in plants
#         individual_plans[plant] = Plan([Q[scenario,plant,1,t] + Q[scenario,plant,2,t] for t in 1:hours(horizon)],
#                                        [S[scenario,plant,t] for t in 1:hours(horizon)],
#                                        [M[scenario,plant,t] for t in 1:hours(horizon)],
#                                        [μ[plant,1]*Q[scenario,plant,1,t] + μ[plant,2]*Q[scenario,plant,2,t] for t in 1:hours(horizon)])
#     end

#     total_plan = Plan(sum(p.Q for p in values(individual_plans)),
#                       sum(p.S for p in values(individual_plans)),
#                       sum(p.M for p in values(individual_plans)),
#                       sum(p.H for p in values(individual_plans)))

#     @assert total_plan.H ≈ H.innerArray[scenario,:] "Difference in total production"

#     return HydroProductionPlan(horizon,
#                           modeldata,
#                           individual_plans,
#                           total_plan)
# end

plants(plan::HydroProductionPlan) = collect(keys(plan.individual_plans))

discharge(plan::HydroProductionPlan) = plan.total_plan.Q
function discharge(plan::HydroProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].Q
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

spillage(plan::HydroProductionPlan) = plan.total_plan.S
function spillage(plan::HydroProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].S
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

reservoir(plan::HydroProductionPlan) = plan.total_plan.M
function reservoir(plan::HydroProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].M
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

power(plan::HydroProductionPlan) = plan.total_plan.H
function power(plan::HydroProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].H
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

function revenue(plan::HydroProductionPlan,λ::Vector{Float64})
    length(λ) >= nhours(plan.horizon) || error("Price vector is to short")
    return plan.H .* λ
end

function totalrevenue(plan::HydroProductionPlan,λ::Vector{Float64})
    length(λ) >= nhours(plan.horizon) || error("Price vector is to short")
    return plan.H⋅λ
end

function Base.mean(plans::Vector{HydroProductionPlan{T}}) where T <: AbstractFloat
    individual_plans = Dict{Plant,HydroPlan{T}}()

    for plant in plants(plans[1])
        individual_plans[plant] = HydroPlan(mean([p.individual_plans[plant].Q for p in plans]),
                                            mean([p.individual_plans[plant].S for p in plans]),
                                            mean([p.individual_plans[plant].M for p in plans]),
                                            mean([p.individual_plans[plant].H for p in plans]))
    end

    total_plan = HydroPlan(sum(p.Q for p in values(individual_plans)),
                           sum(p.S for p in values(individual_plans)),
                           sum(p.M for p in values(individual_plans)),
                           sum(p.H for p in values(individual_plans)))

    return HydroProductionPlan(plans[1].horizon,
                               plans[1].modeldata,
                               individual_plans,
                               total_plan)
end

@recipe function f(plan::HydroProductionPlan; showHmax = false)
    Hmin = minimum(plan.total_plan.H)
    Hmax = showHmax ? sum([plan.modeldata.H̅[p] for p in plants(plan)]) : maximum(plan.total_plan.H)
    increment = mean(abs.(diff(plan.total_plan.H)))

    linewidth --> 4
    linecolor --> :black
    tickfontsize := 14
    tickfontfamily := "sans-serif"
    guidefontsize := 16
    guidefontfamily := "sans-serif"
    titlefontsize := 22
    titlefontfamily := "sans-serif"
    xlabel := "Hour"
    ylabel := "Energy Volume [MWh]"
    xlims := (1,nhours(plan.horizon))
    ylims := (Hmin-increment,Hmax+increment)
    xticks := 1:1:nhours(plan.horizon)
    yticks := Hmin:increment:Hmax
    yformatter := (d) -> @sprintf("%.2f",d)

    @series begin
        label --> "H"
        1:1:nhours(plan.horizon),plan.total_plan.H
    end

    if showHmax
        @series begin
            label --> "Hmax"
            linestyle --> :dash
            linecolor --> :black
            linewidth --> 2
            0:1:nhours(plan.horizon),fill(Hmax,nhours(plan.horizon))
        end
    end
end

@recipe function f(plan::HydroProductionPlan,plant::Plant; showHmax = false)
    if !(plant in plants(plant))
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
    Hmin = minimum(plan.total_plan.H)
    Hmax = showHmax ? sum([plan.modeldata.H̅[p] for p in plants(plan)]) : maximum(plan.total_plan.H)
    increment = std(plan.total_plan.H)

    linewidth --> 4
    linecolor --> :black
    xlims := (-1,nhours(horizon))
    ylims := (Hmin-increment,Hmax+increment)
    xticks := 0:1:nhours(plan.horizon)
    yticks := Hmin:increment:Hmax

    @series begin
        plan.individual_plans[plant].H
    end

    if showHmax
        @series begin
            linestyle --> :dash
            linecolor --> :black
            linewidth --> 2
            fill(plan.modeldata.H̅[plant],nhours(plan.horizon))
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", plan::HydroProductionPlan)
    show(io,plan)
end

function Base.show(io::IO, plan::HydroProductionPlan)
    if get(io, :multiline, false)
        print(io,"Production Plan")
    else
        println(io,"Hydro Power Production Plan")
        println(io,"Power production:")
        Base.print_matrix(io,plan.total_plan.H)
    end
end
