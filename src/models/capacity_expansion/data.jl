struct CapacityExpansionData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    resolution::Resolution
    investment_levels::Vector{T}
    expansion_cost::T
    discount_rate::T
    investment_period::Int

    function CapacityExpansionData(plantdata::HydroPlantCollection{T,2},
                                   investment_levels::Vector{T};
                                   hours_in_period::Integer = 24,
                                   expansion_cost::T = 0.79,
                                   discount_rate::T = 0.05,
                                   investment_period::Integer = 40) where T <: AbstractFloat
        return new{T}(plantdata, Resolution(hours_in_period), investment_levels, expansion_cost, discount_rate, investment_period)
    end
end

function CapacityExpansionData(plantfilename::String, investment_levels::AbstractVector; kw...)
    return CapacityExpansionData(HydroPlantCollection(plantfilename), investment_levels; kw...)
end

function CapacityExpansionData(plantfilename::String; kw...)
    investment_levels = collect(0.0:10:100.0)
    return CapacityExpansionData(HydroPlantCollection(plantfilename), investment_levels; kw...)
end

function equivalent_cost(data::CapacityExpansionData, horizon::Horizon, level_index::Integer)
    C = data.investment_levels[level_index] * data.expansion_cost * 1e6
    if iszero(C)
        return C
    end
    r = data.discount_rate
    P = data.investment_period
    T = num_days(horizon)
    # Calculate equivalent rate
    rᴱ = (1 + r)^(T/365) - 1
    # Calculate equivalent cost
    Cᴱ = C * rᴱ / (1 - (1 + rᴱ)^(-P * 365 / T))
    # Return equivalent cost
    return Cᴱ
end
