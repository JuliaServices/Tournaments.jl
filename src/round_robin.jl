"""
    round_robin(teams::Vector{String}) -> Vector{Vector{Tuple{String,String}}}

Every team plays every other team once, in rounds where nobody plays twice. Each
pair is `(home, away)`.

It uses the circle method: seat `i` plays seat `n - i + 1`, and after each round
every seat but the first moves one along. With an odd count an empty last seat
gives byes, so `n` teams play `n - 1` rounds when `n` is even and `n` rounds when it
is odd.

The team that has hosted fewer games so far hosts. On a tie the first-seat team
hosts, and in other seats the left team hosts when the round and seat numbers add
up to an odd number. With that tie-break, after every round each team is within
one game of an even home and away split, and a team with an even number of games
ends the cycle exactly even.

```julia
julia> Tournaments.round_robin(["a", "b", "c", "d"])
3-element Vector{Vector{Tuple{String, String}}}:
 [("a", "d"), ("b", "c")]
 [("c", "a"), ("d", "b")]
 [("a", "b"), ("c", "d")]
```
"""
function round_robin(team_ids::Vector{String})
    ids = Vector{Union{String,Nothing}}(team_ids)
    if isodd(length(ids))
        push!(ids, nothing)
    end

    rounds = Vector{Vector{Tuple{String,String}}}()
    n = length(ids)
    half = n ÷ 2
    hosted = Dict{String,Int}(id => 0 for id in team_ids)   # home games minus away games
    for round_number in 1:(n - 1)
        pairs = Tuple{String,String}[]
        for i in 1:half
            a = ids[i]
            b = ids[n - i + 1]
            (a === nothing || b === nothing) && continue
            a_hosts = hosted[a] == hosted[b] ? (i == 1 || isodd(round_number + i)) :
                hosted[a] < hosted[b]
            home, away = a_hosts ? (a, b) : (b, a)
            hosted[home] += 1
            hosted[away] -= 1
            push!(pairs, (home, away))
        end
        push!(rounds, pairs)
        rotated = Union{Nothing,String}[ids[1], ids[end]]
        append!(rotated, @view ids[2:end-1])
        ids = rotated
    end
    return rounds
end

"""
    season_rounds(teams::Vector{String}, games_per_team::Int)
        -> (rounds::Vector{Vector{Tuple{String,String}}}, total_games::Int)

Rounds for a season where each team plays `games_per_team` games: full
[`round_robin`](@ref) cycles, home and away swapped in every other cycle, cut off
when the season has `ceil(n * games_per_team / 2)` games (`total_games`).

When the last round holds fewer games than a full round, it takes the teams still
short of their games, in round order from where the cycle stopped, so teams that
have not met yet in the cycle play first. When the target makes the total odd, one
short team plays a team that already has its games. Those games come out of round
order, so the team that has hosted less so far hosts.

A negative `games_per_team`, or a positive one with fewer than two teams, is an
`ArgumentError`.
"""
function season_rounds(team_ids::Vector{String}, games_per_team::Int)
    games_per_team >= 0 || throw(ArgumentError("games_per_team cannot be negative"))
    games_per_team == 0 || length(team_ids) >= 2 ||
        throw(ArgumentError("A season needs at least two teams"))
    n = length(team_ids)
    total_games = ceil(Int, n * games_per_team / 2)
    base = round_robin(team_ids)
    rounds = Vector{Vector{Tuple{String,String}}}()
    played = Dict{String,Int}(id => 0 for id in team_ids)
    hosted = Dict{String,Int}(id => 0 for id in team_ids)   # home games minus away games
    games = 0
    cycle = 0
    while games < total_games
        for (index, r) in enumerate(base)
            pairs = isodd(cycle) ? Tuple{String,String}[(b, a) for (a, b) in r] : copy(r)
            if games + length(pairs) > total_games
                pairs = _final_season_round(base, index, isodd(cycle), played, hosted,
                                            games_per_team, total_games - games)
            end
            isempty(pairs) && continue
            push!(rounds, pairs)
            for (home, away) in pairs
                played[home] += 1
                played[away] += 1
                hosted[home] += 1
                hosted[away] -= 1
            end
            games += length(pairs)
            games >= total_games && break
        end
        cycle += 1
        cycle > games_per_team + 2 && break   # safety; cannot happen with n ≥ 2
    end
    return rounds, total_games
end

"""
The season's last round when it holds fewer games than a full round: `count`
games for the teams still short of `games_per_team`. Pairs are taken in round
order from round `start` of the cycle, so teams that have not met yet in this
cycle play first. When the target makes the total odd, one short team plays a
team that already has its games. These games come out of round order, so the
team that has hosted less so far (`hosted`: home minus away games) hosts.
"""
function _final_season_round(base::Vector{Vector{Tuple{String,String}}}, start::Int,
                             reversed::Bool, played::Dict{String,Int},
                             hosted::Dict{String,Int}, games_per_team::Int, count::Int)
    pairs = Tuple{String,String}[]
    used = Set{String}()
    for short_teams in (2, 1), offset in 0:(length(base) - 1)
        for (a, b) in base[mod1(start + offset, length(base))]
            length(pairs) == count && return pairs
            (a in used || b in used) && continue
            (played[a] < games_per_team) + (played[b] < games_per_team) >= short_teams || continue
            home, away = reversed ? (b, a) : (a, b)
            push!(pairs, hosted[home] > hosted[away] ? (away, home) : (home, away))
            push!(used, a)
            push!(used, b)
        end
    end
    return pairs
end
