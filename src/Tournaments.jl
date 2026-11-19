"""
    Tournaments

Pairings, draws, and brackets for leagues and tournaments, over plain data: team ids
are strings, times are `Dates.DateTime`s, and fields are strings.

- [`round_robin`](@ref) and [`season_rounds`](@ref): everyone plays everyone, or a
  set number of games each, with home and away games split evenly.
- [`swiss_round`](@ref) and [`swiss_pairings`](@ref): Swiss rounds that avoid
  rematches when they can, with byes.
- [`snake_pools`](@ref): snake seeding into pools.
- [`bracket_order`](@ref), [`plan_bracket`](@ref), and [`schedule_bracket`](@ref):
  single and double elimination, consolation games, full placement, and an upper
  and lower split, then time slots and fields for every game.
- [`assign_fields`](@ref): fields for games already given start times, so each
  team plays evenly across the fields.

Nothing is exported; call these through the module, as in `Tournaments.round_robin`.
Every function is deterministic: the same input gives the same output.
"""
module Tournaments

using Dates

include("round_robin.jl")
include("swiss.jl")
include("pools.jl")
include("fields.jl")
include("brackets.jl")

end # module Tournaments
