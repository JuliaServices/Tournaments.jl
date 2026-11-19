"""
    swiss_round(standings::Vector{String}, round_number::Int,
                played::Set{Tuple{String,String}}, prior_byes::Set{String})
        -> (pairs::Vector{Tuple{String,String}}, bye::Union{String,Nothing})

Pair one Swiss round. `standings` lists the teams best first, `played` holds every
`(team, opponent)` pair that has already met (put both orders in), and
`prior_byes` the teams that have already had a bye.

- With an odd count, the lowest-ranked team without a bye sits out (`bye`); when
  everyone has had one, the last team sits out.
- Round 1 pairs the split halves: 1 plays N/2+1, 2 plays N/2+2, and so on.
- Later rounds use [`swiss_pairings`](@ref).
"""
function swiss_round(standings::Vector{String}, round_number::Int,
                     played::Set{Tuple{String,String}}, prior_byes::Set{String})
    ordered = copy(standings)
    bye = nothing
    if isodd(length(ordered))
        pick = findlast(id -> !(id in prior_byes), ordered)
        pick === nothing && (pick = length(ordered))
        bye = ordered[pick]
        deleteat!(ordered, pick)
    end
    pairs = Tuple{String,String}[]
    if round_number == 1
        half = length(ordered) ÷ 2
        for index in 1:half
            push!(pairs, (ordered[index], ordered[index + half]))
        end
    else
        pairs = swiss_pairings(ordered, played)
    end
    return pairs, bye
end

"""
    swiss_pairings(standings::Vector{String}, played::Set{Tuple{String,String}})
        -> Vector{Tuple{String,String}}

Pair an even number of teams, listed best first, so that no pair has met before
(`played` holds every `(team, opponent)` pair that has, in both orders).

It searches the rematch-free pairings first, taking the team with the fewest
possible opponents at each step, so a first-come choice can't strand the last two
teams in a rematch while a clean pairing exists. When none exists, it keeps the
standings order and pairs each team with the next one it hasn't played, or the next
one when it has played them all.

Some histories make proving that no clean pairing exists take exponential time,
such as two odd-sized groups that have played every cross-group pair. So the search
stops after 100,000 steps and uses that fallback. Real fields need far fewer: the
hardest Swiss round in the test corpus takes 15.
"""
function swiss_pairings(ordered::Vector{String},
                        played::Set{Tuple{String,String}})
    pairs = Tuple{String,String}[]

    # A first-available opponent can strand the final two teams in a rematch
    # even when another complete pairing exists. Search the no-rematch graph
    # first, choosing the most constrained team at each step. Swiss fields are
    # small and the graph is dense in the rounds where this path is useful.
    _pair_swiss_without_rematches!(pairs, copy(ordered), played, Ref(_SWISS_SEARCH_STEPS)) &&
        return pairs

    # A rematch-free round is impossible. Preserve standings order and avoid a
    # rematch for each team when a local alternative remains.
    empty!(pairs)
    remaining = copy(ordered)
    while length(remaining) >= 2
        first_id = popfirst!(remaining)
        opponent_index = findfirst(id -> !((first_id, id) in played), remaining)
        opponent_index === nothing && (opponent_index = 1)
        push!(pairs, (first_id, remaining[opponent_index]))
        deleteat!(remaining, opponent_index)
    end
    return pairs
end

# ponytail: a step budget instead of a matching feasibility check (Edmonds' blossom);
# add that check if large Swiss fields with dense histories become common.
const _SWISS_SEARCH_STEPS = 100_000

function _pair_swiss_without_rematches!(
    pairs::Vector{Tuple{String,String}},
    remaining::Vector{String},
    played::Set{Tuple{String,String}},
    steps::Base.RefValue{Int},
)::Bool
    isempty(remaining) && return true
    steps[] -= 1
    steps[] < 0 && return false
    chosen_index = 1
    candidate_indexes = Int[]
    smallest_count = typemax(Int)
    for index in eachindex(remaining)
        candidates = Int[]
        for other in eachindex(remaining)
            other == index && continue
            (remaining[index], remaining[other]) in played && continue
            push!(candidates, other)
        end
        if length(candidates) < smallest_count
            chosen_index = index
            candidate_indexes = candidates
            smallest_count = length(candidates)
        end
    end
    isempty(candidate_indexes) && return false

    first_id = remaining[chosen_index]
    for opponent_index in candidate_indexes
        opponent_id = remaining[opponent_index]
        next_remaining = String[]
        sizehint!(next_remaining, length(remaining) - 2)
        for index in eachindex(remaining)
            (index == chosen_index || index == opponent_index) && continue
            push!(next_remaining, remaining[index])
        end
        push!(pairs, (first_id, opponent_id))
        _pair_swiss_without_rematches!(pairs, next_remaining, played, steps) && return true
        pop!(pairs)
    end
    return false
end
