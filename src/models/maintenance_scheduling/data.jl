struct MaintenanceSchedulingData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    minimize_loss::Bool

    function MaintenanceSchedulingData(plantdata::HydroPlantCollection{T,2}; minimize_loss::Bool = false) where T <: AbstractFloat
        return new{T}(plantdata, minimize_loss)
    end
end

function MaintenanceSchedulingData(plantfilename::String; minimize_loss::Bool = false)
    return MaintenanceSchedulingData(HydroPlantCollection(plantfilename); minimize_loss = minimize_loss)
end
