struct Horizon
    nhours::Integer   # Number of hours in horizon

    function Horizon(nhours::Integer)
        @assert mod(nhours,24) == 0 "Horizon should be an even number of days"
        return new(nhours)
    end
end

Day() = Horizon(24)
Days(ndays::Integer) = Horizon(ndays*24)
Week() = Horizon(168)
Weeks(nweeks::Integer) = Horizon(nweeks*168)

hours(horizon::Horizon) = horizon.nhours
days(horizon::Horizon) = div(horizon.nhours,24)
weeks(horizon::Horizon) = div(horizon.nhours,168)

function horizonstring(horizon::Horizon)
    remaindays = div(mod(hours(horizon),168),24)
    horizonstr = ""
    if weeks(horizon) > 0
        horizonstr *= string("(",weeks(horizon)," week")
        if weeks(horizon) > 1
            horizonstr *= "s"
        end
    end
    if remaindays > 0
        if weeks(horizon) > 0
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
