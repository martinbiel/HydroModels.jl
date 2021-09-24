struct Segmenter{S} end
function segment(::Segmenter{2}, Q̄::AbstractFloat, H̄::AbstractFloat)
    Q̄s = (0.75*Q̄, 0.25*Q̄)
    μ = H̄/(Q̄s[1] + 0.95*Q̄s[2])
    μs = (μ, 0.95*μ)
    return Q̄s, μs
end
function segment_percentage(::Segmenter{2}, segment::Integer)
    if segment == 1
        return 0.75
    elseif segment == 2
        return 0.25
    else
        error("Segment out of bounds.")
    end
end
