struct Segmenter{S} end
function segment(::Type{Segmenter{2}},Q̅::AbstractFloat,H̅::AbstractFloat)
    Q̅s = (0.75*Q̅,0.25*Q̅)
    μ1 = H̅/(Q̅s[1] + 0.95*Q̅s[2])
    μs = (μ1, 0.95*μ1)
    return Q̅s,μs
end
