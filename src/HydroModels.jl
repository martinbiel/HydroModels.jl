__precompile__()
module HydroModels

# Standard library
using LinearAlgebra
using DelimitedFiles
using Dates
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
using MathProgBase
using MathProgBase.SolverInterface
using DelimitedFiles
using Flux
using BSON
using BSON: @save, @load

import Base.show
import Statistics.mean

export
    AbstractModelIndices,
    AbstractModelData,
    Horizon,
    HydroPlantCollection,
    hydrodata,
    plants_in_river,
    plants_in_area,
    plants_in_areas_and_rivers,
    PolyhedralWaterValue,
    cuts,
    ncuts,
    lower_bound,
    PriceCurve,
    PriceData,
    Forecaster,
    PriceForecaster,
    FlowForecaster,
    forecast,
    NordPoolPriceData,
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
    Day,
    Week,
    nhours,
    ndays,
    nweeks,
    @hydromodel,
    @deterministic,
    @stochastic,
    ShortTermModel,
    DayAhead,
    WeekAhead

# Include files
include("data/data.jl")
include("models/model.jl")

# Models
include("models/short-term/ShortTerm.jl")
include("models/day-ahead/DayAhead.jl")
include("models/week-ahead/WeekAhead.jl")
include("models/empty_reservoirs/EmptyReservoirs.jl")

# Analysis
include("productionplan.jl")

end # module
