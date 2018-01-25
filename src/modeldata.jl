River = Symbol
Area = Int
Plant = Symbol

struct PlantData{T <: AbstractFloat, S}
    M₀::T                # Initial reservoir contents
    M̅::T                 # Maximum reservoir capacities
    H̅::T                 # Maximal production
    Q̅::NTuple{S,T}       # Maximal discharge in each segment
    μ::NTuple{S,T}       # Marginal production equivalents in each segment
    S̱::T                 # Minimum spillage
    Rqh::Int             # Discharge flow time in whole hours
    Rqm::Int             # Discharge flow time in remaining minutes
    Rsh::Int             # Spillage flow time in whole hours
    Rsm::Int             # Spillage flow time in remaining minutes
    Q̃::T                 # Yearly mean flow of each plant
    V::T                 # Local inflow

    function (::Type{PlantData})(M₀::AbstractFloat,M̅::AbstractFloat,H̅::AbstractFloat,Q̅::NTuple{S,<:AbstractFloat},μ::NTuple{S,<:AbstractFloat},S̱::AbstractFloat,Rgh::Integer,Rqm::Integer,Rsh::Integer,Rsm::Integer,Q̃::AbstractFloat,V::AbstractFloat) where S
        T = promote_type(typeof(M₀),typeof(M̅),typeof(H̅),eltype(Q̅),eltype(μ),typeof(S̱),typeof(Q̃),typeof(V),Float32)
        return new{T,S}(M₀,M̅,H̅,Q̅,μ,S̱,Rgh,Rqm,Rsh,Rsm,Q̃,V)
    end
end

struct HydroModelData{T <: AbstractFloat, S}
    # Plants
    # ========================================================
    plants::Vector{Plant}                   # All possible plant instances
    rivers::Dict{River,Vector{Plant}}       # Plants sorted according to river
    areas::Dict{Area,Vector{Plant}}         # Plants sorted according to price area
    # Parameters
    # ========================================================
    plantdata::Dict{Plant,PlantData{T,S}}   # Data for each plant
    Qd::Dict{Plant,Vector{Plant}}           # All discharge outlets located downstream (including itself)
    Qu::Dict{Plant,Vector{Plant}}           # Discharge outlet(s) located directly upstream
    Sd::Dict{Plant,Vector{Plant}}           # Spillage outlets located downstream (including itself)
    Su::Dict{Plant,Vector{Plant}}           # Spillage outlet(s) located directly upstream

    function HydroModelData(::Type{T},::Type{Segmenter{S}},plantfilename::String) where {T <: AbstractFloat, S}
        modeldata = new{T,S}(Vector{Plant}(),
                             Dict{River,Vector{Plant}}(),
                             Dict{Area,Vector{Plant}}(),
                             Dict{Plant,PlantData{T,S}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),)
        define_model_parameters(modeldata,plantfilename)
        return modeldata
    end
end

function HydroModelData(plant_filename::String)
    return HydroModelData(Float64,Segmenter{2},plant_filename)
end

function define_plants!(modeldata::HydroModelData,plantnames::Vector{String})
    for plantname in plantnames
        push!(modeldata.plants,Plant(filter(x->!isspace(x),plantname)))
    end
end

function define_rivers!(modeldata::HydroModelData,rivernames::Vector{String})
    for (p,rivername) in enumerate(rivernames)
        plant = modeldata.plants[p]
        river = River(filter(x->!isspace(x),rivername))
        if !haskey(modeldata.rivers,river)
            modeldata.rivers[river] = Plant[]
        end
        push!(modeldata.rivers[river],plant)
    end
end

function define_areas!(modeldata::HydroModelData,areas::Vector{Area})
    for (p,area) in enumerate(areas)
        plant = modeldata.plants[p]
        if !haskey(modeldata.areas,area)
            modeldata.areas[area] = Plant[]
        end
        push!(modeldata.areas[area],plant)
    end
end

function define_plant_topology!(links::Dict{Plant,Plant},
                                downstream_plants::Dict{Plant,Vector{Plant}},
                                upstream_plants::Dict{Plant,Vector{Plant}})
    linker = (downstream_plants, current, links ) -> begin
        if current == :NoLink
            return
        end
        push!(downstream_plants, current)
        linker(downstream_plants, links[current], links)
    end

    for (plant,link) in links
        if link == :NoLink
            continue
        end
        push!(downstream_plants[plant],plant)
        linker(downstream_plants[plant],link,links)
        push!(upstream_plants[link],plant)
    end
end

function calculate_inflow(plant::Plant,w::Dict{Plant,<:AbstractFloat},upstream_plants::Vector{Plant})
    V = w[plant]
    if !isempty(upstream_plants)
        V -= sum(w[p] for p in upstream_plants)
    end
    return V
