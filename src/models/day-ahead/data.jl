@with_kw struct TradeRegulations{T <: AbstractFloat}
    lot::T = 0.1                  # Trade lot in MWh
    dayaheadfee::T = 0.04         # Fee for day ahead trades (EUR/MWh)
    intradayfee::T = 0.11         # Fee for intraday trades (EUR/MWh)
    blocklimit::T = 500.0         # Maximum volume (MWh) in block orders
    blockminlength::Int = 3       # Minimum amount of consecutive hours in block orders
    imbalancelimit::T = 200.0     # Maximum volume (MWh) that has to be settled in the intraday market
    lowerorderlimit::T = -500.0   # Lower technical order price limit (EUR)
    upperorderlimit::T = 3000.0   # Upper technical order price limit (EUR)
end
NordPoolRegulations() = TradeRegulations{Float64}()

struct DayAheadData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    regulations::TradeRegulations{T}
    bidprices::Vector{T}
    pricedata::PriceData{T}
    λ̄::T

    function (::Type{DayAheadData})(plantdata::HydroPlantCollection{T,2},regulations::TradeRegulations{T},bidprices::Vector{T},pricedata::PriceData{T},λ̄::T) where T <: AbstractFloat
        return new{T}(plantdata,regulations,bidprices,pricedata,λ̄)
    end
end

function DayAheadData(plantfilename::String,pricefilename::String,λ̱::AbstractFloat,λ̄::AbstractFloat)
    regulations = NordPoolRegulations()
    bidprices = collect(range(λ̱,stop=λ̄,length=3))
    prepend!(bidprices,regulations.lowerorderlimit)
    push!(bidprices,regulations.upperorderlimit)
    prices = PriceData(pricefilename)
    DayAheadData(HydroPlantCollection(plantfilename),regulations,bidprices,prices,expected(prices))
end

function NordPoolDayAheadData(plantfilename::String,pricefilename::String,area::Integer,λ̱::AbstractFloat,λ̄::AbstractFloat)
    regulations = NordPoolRegulations()
    bidprices = collect(range(λ̱,stop=λ̄,length=3))
    prepend!(bidprices,regulations.lowerorderlimit)
    push!(bidprices,regulations.upperorderlimit)
    prices = NordPoolPriceData(pricefilename,Day(),area)
    DayAheadData(HydroPlantCollection(plantfilename),regulations,bidprices,prices,HydroModels.expected(prices))
end
