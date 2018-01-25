module HydroModels

# Import functions for overloading
import Base.show

# Packages
using JuMP
using StructJuMP
using Clp
using RecipesBase
using Parameters

import MathProgBase.SolverInterface.AbstractMathProgSolver
import MathProgBase.SolverInterface.status
import Plots.font
import Plots.text
import Plots.Shape
import Plots.px

export
    HydroModelData,
    ShortTermModel,
    DayAheadModel,
    initialize!,
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
    dependent

JuMPModel = JuMP.Model
JuMPVariable = JuMP.Variable

# Include files
include("horizon.jl")
include("segmenter.jl")
include("modeldata.jl")
include("productionplan.jl")
include("model.jl")
include("deterministic.jl")
include("stochastic.jl")

# Models
include("day-ahead/DayAhead.jl")
include("short-term/short_term_model.jl")

end # module
