River = Symbol
Area = Int
Plant = Symbol

struct HydroPlantData{T <: AbstractFloat, S}
    M₀::T                # Initial reservoir contents
    M̄::T                 # Maximum reservoir capacities
    H̄::T                 # Maximal production
    Q̄::NTuple{S,T}       # Maximal discharge in each segment
    μ::NTuple{S,T}       # Marginal production equivalents in each segment
    S̱::T                 # Minimum spillage
    Rqh::Int             # Discharge flow time in whole hours
    Rqm::Int             # Discharge flow time in remaining minutes
    Rsh::Int             # Spillage flow time in whole hours
    Rsm::Int             # Spillage flow time in remaining minutes
    Q̃::T                 # Yearly mean flow of each plant
    V::T                 # Local inflow

    function (::Type{HydroPlantData})(M₀::AbstractFloat,M̄::AbstractFloat,H̄::AbstractFloat,Q̄::NTuple{S,<:AbstractFloat},μ::NTuple{S,<:AbstractFloat},S̱::AbstractFloat,Rgh::Integer,Rqm::Integer,Rsh::Integer,Rsm::Integer,Q̃::AbstractFloat,V::AbstractFloat) where S
        T = promote_type(typeof(M₀),typeof(M̄),typeof(H̄),eltype(Q̄),eltype(μ),typeof(S̱),typeof(Q̃),typeof(V),Float32)
        return new{T,S}(M₀,M̄,H̄,Q̄,μ,S̱,Rgh,Rqm,Rsh,Rsm,Q̃,V)
    end
end
Base.eltype(::HydroPlantData{T}) where T <: AbstractFloat = T

struct HydroPlantCollection{T <: AbstractFloat, S}
    # Plants
    # ========================================================
    plants::Vector{Plant}                   # All possible plant instances
    rivers::Dict{River,Vector{Plant}}       # Plants sorted according to river
    areas::Dict{Area,Vector{Plant}}         # Plants sorted according to price area
    # Parameters
    # ========================================================
    plantdata::Dict{Plant,HydroPlantData{T,S}}   # Data for each plant
    Qd::Dict{Plant,Vector{Plant}}                # All discharge outlets located downstream (including itself)
    Qu::Dict{Plant,Vector{Plant}}                # Discharge outlet(s) located directly upstream
    Sd::Dict{Plant,Vector{Plant}}                # Spillage outlets located downstream (including itself)
    Su::Dict{Plant,Vector{Plant}}                # Spillage outlet(s) located directly upstream

    function HydroPlantCollection(::Type{Segmenter{S}},
                                  plantnames::Vector{String},
                                  Qlinks::Vector{Int},
                                  Slinks::Vector{Int},
                                  H̄::AbstractVector,
                                  Q̄::AbstractVector,
                                  S̱::AbstractVector,
                                  M̄::AbstractVector,
                                  Q̃::AbstractVector,
                                  Rq::Vector{Int},
                                  Rs::Vector{Int},
                                  rivers::Vector{String},
                                  areas::Vector{Area}) where S
        T = promote_type(eltype(H̄),eltype(Q̄),eltype(S̱),eltype(M̄),eltype(Q̃),Float32)
        modeldata = new{T,S}(Vector{Plant}(),
                             Dict{River,Vector{Plant}}(),
                             Dict{Area,Vector{Plant}}(),
                             Dict{Plant,HydroPlantData{T,S}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),)
        define_model_parameters(modeldata,plantnames,Qlinks,Slinks,convert(Vector{T},H̄),convert(Vector{T},Q̄),convert(Vector{T},S̱),convert(Vector{T},M̄),convert(Vector{T},Q̃),Rq,Rs,rivers,areas)
        return modeldata
    end

    function HydroPlantCollection(::Type{T},::Type{Segmenter{S}},plantfilename::String) where {T <: AbstractFloat, S}
        modeldata = new{T,S}(Vector{Plant}(),
                             Dict{River,Vector{Plant}}(),
                             Dict{Area,Vector{Plant}}(),
                             Dict{Plant,HydroPlantData{T,S}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),
                             Dict{Plant,Vector{Plant}}(),)
        define_model_parameters(modeldata,plantfilename)
        return modeldata
    end
end
Base.eltype(::HydroPlantCollection{T}) where T <: AbstractFloat = T

function Base.show(io::IO, collection::HydroPlantCollection)
    if get(io, :multiline, false)
        print(io,"HydroPlantCollection")
    else
        println(io,"Collection of Hydropower Plants")
        if !isempty(collection.rivers)
            println(io,"Rivers:")
            for river in keys(collection.rivers)
                println(io,string(river))
            end
        end
    end
end

