struct EmptyReservoirsData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}

    function EmptyReservoirsData(plantdata::HydroPlantCollection{T,2}) where T <: AbstractFloat
        return new{T}(plantdata)
    end
end

function EmptyReservoirsData(plantfilename::String)
    EmptyReservoirsData(HydroPlantCollection(plantfilename))
end

function maximum_horizon(M₀::AbstractVector, data::EmptyReservoirsData)
    hydrodata = data.hydrodata
    length(M₀) == length(hydrodata.plants) || error("Incorrect number of reservoir volumes")
    Q̄ = [sum(hydrodata.plantdata[p].Q̄) for p in hydrodata.plants]
    minreq = round(Int, maximum(M₀ ./ Q̄))
    return Horizon(minreq + (24 - minreq % 24))
end

function maximum_horizon(data::EmptyReservoirsData)
    hydrodata = data.hydrodata
    M̄ = [hydrodata.plantdata[p].M̄ for p in hydrodata.plants]
    return maximum_horizon(M̄, data)
end
