"""
    bracket_order(size::Int) -> Vector{Int}

Classic bracket slot order for `size` (a power of two): consecutive pairs play each
other, and seed 1 can only meet seed 2 in the final.

```julia
julia> Tournaments.bracket_order(8)
8-element Vector{Int64}:
 1
 8
 4
 5
 2
 7
 3
 6
```
"""
function bracket_order(size::Int)
    seq = [1]
    while length(seq) < size
        n = 2 * length(seq)
        seq = reduce(vcat, ([x, n + 1 - x] for x in seq))
    end
    return seq
end

"""
    BracketFeeder

Where one side of a bracket game comes from: a seeded `team` (with its `seed`, 1
the best), or the winner or loser (`take`) of the game at `source_match_index` in
the plan's `matches`.
"""
Base.@kwdef struct BracketFeeder
    team::Union{String,Nothing} = nothing
    seed::Union{Int,Nothing} = nothing
    source_match_index::Union{Int,Nothing} = nothing
    take::String = "winner"
end

"""
    BracketMatch

One game in a [`BracketPlan`](@ref).

- `round_number`: rounds count from 1. A double elimination's losers rounds, and
  consolation and placement games, continue the count after the main rounds.
- `slot_number`: the game's place in its round. The main bracket uses 1 and up (an
  upper/lower split's lower half uses 101 and up). The losers bracket uses 101 and up,
  third place 2, fifth place 201 and up, ninth place 301 and up, and full-placement
  games 201 and up, a new hundred for each set.
- `field_ordinal`: the game's order among its round's games in its own set.
- `home` and `away`: [`BracketFeeder`](@ref)s.
"""
Base.@kwdef struct BracketMatch
    round_number::Int
    slot_number::Int
    field_ordinal::Int
    home::BracketFeeder
    away::BracketFeeder
end

"""
    BracketPlan

The games of a bracket (`matches`, each game after every game that feeds it), the
bracket's size (a power of two; with an upper/lower split, the sum of both halves'
sizes), and how many first-round byes it has (`bye_count`).
"""
Base.@kwdef struct BracketPlan
    matches::Vector{BracketMatch} = BracketMatch[]
    bracket_size::Int = 0
    bye_count::Int = 0
end

_direct_bracket_feeder(team::String, seed::Int) =
    BracketFeeder(; team, seed)

_source_bracket_feeder(index::Int, take::String = "winner") =
    BracketFeeder(; source_match_index = index, take)

const _OptionalBracketFeeder = Union{Nothing,BracketFeeder}

mutable struct _BracketBuilder
    matches::Vector{BracketMatch}
end

_BracketBuilder() = _BracketBuilder(BracketMatch[])

