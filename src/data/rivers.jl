struct PlantCollection{Plants}
    function PlantCollection(plants::Vector{Symbol})
        return new{ntuple(p -> plants[p], length(plants))}()
    end
end

nplants(::Type{PlantCollection{Plants}}) where Plants = length(Plants)
nplants(::PlantCollection{Plants}) where Plants = length(Plants)
plants(::Type{PlantCollection{Plants}}) where Plants = [Plants...]
plants(::PlantCollection{Plants}) where Plants = [Plants...]

const Skellefteälven = PlantCollection([:Rebnis,
                                        :Sadva,
                                        :Bergnas,
                                        :Slagnas,
                                        :Bastusel,
                                        :Grytfors,
                                        :Gallejaur,
                                        :Vargfors,
                                        :Rengard,
                                        :Batfors,
                                        :Finnfors,
                                        :Granfors,
                                        :Krangfors,
                                        :Selsfors,
                                        :Kvistforsen])
