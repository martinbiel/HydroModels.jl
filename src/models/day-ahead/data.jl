@with_kw struct TradeRegulations{T <: AbstractFloat}
    lot::T = 0.1                  # Trade lot in MWh
    dayaheadfee::T = 0.04         # Fee for day ahead trades (EUR/MWh)
    intradayfee::T = 0.11         # Fee for intraday trades (EUR/MWh)
    imbalancelimit::T = 200.0     # Maximum volume (MWh) that has to be settled in the intraday market
    lowerorderlimit::T = -500.0   # Lower technical order price limit (EUR)
    upperorderlimit::T = 3000.0   # Upper technical order price limit (EUR)
end
NordPoolRegulations() = TradeRegulations{Float64}()

struct DayAheadData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    water_value::PolyhedralWaterValue{T}
    regulations::TradeRegulations{T}
    intraday_trading::Bool
    bidprices::Vector{T}
    λ̄::T

    function DayAheadData(plantdata::HydroPlantCollection{T,2},
                          water_value::PolyhedralWaterValue{T},
                          regulations::TradeRegulations{T},
                          bidprices::Vector{T},
                          λ̄::T; intraday_trading::Bool = true) where T <: AbstractFloat
        return new{T}(plantdata, water_value, regulations, intraday_trading, bidprices, λ̄)
    end
end

function DayAheadData(plantfilename::String, watervalue_filename::String, λ::AbstractFloat, λ̱::AbstractFloat, λ̄::AbstractFloat)
    plantdata = HydroPlantCollection(plantfilename)
    water_value = PolyhedralWaterValue(plantdata.plants, watervalue_filename)
    regulations = NordPoolRegulations()
    bidprices = collect(range(λ̱,stop=λ̄,length=3))
    prepend!(bidprices,regulations.lowerorderlimit)
    push!(bidprices,regulations.upperorderlimit)
    DayAheadData(plantdata, water_value, regulations, bidprices, λ)
end

function DayAheadData(plantfilename::String, watervalue_filename, bidprices::AbstractVector)
    plantdata = HydroPlantCollection(plantfilename)
    water_value = PolyhedralWaterValue(plantdata.plants, watervalue_filename)
    regulations = NordPoolRegulations()
    prepend!(bidprices,regulations.lowerorderlimit)
    push!(bidprices,regulations.upperorderlimit)
    DayAheadData(plantdata, water_value, regulations, bidprices, mean(bidprices))
end