"""
    plan_bracket(seeds::Vector{String}; bracket_type = "single", split_mode = "single",
                 third_place = false, fifth_place = false, ninth_place = false,
                 full_placement = false) -> BracketPlan

Every game of an elimination bracket for `seeds`, best seed first. Top seeds get
the first-round byes when the count isn't a power of two.

- `bracket_type`: `"single"`, or `"double"` for a losers bracket and a grand final.
- `split_mode`: `"single"`, or `"upper_lower"` for two brackets, the top half of the
  seeds in one and the rest in the other (at least four teams).
- `third_place`: the semifinal losers play for third.
- `fifth_place`: the quarterfinal losers play their own bracket for fifth. It needs
  a full round of 8 teams.
- `ninth_place`: the same for the round of 16's losers, for ninth. It needs a full
  round of 16 teams.
- `full_placement`: every round's losers keep playing, so every team gets a final
  place.

A double elimination already places everyone it can, and so does full placement,
so neither combines with the other options; a third-place game needs four teams.

Throws an `ArgumentError` for fewer than two seeds, a repeated seed, an unknown
option or one of those combinations, an upper/lower split of fewer than four teams,
or a fifth- or ninth-place game without the full round it needs.
"""
function plan_bracket(seeds::Vector{String}; bracket_type::String = "single",
                      split_mode::String = "single", third_place::Bool = false,
                      fifth_place::Bool = false, ninth_place::Bool = false,
                      full_placement::Bool = false)
    length(seeds) >= 2 || throw(ArgumentError("At least two teams are required for a bracket"))
    bracket_type in ("single", "double") ||
        throw(ArgumentError("bracket_type must be single or double"))
    split_mode in ("single", "upper_lower") ||
        throw(ArgumentError("split_mode must be single or upper_lower"))
    allunique(seeds) || throw(ArgumentError("Each team can be seeded only once"))
    third_place && length(seeds) < 4 &&
        throw(ArgumentError("A third-place game needs at least four teams"))
    bracket_type == "double" && (third_place || fifth_place || ninth_place || full_placement ||
                                 split_mode != "single") &&
        throw(ArgumentError("Double elimination already places everyone it can - drop the consolation and split options"))
    full_placement && (third_place || fifth_place || ninth_place || split_mode != "single") &&
        throw(ArgumentError("Full placement already includes every consolation game - drop the other options"))
    builder = _BracketBuilder()
    seed_refs = BracketFeeder[]
    for (index, team) in enumerate(seeds)
        push!(seed_refs, _direct_bracket_feeder(team, index))
    end
    upper_tree = Int[]
    lower_tree = Int[]
    bracket_size = 0
    bye_count = 0
    if split_mode == "upper_lower"
        length(seeds) >= 4 || throw(ArgumentError("An upper/lower split needs at least four teams"))
        half = cld(length(seeds), 2)
        upper_tree, upper_byes = _build_bracket_tree!(builder, seed_refs[1:half])
        lower_tree, lower_byes = _build_bracket_tree!(builder, seed_refs[(half + 1):end], 100)
        upper_size = nextpow(2, max(2, half))
        lower_count = length(seeds) - half
        lower_size = nextpow(2, max(2, lower_count))
        bracket_size = upper_size + lower_size
        bye_count = upper_byes + lower_byes
    else
        upper_tree, bye_count = _build_bracket_tree!(builder, seed_refs)
        bracket_size = nextpow(2, length(seeds))
    end
    main_rounds = 0
    for index in upper_tree
        main_rounds = max(main_rounds, builder.matches[index].round_number)
    end
    for index in lower_tree
        main_rounds = max(main_rounds, builder.matches[index].round_number)
    end

    if bracket_type == "double"
        next_round = Ref(main_rounds)
        winners_rounds = _bracket_rounds(builder, upper_tree)
        carriers = _OptionalBracketFeeder[]
        for winners in winners_rounds
            drops = _loser_bracket_feeders(winners)
            if isempty(carriers)
                carriers = drops
                continue
            end
            while length(carriers) > length(drops)
                carriers = _play_bracket_round!(builder, carriers, next_round)
            end
            merged = _OptionalBracketFeeder[]
            for index in 1:max(length(carriers), length(drops))
                index <= length(drops) && push!(merged, drops[index])
                index <= length(carriers) && push!(merged, carriers[index])
            end
            carriers = _play_bracket_round!(builder, merged, next_round)
        end
        while length(carriers) > 1
            carriers = _play_bracket_round!(builder, carriers, next_round)
        end
        if !isempty(upper_tree) && length(carriers) == 1
            carrier = carriers[1]
            carrier === nothing && error("double-elimination carrier cannot be empty")
            _add_bracket_match!(builder, next_round[] + 1, 1, 1,
                _source_bracket_feeder(upper_tree[end]), carrier)
        end
    end

    if third_place && !isempty(upper_tree)
        final_index = upper_tree[end]
        final = builder.matches[final_index]
        semifinal_indices = Int[]
        final.home.source_match_index === nothing ||
            push!(semifinal_indices, final.home.source_match_index)
        final.away.source_match_index === nothing ||
            push!(semifinal_indices, final.away.source_match_index)
        if length(semifinal_indices) == 2
            _add_bracket_match!(builder, final.round_number, 2, 2,
                _source_bracket_feeder(semifinal_indices[1], "loser"),
                _source_bracket_feeder(semifinal_indices[2], "loser"))
        end
    end

    fifth_place && _add_bracket_consolation!(
        builder, upper_tree, main_rounds, 4, 200, "fifth-place")
    ninth_place && _add_bracket_consolation!(
        builder, upper_tree, main_rounds, 8, 300, "ninth-place")

    if full_placement
        base_counter = Ref(100)
        offset_counter = Ref(main_rounds)
        _add_bracket_placement_ladder!(
            builder, upper_tree, base_counter, offset_counter)
    end

    return BracketPlan(; matches = builder.matches, bracket_size, bye_count)
