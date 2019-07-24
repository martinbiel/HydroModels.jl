struct WeekAheadData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    water_value::PolyhedralWaterValue{T}

    function WeekAheadData(plantdata::HydroPlantCollection{T,2}, water_value::PolyhedralWaterValue{T}) where T <: AbstractFloat
        return new{T}(plantdata, water_value)
    end
end

function WeekAheadData(plantfilename::String, watervalue_filename::String)
    plantdata = HydroPlantCollection(plantfilename)
    water_value = PolyhedralWaterValue(plantdata.plants, watervalue_filename)
    WeekAheadData(plantdata, water_value)
end
