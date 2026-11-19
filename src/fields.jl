"""
    HeldTime

Field time already taken: field id => the `(starts_at, ends_at)` spans booked on
it, such as games another schedule holds. A field is busy during a span from its
start up to, but not including, its end.
"""
const HeldTime = Dict{String,Vector{Tuple{DateTime,DateTime}}}

"""
    field_free(held::HeldTime, field::String, starts_at::DateTime, ends_at::DateTime) -> Bool

Whether `field` is free from `starts_at` to `ends_at`: no span `held` books on it
overlaps that time. Spans that only touch, one ending as the other starts, don't
overlap.
"""
function field_free(held::HeldTime, field_id::String, starts_at::DateTime, ends_at::DateTime)
    spans = get(held, field_id, nothing)
    spans === nothing && return true
    return !any(span -> span[1] < ends_at && starts_at < span[2], spans)
end

"""
    assign_fields(games, fields::Vector{String}; held::HeldTime = HeldTime()) -> Vector{String}

Choose a field for every game so each team's games spread evenly across `fields`.
Each game needs `home`, `away`, `starts_at`, and `ends_at` properties (a
`NamedTuple` works), and the result holds one field per game, in order.

Games that start together share the same times, so choosing fields among them
never changes when anyone plays. The search trades the fields of two games that
start together, or moves a game to a field left open at its start time. It scores
a schedule by the sum of squared per-team field counts, which is smallest when
every team splits its games evenly, plus the squared game totals per field, so
open fields take turns sitting idle.

Keeping only trades that improve the score stalls short of even in common shapes,
such as eight teams on two fields with a rest rule. So the search first runs
simulated annealing: it tries random trades and sometimes keeps a worse one, less
often as it goes, which lets it climb out of dead ends. A fixed seed makes the
result repeatable. A final pass then keeps every trade that improves team balance,
or field totals at equal team balance, until none does.

Within one game of an even split is not always possible. With four teams on two
fields, both games of a round share one start time, so some team always plays
three games on one field and none on the other. In a few tight shapes with three
or more fields, such as ten teams on five fields, the search can also end one game
outside that range even though an even split exists.

A field that `held` books during a game's time never gets that game. At every start
time, there must be at least as many free fields as games starting then. Games that
overlap must start at the same time: the search only trades fields among games that
start together, so a game still running when a later one starts is an
`ArgumentError`, as are repeated field ids.
"""
function assign_fields(games::AbstractVector, field_ids::Vector{String};
                       held::HeldTime = HeldTime())
    allunique(field_ids) || throw(ArgumentError("Field ids must be unique"))
    _check_no_staggered_overlap(games)
    field_count = length(field_ids)
    team_index = Dict{String,Int}()
    start_index = Dict{DateTime,Int}()
    for game in games
        get!(team_index, game.home, length(team_index) + 1)
        get!(team_index, game.away, length(team_index) + 1)
        get!(start_index, game.starts_at, length(start_index) + 1)
    end
    blocked = falses(field_count, length(start_index))
    for game in games, field in 1:field_count
        field_free(held, field_ids[field], game.starts_at, game.ends_at) ||
            (blocked[field, start_index[game.starts_at]] = true)
    end
    tally = _FieldTally(
        Int[team_index[game.home] for game in games],
        Int[team_index[game.away] for game in games],
        zeros(Int, field_count, length(start_index)),
        zeros(Int, length(team_index), field_count),
        zeros(Int, field_count))
    for (index, game) in enumerate(games)
        start = start_index[game.starts_at]
        field = 1
        while field <= field_count && (tally.games[field, start] != 0 || blocked[field, start])
            field += 1
        end
        field <= field_count || throw(ArgumentError(
            "More games start at one time than there are free fields"))
        tally.games[field, start] = index
        tally.counts[tally.home[index], field] += 1
        tally.counts[tally.away[index], field] += 1
        tally.totals[field] += 1
    end
    if field_count > 1 && !isempty(games)
        random = 0x9e3779b97f4a7c15
        # A fixed step budget from one seed; tight shapes with three or more
        # fields can end one game outside the even band. More seeds, keeping the
        # best result, would close that gap.
        steps = 100 * length(games) + 20_000
        for step in 1:steps
            random = _xorshift(random)
            start = Int(random % UInt64(length(start_index))) + 1
            random = _xorshift(random)
            a = Int(random % UInt64(field_count)) + 1
            random = _xorshift(random)
            b = Int(random % UInt64(field_count - 1)) + 1
            b >= a && (b += 1)
            tally.games[a, start] == 0 && tally.games[b, start] == 0 && continue
            (blocked[a, start] || blocked[b, start]) && continue
            change = sum(_field_trade_change(tally, start, a, b))
            # The smallest possible worsening is kept about 60% of the time
            # at first and almost never by the last step.
            temperature = 2.0 * 0.005^(step / steps)
            random = _xorshift(random)
            change <= 0 || (random >> 11) * 0x1p-53 < exp(-change / temperature) || continue
            _trade_fields!(tally, start, a, b)
        end
        improved = true
        while improved
            improved = false
            for start in axes(tally.games, 2), a in 1:field_count, b in (a + 1):field_count
                tally.games[a, start] == 0 && tally.games[b, start] == 0 && continue
                (blocked[a, start] || blocked[b, start]) && continue
                _field_trade_change(tally, start, a, b) < (0, 0) || continue
                _trade_fields!(tally, start, a, b)
                improved = true
            end
        end
    end
    assigned = Vector{String}(undef, length(games))
    for start in axes(tally.games, 2), field in 1:field_count
        index = tally.games[field, start]
        index == 0 && continue
        assigned[index] = field_ids[field]
    end
    return assigned