end

function _add_bracket_match!(builder::_BracketBuilder, round_number::Int,
                             slot_number::Int, field_ordinal::Int,
                             home::BracketFeeder, away::BracketFeeder)::Int
    push!(builder.matches, BracketMatch(;
        round_number, slot_number, field_ordinal, home, away))
    return length(builder.matches)
end

function _bracket_rounds(builder::_BracketBuilder,
                         indices::Vector{Int})::Vector{Vector{Int}}
    grouped = Dict{Int,Vector{Int}}()
    for index in indices
        round_number = builder.matches[index].round_number
        push!(get!(grouped, round_number, Int[]), index)
    end
    result = Vector{Vector{Int}}()
    for round_number in sort!(collect(keys(grouped)))
        round = grouped[round_number]
        # Match counts are small; an explicit insertion sort avoids a captured
        # `by` closure in this trim-sensitive graph builder.
        for index in 2:length(round)
            cursor = index
            while cursor > 1 &&
                  builder.matches[round[cursor - 1]].slot_number >
                  builder.matches[round[cursor]].slot_number
                round[cursor - 1], round[cursor] = round[cursor], round[cursor - 1]
                cursor -= 1
            end
        end
        push!(result, round)
    end
    return result
end

function _present_bracket_feeder(home::_OptionalBracketFeeder,
                                 away::_OptionalBracketFeeder)::BracketFeeder
    home === nothing || return home
    away === nothing && error("bracket feeder pair is empty")
    return away
end

function _build_bracket_tree!(builder::_BracketBuilder,
                              tree_seeds::Vector{BracketFeeder},
                              slot_base::Int = 0,
                              round_offset::Int = 0)::Tuple{Vector{Int},Int}
    count = length(tree_seeds)
    size = count <= 1 ? 2 : nextpow(2, count)
    order = bracket_order(size)
    feeders = _OptionalBracketFeeder[]
    for index in 1:size
        push!(feeders, order[index] <= count ? tree_seeds[order[index]] : nothing)
    end
    tree_match_indices = Int[]
    round_number = round_offset
    while length(feeders) > 1
        round_number += 1
        next = _OptionalBracketFeeder[]
        field_ordinal = 0
        for index in 1:2:length(feeders)
            home = feeders[index]
            away = feeders[index + 1]
            if home === nothing && away === nothing
                push!(next, nothing)
                continue
            elseif home === nothing || away === nothing
                push!(next, _present_bracket_feeder(home, away))
                continue
            end
            field_ordinal += 1
            match_index = _add_bracket_match!(
                builder, round_number, slot_base + field_ordinal,
                field_ordinal, home, away)
            push!(tree_match_indices, match_index)
            push!(next, _source_bracket_feeder(match_index))
        end
        feeders = next
    end
    return tree_match_indices, size - count
end

function _play_bracket_round!(builder::_BracketBuilder,
                              feeders::Vector{_OptionalBracketFeeder},
                              next_round::Base.RefValue{Int},
                              slot_base::Int = 100)::Vector{_OptionalBracketFeeder}
    length(feeders) <= 1 && return feeders
    isodd(length(feeders)) && push!(feeders, nothing)
    next_round[] += 1
    out = _OptionalBracketFeeder[]
    field_ordinal = 0
    for index in 1:2:length(feeders)
        home = feeders[index]
        away = feeders[index + 1]
        if home === nothing && away === nothing
            push!(out, nothing)
            continue
        elseif home === nothing || away === nothing
            push!(out, _present_bracket_feeder(home, away))
            continue
        end
        field_ordinal += 1
        match_index = _add_bracket_match!(
            builder, next_round[], slot_base + field_ordinal,
            field_ordinal, home, away)
        push!(out, _source_bracket_feeder(match_index))
    end
    return out
