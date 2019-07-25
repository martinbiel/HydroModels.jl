struct WeekAheadData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}

    function WeekAheadData(plantdata::HydroPlantCollection{T,2}) where T <: AbstractFloat
        return new{T}(plantdata)
    end
end

function WeekAheadData(plantfilename::String)
    WeekAheadData(HydroPlantCollection(plantfilename))
end