function HydroPlantCollection(plantnames::Vector{String},
                              Qlinks::Vector{Int},
                              Slinks::Vector{Int},
                              H̄::AbstractVector,
                              Q̄::AbstractVector,
                              S̱::AbstractVector,
                              M̄::AbstractVector,
                              Q̃::AbstractVector,
                              Rq::Vector{Int},
                              Rs::Vector{Int},
                              rivers::Vector{String},
                              areas::Vector{Area})
    return HydroPlantCollection(Segmenter{2},plantnames,Qlinks,Slinks,H̄,Q̄,S̱,M̄,Q̃,Rq,Rs,rivers,areas)
end

function HydroPlantCollection(plant_filename::String)
    return HydroPlantCollection(Float64,Segmenter{2},plant_filename)
end

Base.getindex(collection::HydroPlantCollection,plant::Plant) = collection.plantdata[plant]

function define_plants!(collection::HydroPlantCollection,plantnames::Vector{String})
    for plantname in plantnames
        push!(collection.plants,Plant(filter(x->!isspace(x),plantname)))
    end
end

function define_rivers!(collection::HydroPlantCollection,rivernames::Vector{String})
    for (p,rivername) in enumerate(rivernames)
        plant = collection.plants[p]
        river = River(filter(x->!isspace(x),rivername))
        if !haskey(collection.rivers,river)
            collection.rivers[river] = Plant[]
        end
        push!(collection.rivers[river],plant)
    end
end

function define_areas!(collection::HydroPlantCollection,areas::Vector{Area})
    for (p,area) in enumerate(areas)
        plant = collection.plants[p]
        if !haskey(collection.areas,area)
            collection.areas[area] = Plant[]
        end
        push!(collection.areas[area],plant)
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

function define_model_parameters(collection::HydroPlantCollection{T,S},
                                 plantnames::Vector{String},
                                 Qlinks::Vector{Int},
                                 Slinks::Vector{Int},
                                 H̄::Vector{T},
                                 Q̄::Vector{T},
                                 S̱::Vector{T},
                                 M̄::Vector{T},
                                 Q̃::Vector{T},
                                 Rq::Vector{Int},
                                 Rs::Vector{Int},
                                 rivers::Vector{String},
                                 areas::Vector{Area}) where {T <: AbstractFloat, S}
    Vsf = 0.2278           # Scale factor for local inflow (0.2278)
    δ = 0.363              # Initial reservoir content factor (0.363)
    M_end = 0.89           # Target water level as factor of M_0 (0.89)

    # Define available plants
    define_plants!(collection, plantnames)

    # Define sortings of plants
    define_rivers!(collection,rivers)
    define_areas!(collection,areas)

    for p in collection.plants
        collection.Qd[p] = Plant[]
        collection.Qu[p] = Plant[]
        collection.Sd[p] = Plant[]
        collection.Su[p] = Plant[]
    end

    # Define plant topologies
    links_as_plants(links) = Dict([(collection.plants[p],(l == 0 ? :NoLink : collection.plants[l])) for (p,l) in enumerate(links)])
    define_plant_topology!(links_as_plants(Qlinks), collection.Qd, collection.Qu)
    define_plant_topology!(links_as_plants(Slinks), collection.Sd, collection.Su)

    w = Dict(zip(collection.plants,Vsf*Q̃))

    for i in 1:length(plantnames)
        Q̄s,μs = segment(Segmenter{S},Q̄[i],H̄[i])
        p = collection.plants[i]
        V = calculate_inflow(p,w,collection.Qu[p])
        collection.plantdata[p] = HydroPlantData(δ*M̄[i],
                                                M̄[i],
                                                H̄[i],
                                                Q̄s,
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

function define_model_parameters(collection::HydroPlantCollection{T}, plantdata::Matrix) where T <: AbstractFloat
    @assert size(plantdata,2) == 12 "Invalid plant data format"

    define_model_parameters(collection,
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

function define_model_parameters(collection::HydroPlantCollection, plantfilename::String)
    plantdata = readcsv(plantfilename)
    define_model_parameters(collection,plantdata[2:end,:])
end

function plants_in_river(collection::HydroPlantCollection,river::River)
    if river == :All
        return collection.plants
    end
    if !haskey(collection.rivers,river)
        warn(string("Invalid river name: ", river))
        return Plant[]
    end
    return collection.rivers[river]
end

function plants_in_river(collection::HydroPlantCollection,rivers::Vector{River})
    plants = Plant[]
    for river in rivers
        append!(plants,plants_in_river(collection,river))
    end
    return plants
end

function plants_in_area(collection::HydroPlantCollection,area::Area)
    if area == 0
        return collection.plants
    end
    if !haskey(collection.areas,area)
        warn(string("Invalid area: ",area))
        return Plant[]
    end
    return collection.areas[area]
end

function plants_in_area(collection::HydroPlantCollection,areas::Vector{Area})
    plants = Plant[]
    for area in areas
        append!(plants,plants_in_area(collection,area))
    end
    return plants
end

function plants_in_areas_and_rivers(collection::HydroPlantCollection,areas::Vector{Area},rivers::Vector{River})
    return plants_in_river(collection,rivers) ∩ plants_in_area(collection,areas)
end