end

function _loser_bracket_feeders(indices::Vector{Int})::Vector{_OptionalBracketFeeder}
    feeders = _OptionalBracketFeeder[]
    for index in Iterators.reverse(indices)
        push!(feeders, _source_bracket_feeder(index, "loser"))
    end
    return feeders
end

function _add_bracket_consolation!(builder::_BracketBuilder,
                                   upper_tree::Vector{Int}, main_rounds::Int,
                                   match_count::Int, slot_base::Int, label::String)
    # Fifth place takes the quarterfinal losers and ninth place the round-of-16
    # losers: the round `log2(match_count)` rounds before the final. Byes can
    # make the first round just as wide, but its losers finish lower.
    rounds = _bracket_rounds(builder, upper_tree)
    position = length(rounds) - trailing_zeros(match_count)
    (position >= 1 && length(rounds[position]) == match_count) || throw(ArgumentError(
        "A $(label) game needs a full round of $(match_count * 2) teams - this bracket doesn't have one"))
    feeders = BracketFeeder[]
    for index in rounds[position]
        push!(feeders, _source_bracket_feeder(index, "loser"))
    end
    _build_bracket_tree!(builder, feeders, slot_base, main_rounds)
    return nothing
end

function _add_bracket_placement_ladder!(builder::_BracketBuilder,
                                        tree::Vector{Int},
                                        base_counter::Base.RefValue{Int},
                                        offset_counter::Base.RefValue{Int})
    for round in _bracket_rounds(builder, tree)
        length(round) >= 2 || continue
        feeders = BracketFeeder[]
        for index in round
            push!(feeders, _source_bracket_feeder(index, "loser"))
        end
        base_counter[] += 100
        sub, _ = _build_bracket_tree!(
            builder, feeders, base_counter[], offset_counter[])
        isempty(sub) && continue
        for index in sub
            offset_counter[] = max(
                offset_counter[], builder.matches[index].round_number)
        end
        _add_bracket_placement_ladder!(builder, sub, base_counter, offset_counter)
    end
    return nothing
end

"""
    BracketGame

When and where one [`BracketPlan`](@ref) game plays: the game's index in the plan's
`matches` (`plan_index`), its start and end (`nothing` for an untimed bracket), its
field, and its time slot, counted from 1 (games in one slot play together).
"""
Base.@kwdef struct BracketGame
    plan_index::Int
    starts_at::Union{DateTime,Nothing} = nothing
    ends_at::Union{DateTime,Nothing} = nothing
    field::Union{String,Nothing} = nothing
    slot::Int = 0
end

"""
    BracketSchedule

A [`BracketPlan`](@ref) laid into time slots: one [`BracketGame`](@ref) per plan
game, in plan order, how many slots it takes (`time_slot_count`), and when the
last slot ends (`scheduled_ends_at`, `nothing` for an untimed bracket).
"""
Base.@kwdef struct BracketSchedule
    games::Vector{BracketGame} = BracketGame[]
    time_slot_count::Int = 0
    scheduled_ends_at::Union{DateTime,Nothing} = nothing
end

