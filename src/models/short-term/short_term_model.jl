struct ShortTermIndices <: AbstractModelIndices
    hours::Vector{Int}
    plants::Vector{Plant}
    segments::Vector{Int}
end
plants(indices::ShortTermIndices) = indices.plants

struct ShortTermData{T <: AbstractFloat} <: AbstractModelData
    plantdata::HydroPlantCollection{T,2}
    pricecurve::PriceCurve{T}

    function (::Type{ShortTermData})(plantdata::HydroPlantCollection{T,2},pricecurve::PriceCurve{T}) where T <: AbstractFloat
        return new{T}(plantdata,pricecurve)
    end
end
function ShortTermData(plantfilename::String,pricecurve::PriceCurve)
    ShortTermData(HydroPlantCollection(plantfilename),pricecurve)
end

function modelindices(horizon::Horizon,data::ShortTermData,areas::Vector{Area},rivers::Vector{River})
    hours = collect(1:nhours(horizon))
    plants = plants_in_areas_and_rivers(data.plantdata,areas,rivers)
    if isempty(plants)
        error("No plants in given set of price areas and rivers")
    end
    segments = collect(1:2)
    return ShortTermIndices(hours, plants, segments)
end

# @deterministic_hydro ShortTerm = begin

@hydromodel Deterministic ShortTerm = begin
    @unpack hours, plants, segments = indices
    hdata = data.plantdata
    λ = data.pricecurve
    λ̄ = expected(λ)
    HydroModels.horizon(λ) >= horizon || error("Not enough price data for chosen horizon")

    # Variables
    # ========================================================
    @variable(model, Q[p = plants, s = segments, t = hours], lowerbound = 0, upperbound = hdata[p].Q̄[s])
    @variable(model, S[p = plants, t = hours] >= 0)
    @variable(model, M[p = plants, t = hours], lowerbound = 0, upperbound = hdata[p].M̄)
    @variable(model, H[t = hours] >= 0)
    @variable(model, Qf[p = plants, t = hours] >= 0)
    @variable(model, Sf[p = plants, t = hours] >= 0)

    # Objectives
    # ========================================================
    # Net profit
    @expression(model, net_profit, sum(λ[t]*H[t] for t = hours))
    # Value of stored water
    @expression(model,value_of_stored_water,
                λ̄*sum(M[p,nhours(horizon)]*sum(hdata[i].μ[1]
                                                    for i = hdata.Qd[p])
                               for p = plants))
    # Define objective
    @objective(model, Max, net_profit + value_of_stored_water)

    # Constraints
    # ========================================================
    # Hydrological balance
    @constraint(model, hydro_constraints[p = plants, t = hours],
                # Previous reservoir content
                M[p,t] == (t > 1 ? M[p,t-1] : hdata[p].M₀)
                # Inflow
                + sum(Qf[i,t]
                      for i = intersect(hdata.Qu[p],plants))
                + sum(Sf[i,t]
                      for i = intersect(hdata.Su[p],plants))
                # Local inflow
                + hdata[p].V
                + (t <= hdata[p].Rqh ? 1 : 0)*sum(hdata[i].Q̃
                                                  for i = hdata.Qu[p])
                + (t == (hdata[p].Rqh + 1) ? 1 : 0)*sum(hdata[i].Q̃*(1-hdata[p].Rqm/60)
                                                         for i = hdata.Qu[p])
                # Outflow
                - sum(Q[p,s,t]
                      for s = segments)
                - S[p,t]
                )

    # Water flow: Discharge + Spillage
    @constraintref Qflow[1:length(plants),1:nhours(horizon)]
    @constraintref Sflow[1:length(plants),1:nhours(horizon)]
    for (pidx,p) = enumerate(plants)
        for t = hours
            if t - hdata[p].Rqh > 1
                Qflow[pidx,t] = @constraint(model,
                                            Qf[p,t] == (hdata[p].Rqm/60)*sum(Q[p,s,t-(hdata[p].Rqh+1)]
                                                                             for s = segments)
                                            + (1-hdata[p].Rqm/60)*sum(Q[p,s,t-hdata[p].Rqh]
                                                                      for s = segments)
                                            )
            elseif t - hdata[p].Rqh > 0
                Qflow[pidx,t] = @constraint(model,
                                            Qf[p,t] == (1-hdata[p].Rqm/60)*sum(Q[p,s,t-hdata[p].Rqh]
                                                                               for s = segments)
                                            )
            else
                Qflow[pidx,t] = @constraint(model,
                                            Qf[p,t] == 0
                                            )
            end
            if t - hdata[p].Rsh > 1
                Sflow[pidx,t] = @constraint(model,
                                            Sf[p,t] == (hdata[p].Rsm/60)*S[p,t-(hdata[p].Rsh+1)]
                                            + (1-hdata[p].Rsm/60)*S[p,t-hdata[p].Rsh]
                                            )
            elseif t - hdata[p].Rsh > 0
                Sflow[pidx,t] = @constraint(model,
                                            Sf[p,t] == (1-hdata[p].Rsm/60)*S[p,t-hdata[p].Rsh]
                                            )
            else
                Sflow[pidx,t] = @constraint(model,
                                            Sf[p,t] == 0
                                            )
            end
        end
    end

    # Power production
    @constraint(model, production[t = hours],
                H[t] == sum(hdata[p].μ[s]*Q[p,s,t]
                            for p = plants, s = segments)
                )
end

ShortTermModel(horizon::Horizon,modeldata::AbstractModelData,area::Area,river::River) = ShortTermModel(horizon,modeldata,[area],[river])
ShortTermModel(horizon::Horizon,modeldata::AbstractModelData,area::Area) = ShortTermModel(horizon,modeldata,[area],[:All])
ShortTermModel(horizon::Horizon,modeldata::AbstractModelData,areas::Vector{Area}) = ShortTermModel(horizon,modeldata,areas,[:All])
ShortTermModel(horizon::Horizon,modeldata::AbstractModelData,river::River) = ShortTermModel(horizon,modeldata,[0],[river])
ShortTermModel(horizon::Horizon,modeldata::AbstractModelData,rivers::Vector{River}) = ShortTermModel(horizon,modeldata,[0],rivers)
ShortTermModel(horizon::Horizon,modeldata::AbstractModelData) = ShortTermModel(horizon,modeldata,[0],[:All])
