struct Plan
    Q::Vector{Float64} # Discharge each hour
    S::Vector{Float64} # Spillage each hour
    M::Vector{Float64} # Reservoir content each hour
    H::Vector{Float64} # Resulting electricity production each hour
end

struct ProductionPlan
    horizon::Horizon                     # Planning horizon
    modeldata::HydroModelData

    individual_plans::Dict{Plant,Plan}   # Plans for each hydro power plant
    total_plan::Plan                     # Accumulation of individual plans
end

function ProductionPlan(horizon::Horizon,modeldata::HydroModelData,plants::Vector{Plant},model::JuMPModel)
    @assert haskey(model.objDict,:Q) && haskey(model.objDict,:S) && haskey(model.objDict,:M) && haskey(model.objDict,:H) "Given JuMP model does not model hydro power production"

    Q = getvalue(model.objDict[:Q])
    S = getvalue(model.objDict[:S])
    M = getvalue(model.objDict[:M])
    H = getvalue(model.objDict[:H])
    μ = modeldata.μ

    individual_plans = Dict{Plant,Plan}()

    for plant in plants
        individual_plans[plant] = Plan([Q[plant,1,t] + Q[plant,2,t] for t in 1:hours(horizon)],
                                       [S[plant,t] for t in 1:hours(horizon)],
                                       [M[plant,t] for t in 1:hours(horizon)],
                                       [μ[plant,1]*Q[plant,1,t] + μ[plant,2]*Q[plant,2,t] for t in 1:hours(horizon)])
    end

    total_plan = Plan(sum(p.Q for p in values(individual_plans)),
                      sum(p.S for p in values(individual_plans)),
                      sum(p.M for p in values(individual_plans)),
                      sum(p.H for p in values(individual_plans)))

    @assert total_plan.H ≈ H.innerArray "Difference in total production"

    return ProductionPlan(horizon,
                          modeldata,
                          individual_plans,
                          total_plan)
end

function ProductionPlan(horizon::Horizon,modeldata::HydroModelData,plants::Vector{Plant},model::JuMPModel,scenario::Int64)
    @assert haskey(model.objDict,:Q) && haskey(model.objDict,:S) && haskey(model.objDict,:M) && haskey(model.objDict,:H) "Given JuMP model does not model hydro power production"

    Q = getvalue(model.objDict[:Q])
    S = getvalue(model.objDict[:S])
    M = getvalue(model.objDict[:M])
    H = getvalue(model.objDict[:H])
    μ = modeldata.μ

    individual_plans = Dict{Plant,Plan}()

    for plant in plants
        individual_plans[plant] = Plan([Q[scenario,plant,1,t] + Q[scenario,plant,2,t] for t in 1:hours(horizon)],
                                       [S[scenario,plant,t] for t in 1:hours(horizon)],
                                       [M[scenario,plant,t] for t in 1:hours(horizon)],
                                       [μ[plant,1]*Q[scenario,plant,1,t] + μ[plant,2]*Q[scenario,plant,2,t] for t in 1:hours(horizon)])
    end

    total_plan = Plan(sum(p.Q for p in values(individual_plans)),
                      sum(p.S for p in values(individual_plans)),
                      sum(p.M for p in values(individual_plans)),
                      sum(p.H for p in values(individual_plans)))

    @assert total_plan.H ≈ H.innerArray[scenario,:] "Difference in total production"

    return ProductionPlan(horizon,
                          modeldata,
                          individual_plans,
                          total_plan)
end

plants(plan::ProductionPlan) = collect(keys(plan.individual_plans))

discharge(plan::ProductionPlan) = plan.total_plan.Q
function discharge(plan::ProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].Q
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

spillage(plan::ProductionPlan) = plan.total_plan.S
function spillage(plan::ProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].S
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

reservoir(plan::ProductionPlan) = plan.total_plan.M
function reservoir(plan::ProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].M
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

