# Tournaments.jl

[![CI](https://github.com/JuliaServices/Tournaments.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaServices/Tournaments.jl/actions/workflows/ci.yml)

Pairings, draws, and brackets for leagues and tournaments, over plain data: team ids
are strings, times are `Dates.DateTime`s, and fields are strings. It has no
dependencies beyond Julia's standard library, and every function compiles with
`juliac --trim=safe`.

- **Round robins and seasons:** everyone plays everyone, or a set number of games
  each, with home and away games split evenly.
- **Swiss rounds** that avoid rematches when they can, with byes.
- **Snake seeding** into pools.
- **Brackets:** single and double elimination, third-, fifth-, and ninth-place
  games, full placement, and an upper and lower split. Then time slots and fields
  for every game, with rest between a team's games.
- **Fields:** for games already given start times, choose fields so each team plays
  evenly across them.

Every function is deterministic: the same input gives the same output.

The code was moved out of a production league scheduler. Its tests include a
golden corpus of about 4,300 cases recorded from that scheduler, which this package
must reproduce exactly.

## Install

It isn't registered yet, so add it by URL:

```julia
using Pkg
Pkg.add(url = "https://github.com/JuliaServices/Tournaments.jl")
```

## Example: a round robin for six teams on three fields

```julia
using Dates
import Tournaments as T

teams = ["Aces", "Blaze", "Comets", "Dragons", "Eagles", "Falcons"]
rounds = T.round_robin(teams)            # 5 rounds of 3 games

# One hour per round, all of a round's games at once.
games = [(; home, away, starts_at = DateTime(2026, 6, 6, 8 + round),
            ends_at = DateTime(2026, 6, 6, 9 + round))
         for (round, pairs) in enumerate(rounds) for (home, away) in pairs]
fields = T.assign_fields(games, ["Field 1", "Field 2", "Field 3"])

for (game, field) in zip(games, fields)
    println(Dates.format(game.starts_at, "HH:MM"), "  ", rpad(field, 8), game.home, " vs ", game.away)
end
```

```
09:00  Field 2 Aces vs Falcons
09:00  Field 3 Blaze vs Eagles
09:00  Field 1 Dragons vs Comets
10:00  Field 1 Eagles vs Aces
⋮
13:00  Field 2 Eagles vs Dragons
```

Each team plays five games, at most two of them on any one field.

## Functions

Nothing is exported; call them through the module.

| Function | What it gives |
|---|---|
| `round_robin(teams)` | Rounds of `(home, away)` pairs, by the circle method. |
| `season_rounds(teams, games_per_team)` | Rounds for a season of that many games each, and the total game count. |
| `swiss_round(standings, round_number, played, prior_byes)` | One Swiss round's pairs and its bye. |
| `swiss_pairings(standings, played)` | A rematch-free pairing when one exists. |
| `snake_pools(count, pool_count)` | Each seed's pool, dealt in a snake. |
| `bracket_order(size)` | Seed order for a bracket of `size` (1 meets 2 only in the final). |
| `plan_bracket(seeds; bracket_type, split_mode, third_place, fifth_place, ninth_place, full_placement)` | A `BracketPlan`: every game, fed by a seed or by the winner or loser of an earlier game. |
| `schedule_bracket(plan, starts_at, round_length_minutes, fields; held, rest_slots)` | A `BracketSchedule`: each game's time slot and field. |
| `assign_fields(games, fields; held)` | A field for each game, spreading every team's games evenly. |
| `field_free(held, field, starts_at, ends_at)` | Whether held field time leaves a field free. |

`held` is a `Tournaments.HeldTime`, a `Dict` from field to the `(starts_at, ends_at)`
spans already booked on it. Each function's docstring has the details, including
the shapes where an even field split isn't possible.

## Tests

```julia
using Pkg
Pkg.test("Tournaments")
```

`test/trim/main.jl` is the program CI compiles with `juliac --trim=safe` and runs.

## License

MIT
