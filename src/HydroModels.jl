module HydroModels

# Packages
using JuMP
using StochasticPrograms
using Clp
using RecipesBase
using Parameters
using MacroTools
using MacroTools: postwalk, @q

import MathProgBase.SolverInterface.AbstractMathProgSolver
import MathProgBase.SolverInterface.status
# import Plots.text
# import Plots.Shape

export
    HydroModelData,
    ShortTermModel,
    DayAheadModel,
    reinitialize!,
    plan!,
    production,
    strategy,
    plants,
    discharge,
    spillage,
    reservoir,
    power,
    revenue,
    totalrevenue,
    singleorder,
    singleorders,
    blockorders,
    independent,
    dependent,
    Day,
    Week

JuMPModel = JuMP.Model
JuMPVariable = JuMP.Variable

# Include files
include("data/data.jl")
include("models/model.jl")

# Models
include("models/short-term/short_term_model.jl")
include("models/day-ahead/DayAhead.jl")

# Analysis
include("productionplan.jl")
include("models/day-ahead/orderstrategy.jl")

end # module