end

"Throw unless every game still running at a later game's start began at that same time."
function _check_no_staggered_overlap(games::AbstractVector)
    latest_end = Dict{DateTime,DateTime}()   # start => the latest end of games starting then
    for game in games
        latest_end[game.starts_at] = max(get(latest_end, game.starts_at, game.ends_at), game.ends_at)
    end
    starts = sort!(collect(keys(latest_end)))
    for index in 1:(length(starts) - 1)
        latest_end[starts[index]] <= starts[index + 1] || throw(ArgumentError(
            "Games that overlap must start at the same time"))
    end
    return nothing
end

"Field use while `assign_fields` searches; teams and fields are numbered from 1."
struct _FieldTally
    home::Vector{Int}       # each game's home team
    away::Vector{Int}       # each game's away team
    games::Matrix{Int}      # games[field, start]: the game there, or 0 when open
    counts::Matrix{Int}     # counts[team, field]: that team's games on that field
    totals::Vector{Int}     # totals[field]: games on that field
end

"One step of the xorshift random number generator, so a fixed seed repeats exactly."
_xorshift(x::UInt64) = (x ⊻= x << 13; x ⊻= x >> 7; x ⊻ (x << 17))

"""
Half the change in the sum of squared per-team field counts, and in the sum of
squared field totals, when the games on fields `a` and `b` at `start` trade
fields (an open field simply receives the other game). Moving one game of a
team from a field it has played `c1` times to one it has played `c2` times
changes that team's sum by 2(c2 - c1 + 1).
"""
function _field_trade_change(tally::_FieldTally, start::Int, a::Int, b::Int)
    team = 0
    for (from, to) in ((a, b), (b, a))
        game = tally.games[from, start]
        game == 0 && continue
        for side in (tally.home[game], tally.away[game])
            team += tally.counts[side, to] - tally.counts[side, from] + 1
        end
    end
    # Two occupied fields keep their totals; one game moving shifts one game.
    total = tally.games[a, start] == 0 ? tally.totals[a] - tally.totals[b] + 1 :
            tally.games[b, start] == 0 ? tally.totals[b] - tally.totals[a] + 1 : 0
    return team, total
end

"Trade the games on fields `a` and `b` at `start` and update the tallies."
function _trade_fields!(tally::_FieldTally, start::Int, a::Int, b::Int)
    for (from, to) in ((a, b), (b, a))
        game = tally.games[from, start]
        game == 0 && continue
        for side in (tally.home[game], tally.away[game])
            tally.counts[side, from] -= 1
            tally.counts[side, to] += 1
        end
        tally.totals[from] -= 1
        tally.totals[to] += 1
    end
    tally.games[a, start], tally.games[b, start] = tally.games[b, start], tally.games[a, start]
    return nothing
end
