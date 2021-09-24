struct Resolution
    hours_in_period::Int

    function Resolution(hours_in_period::Integer)
        return new(hours_in_period)
    end
end

function num_periods(resolution::Resolution, horizon::Horizon)
    hours = num_hours(horizon)
    mod(hours, resolution.hours_in_period) == 0 || error("Time resolution with $(resolution.hours_in_period) not compatible with horizon of $hours hours.")
    return div(hours, resolution.hours_in_period)
end

function water_volume(resolution::Resolution, M::AbstractFloat)
    return M / resolution.hours_in_period
end

function marginal_production(resolution::Resolution, μ::AbstractFloat)
    return resolution.hours_in_period * μ
end

function water_flow_time(resolution::Resolution, R::Integer)
    minutes_in_periods = 60 * resolution.hours_in_period
    return floor(Int, R / minutes_in_periods)
end
function historic_flow(resolution, R::Integer)
    minutes_in_periods = 60 * resolution.hours_in_period
    return mod(R, minutes_in_periods)/minutes_in_periods
end
function overflow(resolution::Resolution, R::Integer)
    minutes_in_periods = 60 * resolution.hours_in_period
    return (1 - mod(R, minutes_in_periods)/minutes_in_periods)
end
