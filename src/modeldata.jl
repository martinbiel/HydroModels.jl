River = String
Area = Int
Plant = Symbol

mutable struct HydroModelData
    # Plants
    # ========================================================
    plants       # All possible plant instances
    rivers       # Plants sorted according to river
    areas        # Plants sorted according to price area
    # Parameters
    # ========================================================
    M₀    # Initial reservoir contents
    M̅     # Maximum reservoir capacities
    H̅     # Maximal production
    Q̅     # Maximal discharge in each segment
    μ     # Marginal production equivalents in each segment
    S̱     # Minimum spillage for each plant
    Rqh   # Discharge flow time in whole hours
    Rqm   # Discharge flow time in remaining minutes
    Rsh   # Spillage flow time in whole hours
    Rsm   # Spillage flow time in remaining minutes
    Qd    # All discharge outlets located downstream (including itself)
    Qu    # Discharge outlet(s) located directly upstream
    Sd    # Spillage outlets located downstream (including itself)
    Su    # Spillage outlet(s) located directly upstream
    Qavg  # Yearly mean flow of each plant
    V     # Local inflow
    λ     # Expected price each hour
    λ_f   # Expected future price

    function HydroModelData()
        modeldata = new()
        return modeldata
    end
end

function define_plants!(modeldata::HydroModelData,plantnames::Vector{String})
    modeldata.plants = Vector{Plant}()
    for plantname in plantnames
        push!(modeldata.plants,Plant(strip(plantname)))
    end
end

function define_rivers!(modeldata::HydroModelData,rivers::Vector{River})
    modeldata.rivers = Dict{River,Vector{Plant}}()
    for (p,river) in enumerate(rivers)
        plant = modeldata.plants[p]
        if !haskey(modeldata.rivers,river)
            modeldata.rivers[river] = Plant[]
        end
        push!(modeldata.rivers[river],plant)
    end
end

function define_areas!(modeldata::HydroModelData,areas::Vector{Area})
    modeldata.areas = Dict{Area,Vector{Plant}}()
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
                                upstream_plants)
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

function calculate_marginal_equivalents(Q̅,H̅)
    Q̅s = [0.75*Q̅ 0.25*Q̅]
    μs = zeros(2)
    for i = 1:length(Q̅s)
       μs[1] = H̅/(Q̅s[1] + 0.95*Q̅s[2])
       μs[2] = 0.95*μs[1]
    end
    return Q̅s,μs
end

function calculate_inflow(plant,w,upstream_plants)
    V = w[plant]
    if !isempty(upstream_plants)
        V -= sum(w[p] for p in upstream_plants)
    end
    return V
end

function define_model_parameters(modeldata::HydroModelData,
                                 plantnames::Vector{String},
                                 Qlinks,
                                 Slinks,
                                 H̅,
                                 Q̅,
                                 S̱,
                                 M̅,
                                 yearlymeanflows,
                                 Rq,
                                 Rs,
                                 rivers::Vector{River},
                                 areas::Vector{Area},
                                 pricedata)

    @assert size(pricedata,1) == 24 || size(pricedata,1) == 168 "Prices should be defined daily or weekly"

    Vsf = 0.2278           # Scale factor for local inflow (0.2278)
    δ = 0.363              # Initial reservoir content factor (0.363)
    M_end = 0.89           # Target water level as factor of M_0 (0.89)

    # Define available plants
    define_plants!(modeldata, plantnames)

    # Define sortings of plants
    define_rivers!(modeldata,rivers)
    define_areas!(modeldata,areas)

    # Load/initialize modeldata parameters
    modeldata.M₀ = Dict(zip(modeldata.plants,δ*M̅))
    modeldata.M̅ = Dict(zip(modeldata.plants,M̅))
    modeldata.H̅ = Dict(zip(modeldata.plants,H̅))
    modeldata.Q̅ = Dict{Tuple{Plant,Int64},Float64}()
    modeldata.μ = Dict{Tuple{Plant,Int64},Float64}()
    modeldata.S̱ = Dict(zip(modeldata.plants,S̱))
    modeldata.Rqh = Dict{Plant,Float64}()
    modeldata.Rqm = Dict{Plant,Float64}()
    modeldata.Rsh = Dict{Plant,Float64}()
    modeldata.Rsm = Dict{Plant,Float64}()
    modeldata.Qd = Dict{Plant,Vector{Plant}}()
    modeldata.Qu = Dict{Plant,Vector{Plant}}()
    modeldata.Sd = Dict{Plant,Vector{Plant}}()
    modeldata.Su = Dict{Plant,Vector{Plant}}()
    for p in modeldata.plants
        modeldata.Qd[p] = Plant[]
        modeldata.Qu[p] = Plant[]
        modeldata.Sd[p] = Plant[]
        modeldata.Su[p] = Plant[]
    end
    modeldata.Qavg = Dict(zip(modeldata.plants,Vsf*yearlymeanflows))
    modeldata.V = Dict{Plant,Float64}()


    links_as_plants(links) = Dict([(modeldata.plants[p],(l == 0 ? :NoLink : modeldata.plants[l])) for (p,l) in enumerate(links)])

    define_plant_topology!(links_as_plants(Qlinks), modeldata.Qd, modeldata.Qu)
    define_plant_topology!(links_as_plants(Slinks), modeldata.Sd, modeldata.Su)

    for i in 1:length(plantnames)
        p = modeldata.plants[i]
        Q̅s,μs = calculate_marginal_equivalents(Q̅[i],H̅[i])
        modeldata.Q̅[(p,1)] = Q̅s[1]
        modeldata.Q̅[(p,2)] = Q̅s[2]
        modeldata.μ[(p,1)] = μs[1]
        modeldata.μ[(p,2)] = μs[2]
        modeldata.Rqh[p] = floor(Int64,Rq[i]/60);
        modeldata.Rqm[p] = mod(Rq[i],60);
        modeldata.Rsh[p] = floor(Int64,Rs[i]/60);
        modeldata.Rsm[p] = mod(Rs[i],60);
        modeldata.V[p] = calculate_inflow(p,modeldata.Qavg,modeldata.Qu[p])
    end

    modeldata.λ = pricedata
    modeldata.λ_f = mean(pricedata)
end

function define_model_parameters(modeldata::HydroModelData, plantdata::Matrix, pricedata::Matrix)
    @assert size(plantdata,2) == 12 "Invalid plant data format"

    define_model_parameters(modeldata,
                            Vector{String}(plantdata[:,1]),
                            plantdata[:,2],
                            plantdata[:,3],
                            plantdata[:,4],
                            plantdata[:,5],
                            plantdata[:,6],
                            plantdata[:,7],
                            plantdata[:,8],
                            plantdata[:,9],
                            plantdata[:,10],
                            Vector{River}(plantdata[:,11]),
                            Vector{Area}(plantdata[:,12]),
                            pricedata)
end

function define_model_parameters(modeldata::HydroModelData, plantfilename::String, pricefilename::String)
    plantdata = readcsv(plantfilename)
    pricedata = readcsv(pricefilename)
    define_model_parameters(modeldata,plantdata[2:end,:],pricedata[2:end,:])
end

function HydroModelData(plantfilename::String, pricefilename::String)
    modeldata = HydroModelData()
    define_model_parameters(modeldata,plantfilename,pricefilename)
    return modeldata
end

function plants_in_river(modeldata::HydroModelData,river::River)
    if river == "All"
        return modeldata.plants
    end
    if !haskey(modeldata.rivers,river)
        warn(string("Invalid river name: ",river))
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