"""
    schedule_bracket(plan::BracketPlan, starts_at::Union{DateTime,Nothing},
                     round_length_minutes::Int, fields::Vector{String};
                     held::HeldTime = HeldTime(), rest_slots::Int = 0) -> BracketSchedule

Lay a bracket plan into back-to-back time slots of `round_length_minutes`,
starting at `starts_at`, with at most one game per field in each slot.

Each game takes the earliest slot that leaves `rest_slots` empty slots after the
games feeding it and still has a free field. Every team in a game reaches it from
one of those feeders or from its seed, so each team rests at least `rest_slots`
slots between its games. Games heading the longest chains of games still to play
claim slots first, so a losers bracket and placement games play alongside the
main bracket instead of waiting for its final. A timed bracket skips the fields
that `held` books in each slot. With `starts_at = nothing` the bracket is untimed:
games get slots and fields but no times.

An empty plan or no fields gives an empty schedule. A timed bracket needs a
positive `round_length_minutes`; a negative `rest_slots` or a repeated field id is
an `ArgumentError`.
"""
function schedule_bracket(plan::BracketPlan, starts_at::Union{DateTime,Nothing},
                          round_length_minutes::Int, fields::Vector{String};
                          held::HeldTime = HeldTime(), rest_slots::Int = 0)
    starts_at === nothing || round_length_minutes > 0 ||
        throw(ArgumentError("A timed bracket needs a positive round length"))
    rest_slots >= 0 || throw(ArgumentError("rest_slots cannot be negative"))
    allunique(fields) || throw(ArgumentError("Field ids must be unique"))
    isempty(plan.matches) && return BracketSchedule()
    isempty(fields) && return BracketSchedule()
    matches = plan.matches
    round_length = Minute(round_length_minutes)
    # A game only feeds games added after it, so one backward pass finds the
    # longest chain of games each one starts.
    chain = ones(Int, length(matches))
    for index in reverse(eachindex(matches)), side in (matches[index].home, matches[index].away)
        source = side.source_match_index
        source === nothing || (chain[source] = max(chain[source], chain[index] + 1))
    end
    order = sort(collect(eachindex(matches)); by = index ->
        (-chain[index], matches[index].round_number, matches[index].slot_number))
    slot_of = zeros(Int, length(matches))
    field_of = zeros(Int, length(matches))
    games_in_slot = Int[]
    free_in_slot = Vector{Int}[]   # each slot's free fields, as indexes into `fields`
    for index in order
        slot = 1
        for side in (matches[index].home, matches[index].away)
            source = side.source_match_index
            source === nothing || (slot = max(slot, slot_of[source] + 1 + rest_slots))
        end
        while true
            while slot > length(games_in_slot)
                push!(free_in_slot, _free_bracket_fields(
                    held, fields, starts_at, length(games_in_slot), round_length))
                push!(games_in_slot, 0)
            end
            games_in_slot[slot] < length(free_in_slot[slot]) && break
            slot += 1
        end
        games_in_slot[slot] += 1
        slot_of[index] = slot
        # Rotate the first field between time slots, so a bracket with one
        # game per slot still spreads its games across the fields.
        free = free_in_slot[slot]
        field_of[index] = free[mod1(slot - 1 + games_in_slot[slot], length(free))]
    end
    scheduled = BracketGame[]
    for index in eachindex(matches)
        game_starts_at = starts_at === nothing ? nothing :
            starts_at + (slot_of[index] - 1) * round_length
        push!(scheduled, BracketGame(;
            plan_index = index,
            starts_at = game_starts_at,
            ends_at = game_starts_at === nothing ? nothing : game_starts_at + round_length,
            field = fields[field_of[index]],
            slot = slot_of[index],
        ))
    end
    slot_count = length(games_in_slot)
    return BracketSchedule(;
        games = scheduled,
        time_slot_count = slot_count,
        scheduled_ends_at = starts_at === nothing ? nothing :
            starts_at + slot_count * round_length,
    )
end

"""
Indexes of the `fields` that `held` leaves free in bracket slot `slot_index`
(counted from 0 at `starts_at`). Every field is free in an untimed bracket.
"""
function _free_bracket_fields(held::HeldTime, fields::Vector{String},
        starts_at::Union{DateTime,Nothing}, slot_index::Int, round_length::Minute)
    starts_at === nothing && return collect(eachindex(fields))
    slot_start = starts_at + slot_index * round_length
    return Int[index for index in eachindex(fields)
        if field_free(held, fields[index], slot_start, slot_start + round_length)]
end
