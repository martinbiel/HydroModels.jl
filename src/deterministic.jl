abstract type DeterministicHydroModel <: HydroModel end

function show(io::IO, model::DeterministicHydroModel)
    if get(io, :multiline, false)
        print(io,string("Deterministic Hydro Power Model : ",modelname(model),", including ",length(model.plants)," power stations, over a ",model.simtime," hour horizon ",horizonstring(model)))
    else
        println(io,string("Deterministic Hydro Power Model : ",modelname(model)))
        println(io,string("    including ",length(model.plants)," power stations"))
        println(io,string("    over a ",hours(model.horizon)," hour horizon ",horizonstring(model.horizon)))
        println(io,"")
        if status(model) == :Unplanned
            print(io,"Not yet planned")
        elseif status(model) == :Planned
            print(io,"Optimally planned")
        elseif status(model) == :Failed
            print(io,"Could not be planned")
        else
            error(string(model.status, " is not a valid model status"))
        end
    end
end
