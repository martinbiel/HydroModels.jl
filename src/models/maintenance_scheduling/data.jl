struct MaintenanceSchedulingData{T <: AbstractFloat} <: AbstractModelData
    hydrodata::HydroPlantCollection{T,2}
    bidlevels::Vector{Vector{T}}
    reschedule::Bool

    function MaintenanceSchedulingData(plantdata::HydroPlantCollection{T,2},
                                       bidlevels::Vector{Vector{T}},
                                       reschedule::Bool) where T <: AbstractFloat
        length(bidlevels) == 24 || error("Supply exactly 24 bidlevel sets")
        all(length.(bidlevels) .== length(bidlevels[1])) || error("All bidlevel sets must be of the same length.")
        return new{T}(plantdata, bidlevels, reschedule)
    end
end

function MaintenanceSchedulingData(plantfilename::String, bidlevelsets::AbstractMatrix; reschedule::Bool = false)
    size(bidlevelsets, 2) == 24 || error(" ")
    plantdata = HydroPlantCollection(plantfilename)
    bidlevels = [bidlevelsets[:,i] for i = 1:size(bidlevelsets, 2)]
    for i in eachindex(bidlevels)
        prepend!(bidlevels[i], -500.0)
        push!(bidlevels[i], 3000.0)
    end
    MaintenanceSchedulingData(plantdata, bidlevels, reschedule)
end

function MaintenanceSchedulingData(plantfilename::String, bidlevels::AbstractVector; reschedule::Bool = false)
    plantdata = HydroPlantCollection(plantfilename)
    prepend!(bidlevels, -500.0)
    push!(bidlevels, 3000.0)
    MaintenanceSchedulingData(plantdata, fill(bidlevels, 24), reschedule)
end
