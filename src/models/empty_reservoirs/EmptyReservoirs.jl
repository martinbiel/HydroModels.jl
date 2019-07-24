@reexport module EmptyReservoirs

# Standard library
using Statistics
using Printf
using Dates

using RecipesBase
using Distributions
using Parameters
using StochasticPrograms
using Flux
using HydroModels
using HydroModels: AbstractHydroModel, River, Plant, Area, Scenario, Forecaster, forecast

import HydroModels: modelindices

using Plots: font, text, Shape

export
    EmptyReservoirsData,
    EmptyReservoirsScenario,
    EmptyReservoirsSampler,
    EmptyReservoirsModel

include("data.jl")
include("scenarios.jl")
include("indices.jl")
include("model.jl")

end
