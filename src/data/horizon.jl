struct Horizon
    nhours::Integer   # Number of hours in horizon

    function Horizon(nhours::Integer)
        @assert mod(nhours,24) == 0 "Horizon should be an even number of days"
        return new(nhours)
    end
end

Base.:(==)(h1::Horizon,h2::Horizon) = h1.nhours == h2.nhours
Base.:(<=)(h1::Horizon,h2::Horizon) = h1.nhours <= h2.nhours
Base.:(>=)(h1::Horizon,h2::Horizon) = h1.nhours >= h2.nhours

Day() = Horizon(24)
Days(ndays::Integer) = Horizon(ndays*24)
Week() = Horizon(168)
Weeks(nweeks::Integer) = Horizon(nweeks*168)

nhours(horizon::Horizon) = horizon.nhours
ndays(horizon::Horizon) = div(horizon.nhours,24)
nweeks(horizon::Horizon) = div(horizon.nhours,168)

function horizonstring(horizon::Horizon)
    remaindays = div(mod(nhours(horizon),168),24)
    horizonstr = ""
    weeks = nweeks(horizon)
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
