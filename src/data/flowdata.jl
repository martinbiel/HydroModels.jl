struct Inflows{P <: PlantCollection, T <: AbstractFloat}
    Q̃::Vector{T}

    function Inflows(plants::PlantCollection, Q̃::AbstractVector)
        nplants(plants) == length(Q̃) || error("Inconsistent number of power stations and inflows.")
        P = typeof(plants)
        T = eltype(Q̃)
        return new{P,T}(Q̃)
    end

    function Inflows(::Type{P}, Q̃::AbstractVector) where P <: PlantCollection
        nplants(P) == length(Q̃) || error("Inconsistent number of power stations and inflows.")
        T = eltype(Q̃)
        return new{P,T}(Q̃)
    end
end

function Inflows(plants::Vector{Plant}, Q̃::AbstractVector)
    return Inflows(PlantCollection(plants), Q̃)
end

function Base.zero(::Type{Inflows{P,T}}) where {P <: PlantCollection, T <: AbstractFloat}
    return Inflows(P,zeros(T,nplants(P)))
end

function Base.getindex(inflows::Inflows{P}, plant::Plant) where P <: PlantCollection
    idx = findfirst(p -> p == plant, plants(P))
    idx == nothing && throw(BoundsError(inflows, plant))
    return inflows.Q̃[idx]
end

plants(::Inflows{P}) where P <: PlantCollection = plants(P)
flows(inflows::Inflows) = inflows.Q̃
ninflows(::Inflows{P}) where P = nplants(P)

function Statistics.mean(inflow_collection::Vector{Inflows{P,T}}) where {P <: PlantCollection, T <: AbstractFloat}
    Q̃ = [mean([inflows.Q̃[p] for inflows in inflow_collection]) for p in 1:nplants(P)]
    return Inflows(P, Q̃)
end

function local_inflows(inflows::Inflows{P}, upstream_plants::Dict{Plant, Vector{Plant}}) where P <: PlantCollection
    local_inflows = [local_inflow(inflows, p, upstream_plants[p]) for p in plants(P)]
    return Inflows(P, local_inflows)
end

function local_inflow(inflows::Inflows, plant::Plant, upstream_plants::Vector{Plant})
    V = inflows[plant]
    if !isempty(upstream_plants)
        V -= sum(inflows[p] for p in upstream_plants)
    end
    return max(0, V)
end

struct InflowSequence{N, P <: PlantCollection, T <: AbstractFloat} <: AbstractVector{T}
    inflows::Vector{Inflows{P,T}}

    function InflowSequence(inflows::Vector{Inflows{P,T}}) where {P <: PlantCollection, T <: AbstractFloat}
        N = length(inflows)
        return new{N,P,T}(inflows)
    end

    function InflowSequence(plants::PlantCollection, inflows::AbstractMatrix)
        nplants(plants) == size(inflows,1) || error("Inconsistent number of power stations and inflows.")
        P = typeof(plants)
        N = size(inflows, 2)
        T = eltype(inflows)
        return new{N,P,T}([Inflows(plants, inflows[:,j]) for j in 1:size(inflows,2)])
    end

    function InflowSequence(::Type{P}, inflows::AbstractMatrix) where P <: PlantCollection
        nplants(P) == size(inflows,1) || error("Inconsistent number of power stations and inflows.")
        N = size(inflows, 2)
        T = eltype(inflows)
        return new{N,P,T}([Inflows(P, inflows[:,j]) for j in 1:size(inflows,2)])
    end
end

function InflowSequence(plants::Vector{Plant}, inflows::Matrix{T}) where T <: AbstractFloat
    return InflowSequence(PlantCollection(plants), inflows)
end

function Base.zero(::Type{InflowSequence{N,P,T}}) where {N, P <: PlantCollection, T <: AbstractFloat}
    return InflowSequence(P, zeros(T,nplants(P),N))
end
Base.iterate(inflowseq::InflowSequence) = iterate(inflowseq.inflows)
Base.length(inflowseq::InflowSequence{N}) where N = N
Base.size(inflowseq::InflowSequence) = size(inflowseq.inflows)
@inline function Base.getindex(inflowseq::InflowSequence, I...)
    @boundscheck checkbounds(inflowseq.inflows, I...)
    @inbounds return inflowseq.inflows[I...]
end
function Base.getindex(inflowseq::InflowSequence, horizon::Horizon)
    horizon <= HydroModels.horizon(inflowseq) || throw(BoundsError(inflowseq,horizon))
    return InflowSequence(inflowseq.inflows[1:ndays(horizon)])
end
@inline function Base.setindex!(inflowseq::InflowSequence, x, I...)
    @boundscheck checkbounds(inflowseq.inflows, I...)
    @inbounds inflowseq.inflows[I...] = x
end
Base.axes(inflowseq::InflowSequence) = axes(inflowseq.inflows)
Base.IndexStyle(::Type{<:InflowSequence}) = Base.IndexLinear()
horizon(inflowseq::InflowSequence{N}) where N = Days(N)

function Statistics.mean(sequences::Vector{InflowSequence{N,P,T}}) where {N, P <: PlantCollection, T <: AbstractFloat}
    inflow_sequence = [mean([sequence[i] for sequence in sequences]) for i in 1:N]
    return InflowSequence(inflow_sequence)
end

function local_inflow_sequence(sequence::InflowSequence{N,P}, upstream_plants::Dict{Plant, Vector{Plant}}) where {N, P <: PlantCollection}
    local_inflow_sequence = [local_inflows(sequence[d], upstream_plants) for d in 1:N]
    return InflowSequence(local_inflow_sequence)
end