end

function define_model_parameters(modeldata::HydroModelData{T,S},
                                 plantnames::Vector{String},
                                 Qlinks::Vector{Int},
                                 Slinks::Vector{Int},
                                 H̅::Vector{T},
                                 Q̅::Vector{T},
                                 S̱::Vector{T},
                                 M̅::Vector{T},
                                 Q̃::Vector{T},
                                 Rq::Vector{Int},
                                 Rs::Vector{Int},
                                 rivers::Vector{String},
                                 areas::Vector{Area}) where {T <: AbstractFloat, S}
    Vsf = 0.2278           # Scale factor for local inflow (0.2278)
    δ = 0.363              # Initial reservoir content factor (0.363)
    M_end = 0.89           # Target water level as factor of M_0 (0.89)

    # Define available plants
    define_plants!(modeldata, plantnames)

    # Define sortings of plants
    define_rivers!(modeldata,rivers)
    define_areas!(modeldata,areas)

    for p in modeldata.plants
        modeldata.Qd[p] = Plant[]
        modeldata.Qu[p] = Plant[]
        modeldata.Sd[p] = Plant[]
        modeldata.Su[p] = Plant[]
    end

    # Define plant topologies
    links_as_plants(links) = Dict([(modeldata.plants[p],(l == 0 ? :NoLink : modeldata.plants[l])) for (p,l) in enumerate(links)])
    define_plant_topology!(links_as_plants(Qlinks), modeldata.Qd, modeldata.Qu)
    define_plant_topology!(links_as_plants(Slinks), modeldata.Sd, modeldata.Su)

    w = Dict(zip(modeldata.plants,Vsf*Q̃))

    for i in 1:length(plantnames)
        Q̅s,μs = segment(Segmenter{S},Q̅[i],H̅[i])
        p = modeldata.plants[i]
        V = calculate_inflow(p,w,modeldata.Qu[p])
        modeldata.plantdata[p] = PlantData(δ*M̅[i],
                                           M̅[i],
                                           H̅[i],
                                           Q̅s,
                                           μs,
                                           S̱[i],
                                           floor(Int64,Rq[i]/60),
                                           mod(Rq[i],60),
                                           floor(Int64,Rs[i]/60),
                                           mod(Rs[i],60),
                                           Vsf*Q̃[i],
                                           V)
    end
end

function define_model_parameters(modeldata::HydroModelData{T}, plantdata::Matrix) where T <: AbstractFloat
    @assert size(plantdata,2) == 12 "Invalid plant data format"

    define_model_parameters(modeldata,
                            convert(Vector{String},plantdata[:,1]),
                            convert(Vector{Int},plantdata[:,2]),
                            convert(Vector{Int},plantdata[:,3]),
                            convert(Vector{T},plantdata[:,4]),
                            convert(Vector{T},plantdata[:,5]),
                            convert(Vector{T},plantdata[:,6]),
                            convert(Vector{T},plantdata[:,7]),
                            convert(Vector{T},plantdata[:,8]),
                            convert(Vector{Int},plantdata[:,9]),
                            convert(Vector{Int},plantdata[:,10]),
                            convert(Vector{String},plantdata[:,11]),
                            convert(Vector{Area},plantdata[:,12]))
end

function define_model_parameters(modeldata::HydroModelData, plantfilename::String)
    plantdata = readcsv(plantfilename)
    define_model_parameters(modeldata,plantdata[2:end,:])
end

function plants_in_river(modeldata::HydroModelData,river::River)
    if river == :All
        return modeldata.plants
    end
    if !haskey(modeldata.rivers,river)
        warn(string("Invalid river name: ", river))
        return Plant[]
    end
    return modeldata.rivers[river]
end

function plants_in_river(modeldata::HydroModelData,rivers::Vector{River})
    plants = Plant[]
    for river in rivers
        append!(plants,plants_in_river(modeldata,river))
    end
    return plants
end

function plants_in_area(modeldata::HydroModelData,area::Area)
    if area == 0
        return modeldata.plants
    end
    if !haskey(modeldata.areas,area)
        warn(string("Invalid area: ",area))
        return Plant[]
    end
    return modeldata.areas[area]
end

function plants_in_area(modeldata::HydroModelData,areas::Vector{Area})
    plants = Plant[]
    for area in areas
        append!(plants,plants_in_area(modeldata,area))
    end
    return plants
end

function plants_in_areas_and_rivers(modeldata::HydroModelData,areas::Vector{Area},rivers::Vector{River})
    return plants_in_river(modeldata,rivers) ∩ plants_in_area(modeldata,areas)
end