power(plan::ProductionPlan) = plan.total_plan.H
function power(plan::ProductionPlan,plant::Plant)
    if plant in plants(plan)
        return plan.individual_plans[plant].H
    else
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
end

function revenue(plan::ProductionPlan,λ::Vector{Float64})
    @assert length(λ) >= hours(plan.horizon) "Price vector is to short"
    return plan.H .* λ
end

function totalrevenue(plan::ProductionPlan,λ::Vector{Float64})
    @assert length(λ) >= hours(plan.horizon) "Price vector is to short"
    return plan.H⋅λ
end

function Base.mean(plans::Vector{ProductionPlan})
    individual_plans = Dict{Plant,Plan}()

    for plant in plants(plans[1])
        individual_plans[plant] = Plan(mean([p.individual_plans[plant].Q for p in plans]),
                                       mean([p.individual_plans[plant].S for p in plans]),
                                       mean([p.individual_plans[plant].M for p in plans]),
                                       mean([p.individual_plans[plant].H for p in plans]))
    end

    total_plan = Plan(sum(p.Q for p in values(individual_plans)),
                      sum(p.S for p in values(individual_plans)),
                      sum(p.M for p in values(individual_plans)),
                      sum(p.H for p in values(individual_plans)))

    return ProductionPlan(plans[1].horizon,
                          plans[1].modeldata,
                          individual_plans,
                          total_plan)
end

@recipe function f(plan::ProductionPlan; showHmax = false)
    Hmin = minimum(plan.total_plan.H)
    Hmax = showHmax ? sum([plan.modeldata.H̅[p] for p in plants(plan)]) : maximum(plan.total_plan.H)
    increment = mean(abs.(diff(plan.total_plan.H)))

    linewidth --> 4
    linecolor --> :black
    tickfont := font(14,"sans-serif")
    guidefont := font(16,"sans-serif")
    titlefont := font(22,"sans-serif")
    xlabel := "Hour"
    ylabel := "Energy Volume [MWh]"
    xlims := (0,hours(plan.horizon))
    ylims := (Hmin-increment,Hmax+increment)
    xticks := 0:1:hours(plan.horizon)
    yticks := Hmin:increment:Hmax
    yformatter := (d) -> @sprintf("%.2f",d)

    @series begin
        label --> "H"
        0:1:hours(plan.horizon),plan.total_plan.H
    end

    if showHmax
        @series begin
            label --> "Hmax"
            linestyle --> :dash
            linecolor --> :black
            linewidth --> 2
            0:1:hours(plan.horizon),fill(Hmax,hours(plan.horizon))
        end
    end
end

@recipe function f(plan::ProductionPlan,plant::Plant; showHmax = false)
    if !(plant in plants(plant))
        throw(ArgumentError(string("Selected plant ",hour," not in production plan")))
    end
    Hmin = minimum(plan.total_plan.H)
    Hmax = showHmax ? sum([plan.modeldata.H̅[p] for p in plants(plan)]) : maximum(plan.total_plan.H)
    increment = std(plan.total_plan.H)

    linewidth --> 4
    linecolor --> :black
    xlims := (-1,hours(horizon))
    ylims := (Hmin-increment,Hmax+increment)
    xticks := 0:1:hours(plan.horizon)
    yticks := Hmin:increment:Hmax

    @series begin
        plan.individual_plans[plant].H
    end

    if showHmax
        @series begin
            linestyle --> :dash
            linecolor --> :black
            linewidth --> 2
            fill(plan.modeldata.H̅[plant],hours(plan.horizon))
        end
    end
end

function show(io::IO, ::MIME"text/plain", plan::ProductionPlan)
    show(io,plan)
end

function show(io::IO, plan::ProductionPlan)
    if get(io, :multiline, false)
        print(io,"Production Plan")
    else
        println(io,"Hydro Power Production Plan")
        println(io,"Power production:")
        Base.print_matrix(io,plan.total_plan.H)
    end
end
