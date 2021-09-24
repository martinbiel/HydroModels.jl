__precompile__()
module HydroModels

# Standard library
using LinearAlgebra
using DelimitedFiles
using Dates
using Statistics
using Printf

# Packages
using JuMP
using StochasticPrograms
using GLPKMathProgInterface
using RecipesBase
using Parameters
using Reexport
using MacroTools
using MacroTools: postwalk, @q
using DelimitedFiles
using Flux
using BSON
using BSON: @save, @load

import Base: show
import Statistics: mean

export
    AbstractModelIndices,
    AbstractModelData,
    Horizon,
    Resolution,
    PlantCollection,
    plants,
    nplants,
    Skellefteälven,
    HydroPlantCollection,
    hydrodata,
    plants_in_river,
    plants_in_area,
    plants_in_areas_and_rivers,
    PolyhedralWaterValue,
    cuts,
    ncuts,
    cut_indices,
    nindices,
    cut_lb,
    PriceCurve,
    PriceData,
    Inflows,
    InflowSequence,
    local_inflows,
    local_inflow_sequence,
    Forecaster,
    PriceForecaster,
    FlowForecaster,
    forecast,
    mean_price,
    reload!,
    reinitialize!,
    plan!,
    status,
    production,
    plants,
    discharge,
    spillage,
    reservoir,
    power,
    revenue,
    totalrevenue,
    num_hours,
    num_days,
    num_weeks,
    num_periods,
    water_volume,
    marginal_production,
    water_flow_time,
    historic_flow,
    overflow,
    DayAhead,
    WeekAhead

macro exportSPjl()
    Expr(:export, names(StochasticPrograms)...)
end
@exportSPjl

# Include files
include("data/data.jl")
include("models/model.jl")

# Models
#include("models/short-term/ShortTerm.jl")
include("models/day-ahead/DayAhead.jl")
include("models/week-ahead/WeekAhead.jl")
include("models/maintenance_scheduling/MaintenanceScheduling.jl")
include("models/capacity_expansion/CapacityExpansion.jl")

# Analysis
include("productionplan.jl")

end # module
