struct Horizon
    num_hours::Integer   # Number of hours in horizon

    function Horizon(num_hours::Integer)
        @assert mod(num_hours,24) == 0 "Horizon should be an even number of days"
        return new(num_hours)
    end
end

Base.:(==)(h1::Horizon,h2::Horizon) = h1.num_hours == h2.num_hours
Base.:(<=)(h1::Horizon,h2::Horizon) = h1.num_hours <= h2.num_hours
Base.:(>=)(h1::Horizon,h2::Horizon) = h1.num_hours >= h2.num_hours

Day() = Horizon(24)
Days(num_days::Integer) = Horizon(num_days*24)
Week() = Horizon(168)
Weeks(num_weeks::Integer) = Horizon(num_weeks*168)
Year() = Horizon(8760)
Years(num_years::Integer) = Horizon(num_years*8760)


num_hours(horizon::Horizon) = horizon.num_hours
num_days(horizon::Horizon) = div(horizon.num_hours, 24)
num_weeks(horizon::Horizon) = div(horizon.num_hours, 168)

function horizonstring(horizon::Horizon)
    remaindays = div(mod(num_hours(horizon),168),24)
    horizonstr = ""
    weeks = num_weeks(horizon)
    if weeks > 0
        horizonstr *= string("(",weeks," week")
        if weeks > 1
            horizonstr *= "s"
        end
    end
    if remaindays > 0
        if weeks > 0
            horizonstr *= string(", ",remaindays," day")
        else
            horizonstr *= string("(",remaindays," day")
        end
        if remaindays > 1
            horizonstr *= "s)"
        else
            horizonstr *= ")"
        end
    else
        horizonstr *= ")"
    end
    return horizonstr
end
