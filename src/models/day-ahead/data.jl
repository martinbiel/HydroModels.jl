@with_kw struct TradeRegulations{T <: AbstractFloat}
    lot::T = 0.1                  # Trade lot in MWh
    dayaheadfee::T = 0.04         # Fee for day ahead trades (EUR/MWh)
    intradayfee::T = 0.11         # Fee for intraday trades (EUR/MWh)
    blocklimit::T = 500.0         # Maximum volume (MWh) in block orders
    blockminlength::Int = 3       # Minimum amount of consecutive hours in block orders
    nblockorders::Int = 50        # Maximum number of block orders in portfolio
    imbalancelimit::T = 200.0     # Maximum volume (MWh) that can be settled in the intraday market
    lowerorderlimit::T = -500.0   # Lower technical order price limit (EUR)
    upperorderlimit::T = 3000.0   # Upper technical order price limit (EUR)
end
NordPoolRegulations() = TradeRegulations{Float64}()

struct DayAheadData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    water_value::PolyhedralWaterValue{T}
    regulations::TradeRegulations{T}
    intraday_trading::Bool
    simple_water_value::Bool
    penalty_percentage::Float64
    use_blockbids::Bool
    bidlevels::Vector{Vector{T}}

    function DayAheadData(plantdata::HydroPlantCollection{T,2},
                          water_value::PolyhedralWaterValue{T},
                          regulations::TradeRegulations{T},
                          bidlevels::Vector{Vector{T}};
                          intraday_trading::Bool = true,
                          simple_water_value::Bool = false,
                          penalty_percentage::Float64 = 0.0,
                          use_blockbids::Bool = true) where T <: AbstractFloat
        length(bidlevels) == 24 || error("Supply exactly 24 bidlevel sets")
        all(length.(bidlevels) .== length(bidlevels[1])) || error("All bidlevel sets must be of the same length.")
        return new{T}(plantdata, water_value, regulations, intraday_trading, simple_water_value, penalty_percentage, use_blockbids, bidlevels)
    end
end

function DayAheadData(plantfilename::String, watervalue_filename, bidlevelsets::AbstractMatrix; intraday_trading = true, simple_water_value = false, penalty_percentage = 0.0, use_blockbids = true)
    size(bidlevelsets, 2) == 24 || error(" ")
    plantdata = HydroPlantCollection(plantfilename)
    water_value = PolyhedralWaterValue(watervalue_filename)
    regulations = NordPoolRegulations()
    bidlevels = [bidlevelsets[:,i] for i = 1:size(bidlevelsets, 2)]
    for i in eachindex(bidlevels)
        prepend!(bidlevels[i], regulations.lowerorderlimit)
        push!(bidlevels[i], regulations.upperorderlimit)
    end
    DayAheadData(plantdata, water_value, regulations, bidlevels, intraday_trading = intraday_trading, simple_water_value = simple_water_value, penalty_percentage = penalty_percentage, use_blockbids = use_blockbids)
end

function DayAheadData(plantfilename::String, watervalue_filename, bidlevels::AbstractVector; intraday_trading = true, use_blockbids = true)
    plantdata = HydroPlantCollection(plantfilename)
    water_value = PolyhedralWaterValue(watervalue_filename)
    regulations = NordPoolRegulations()
    prepend!(bidlevels, regulations.lowerorderlimit)
    push!(bidlevels, regulations.upperorderlimit)
    DayAheadData(plantdata, water_value, regulations, fill(bidlevels, 24), intraday_trading = intraday_trading, use_blockbids = use_blockbids)
end
