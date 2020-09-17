struct NoScaling end
scale(::NoScaling, value) = value

struct MinMaxScaling{T <: AbstractFloat}
    min::T
    max::T

    function MinMaxScaling(min::T, max::T) where T <: AbstractFloat
        return new{T}(min, max)
    end
end

function scale(scaling::MinMaxScaling, value::AbstractFloat)
    return (value - scaling.min) / (scaling.max - scaling.min)
end

struct Forecaster{T, I, M, S}
    initializer::I
    network::M
    scaling::S

    function Forecaster(model_type, initializer, network, scaling; init_from::String = "none", from::String = "none")
        if init_from != "none"
            @load init_from weights
            Flux.loadparams!(initializer, weights)
        end
        if from != "none"
            @load from weights
            Flux.loadparams!(network, weights)
        end
        I = typeof(initializer)
        M = typeof(network)
        S = typeof(scaling)
        return new{model_type, I, M, S}(initializer, network, scaling)
    end
end

function PriceForecaster(initializer, network; init_from::String = "none", from::String = "none")
    if from != "none"
        @load from min max
        scaling = MinMaxScaling(min, max)
        return Forecaster(:price, initializer, network, scaling; init_from = init_from, from = from)
    end
    return Forecaster(:price, initializer, network, NoScaling(); init_from = init_from, from = from)
end

function FlowForecaster(initializer, network; init_from::String = "none", from::String = "none")
    if from != "none"
        @load from min max weights
        Flux.loadparams!(network, weights)
        scaling = MinMaxScaling(min, max)
        return Forecaster(:flow, initializer, network, scaling; init_from = init_from, from = from)
    end
    return Forecaster(:flow, initializer, network, NoScaling(); init_from = init_from, from = from)
end

function forecast(forecaster::Forecaster{:price}, starting_price::T, month::Integer) where T <: AbstractFloat
    Flux.reset!(forecaster.network)
    λ = Vector{T}(undef, 24)
    λ[1] = starting_price
    for i = 2:24
        input = vcat(scale(forecaster.scaling, λ[i-1]), i/24, month/12)
        λ[i] = forecaster.network(input)[1]
    end
    return λ
end

function forecast(forecaster::Forecaster{:price}, month::Integer)
    Flux.reset!(forecaster.network)
    λ = Vector{Float64}(undef, 24)
    λ[1] = forecaster.initializer(vcat(randn(), month/12))[1]
    for i = 2:24
        input = vcat(scale(forecaster.scaling, λ[i-1]), i/24, month/12)
        λ[i] = forecaster.network(input)[1]
    end
    return λ
end

function forecast(forecaster::Forecaster{:flow}, starting_flows::Vector{T}, week::Int, plants::Vector{Plant}) where T <: AbstractFloat
    Flux.reset!(forecaster.network)
    flows = Matrix{T}(undef, length(starting_flows), 7)
    flows[:,1] = starting_flows
    for i = 2:7
        input = vcat([scale(forecaster.scaling, f) for f in flows[:,i-1]], i/7, week/52)
        flows[:,i] = forecaster.network(input)[:]
    end
    return flows
end

function forecast(forecaster::Forecaster{:flow}, week::Int)
    Flux.reset!(forecaster.network)
    nplants = size(forecaster.initializer.layers[1].W, 2) - 1
    flows = Matrix{Float64}(undef, nplants, 7)
    flows[:,1] = forecaster.initializer(vcat(randn(nplants), week/52))[:]
    for i = 2:7
        input = vcat([scale(forecaster.scaling, f) for f in flows[:,i-1]], i/7, week/52)
        flows[:,i] = forecaster.network(input)[:]
    end
    return flows
end
