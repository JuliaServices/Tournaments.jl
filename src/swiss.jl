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

When a rematch-free pairing exists, it builds one a pair at a time: it takes the
team with the fewest possible opponents, and pairs it with the first of them (in
standings order) that still leaves a rematch-free pairing for everyone else. So a
first-come choice can't strand the last two teams in a rematch. When no
rematch-free pairing exists, it keeps the standings order and pairs each team with
the next one it hasn't played, or the next one when it has played them all.
"""
function swiss_pairings(ordered::Vector{String},
                        played::Set{Tuple{String,String}})
    pairs = Tuple{String,String}[]
    remaining = copy(ordered)
    if _has_clean_pairing(remaining, played)
        while !isempty(remaining)
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
            for opponent_index in candidate_indexes
                rest = deleteat!(copy(remaining), sort!([chosen_index, opponent_index]))
                _has_clean_pairing(rest, played) || continue
                push!(pairs, (remaining[chosen_index], remaining[opponent_index]))
                remaining = rest
                break
            end
        end
        return pairs
    end

    while length(remaining) >= 2
        first_id = popfirst!(remaining)
        opponent_index = findfirst(id -> !((first_id, id) in played), remaining)
        opponent_index === nothing && (opponent_index = 1)
        push!(pairs, (first_id, remaining[opponent_index]))
        deleteat!(remaining, opponent_index)
    end
    return pairs
end

"""
Whether every team in `teams` can play one that it hasn't played: a perfect
matching in the graph of unplayed pairs. Edmonds' blossom algorithm finds a maximum
matching in O(n³) for `n` teams.
"""
function _has_clean_pairing(teams::Vector{String}, played::Set{Tuple{String,String}})::Bool
    n = length(teams)
    isodd(n) && return false
    # Most histories leave plenty of unplayed pairs, so pairing each team with the
    # next one it hasn't played usually covers everyone without the full search.
    unpaired = copy(teams)
    while !isempty(unpaired)
        team = popfirst!(unpaired)
        opponent = findfirst(id -> !((team, id) in played) && !((id, team) in played), unpaired)
        opponent === nothing && break
        deleteat!(unpaired, opponent)
        isempty(unpaired) && return true
    end
    unplayed = Bool[i != j && !((teams[i], teams[j]) in played) && !((teams[j], teams[i]) in played)
                    for i in 1:n, j in 1:n]
    mate = zeros(Int, n)       # each team's partner in the matching, 0 for none
    parent = zeros(Int, n)     # the search tree's links from odd to even teams
    base = collect(1:n)        # each team's blossom base
    queued = falses(n)
    in_blossom = falses(n)
    on_path = falses(n)
    queue = Int[]

    function common_base(a::Int, b::Int)::Int
        fill!(on_path, false)
        while true
            a = base[a]
            on_path[a] = true
            mate[a] == 0 && break
            a = parent[mate[a]]
        end
        while true
            b = base[b]
            on_path[b] && return b
            b = parent[mate[b]]
        end
    end

    function mark_blossom!(v::Int, blossom_base::Int, child::Int)
        while base[v] != blossom_base
            in_blossom[base[v]] = true
            in_blossom[base[mate[v]]] = true
            parent[v] = child
            child = mate[v]
            v = parent[mate[v]]
        end
        return nothing
    end

    # The end of an augmenting path from `root`, or 0 when there is none.
    function augmenting_path_end(root::Int)::Int
        fill!(queued, false)
        fill!(parent, 0)
        for i in 1:n
            base[i] = i
        end
        queued[root] = true
        empty!(queue)
        push!(queue, root)
        head = 1
        while head <= length(queue)
            v = queue[head]
            head += 1
            for to in 1:n
                unplayed[v, to] || continue
                (base[v] == base[to] || mate[v] == to) && continue
                if to == root || (mate[to] != 0 && parent[mate[to]] != 0)
                    blossom_base = common_base(v, to)
                    fill!(in_blossom, false)
                    mark_blossom!(v, blossom_base, to)
                    mark_blossom!(to, blossom_base, v)
                    for i in 1:n
                        in_blossom[base[i]] || continue
                        base[i] = blossom_base
                        queued[i] && continue
                        queued[i] = true
                        push!(queue, i)
                    end
                elseif parent[to] == 0
                    parent[to] = v
                    mate[to] == 0 && return to
                    queued[mate[to]] = true
                    push!(queue, mate[to])
                end
            end
        end
        return 0
    end

    for root in 1:n
        mate[root] == 0 || continue
        team = augmenting_path_end(root)
        # With no augmenting path now, later matchings never cover `root` either.
        team == 0 && return false
        while team != 0   # flip the path: its unmatched links become the matched ones
            partner = parent[team]
            next_team = mate[partner]
            mate[team] = partner
            mate[partner] = team
            team = next_team
        end
    end
    return true
end
