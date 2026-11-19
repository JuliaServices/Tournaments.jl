using Test, Dates
import Tournaments as T

@testset "Tournaments" begin
    @testset "round-robin pairings (circle method)" begin
        ids = ["a", "b", "c", "d"]
        rounds = T.round_robin(ids)
        @test length(rounds) == 3
        @test all(length(r) == 2 for r in rounds)
        pairs = Set(Set([h, a]) for r in rounds for (h, a) in r)
        @test length(pairs) == 6                     # every matchup exactly once
        @test all(h != a for r in rounds for (h, a) in r)
        for r in rounds                              # nobody plays twice per round
            seen = [t for (h, a) in r for t in (h, a)]
            @test allunique(seen)
        end
        odd = T.round_robin(["a", "b", "c"])          # odd count: byes, still 3 rounds
        @test length(odd) == 3
        @test all(length(r) == 1 for r in odd)
        @test isempty(only(T.round_robin(["a"])))
    end

    @testset "round robins and seasons split home and away games evenly" begin
        for n in 2:24
            team_ids = ["t$(i)" for i in 1:n]
            rounds = T.round_robin(team_ids)
            @test sum(length, rounds) == n * (n - 1) ÷ 2
            @test length(Set(Set(pair) for r in rounds for pair in r)) == n * (n - 1) ÷ 2
            @test all(allunique(t for pair in r for t in pair) for r in rounds)
            # Within one game of an even split at every point of the cycle.
            balance = Dict(id => 0 for id in team_ids)
            worst = 0
            for r in rounds
                for (home, away) in r
                    balance[home] += 1
                    balance[away] -= 1
                end
                worst = max(worst, maximum(abs, values(balance)))
            end
            @test worst <= 1
            @test maximum(abs, values(balance)) == (iseven(n) ? 1 : 0)
            # A season stops partway through a cycle or repeats it with venues
            # swapped; the swapped cycle can put an even count two games off.
            # Every pair still meets as often as any other, give or take one.
            season_worst = 0
            meetings_spread = 0
            for games_per_team in 1:(2n - 2)
                season = Dict(id => 0 for id in team_ids)
                meetings = Dict{Set{String},Int}()
                for r in first(T.season_rounds(team_ids, games_per_team)), (home, away) in r
                    season[home] += 1
                    season[away] -= 1
                    meetings[Set((home, away))] = get(meetings, Set((home, away)), 0) + 1
                end
                season_worst = max(season_worst, maximum(abs, values(season)))
                low, high = extrema(get(meetings, Set((a, b)), 0)
                                    for a in team_ids for b in team_ids if a < b)
                meetings_spread = max(meetings_spread, high - low)
            end
            @test season_worst <= (iseven(n) ? 2 : 1)
            @test meetings_spread <= 1
        end
    end

    @testset "season round sequence hits the games target" begin
        rounds, total = T.season_rounds(["a", "b", "c", "d"], 3)
        @test total == 6                              # 4 teams × 3 games / 2
        @test sum(length, rounds) == total
        counts = Dict{String,Int}()
        for r in rounds, (h, a) in r
            counts[h] = get(counts, h, 0) + 1
            counts[a] = get(counts, a, 0) + 1
        end
        @test all(v == 3 for v in values(counts))

        # With an odd team count the last round is partial; its games go to
        # the teams still short, so nobody plays two games more than another.
        for n in 3:2:21, games_per_team in 1:12
            team_ids = ["t$(i)" for i in 1:n]
            rounds, total = T.season_rounds(team_ids, games_per_team)
            counts = Dict(id => 0 for id in team_ids)
            for r in rounds, (h, a) in r
                counts[h] += 1
                counts[a] += 1
            end
            @test sum(length, rounds) == total
            @test minimum(values(counts)) == games_per_team
            @test count(>(games_per_team), values(counts)) == (isodd(n * games_per_team) ? 1 : 0)
        end
        # A target no schedule can meet.
        @test_throws ArgumentError T.season_rounds(["a", "b"], -1)
        @test_throws ArgumentError T.season_rounds(["a"], 2)
        @test T.season_rounds(["a"], 0) == (Vector{Tuple{String,String}}[], 0)
    end

    @testset "Swiss pairing avoids avoidable rematches" begin
        # Greedily pairing A-B strands C-D in a rematch. A complete clean
        # pairing still exists (A-C/B-D or A-D/B-C).
        played = Set([("c", "d"), ("d", "c")])
        pairings = T.swiss_pairings(["a", "b", "c", "d"], played)
        @test length(pairings) == 2
        @test all(!((home, away) in played) for (home, away) in pairings)
        @test Set(Iterators.flatten(pairings)) == Set(["a", "b", "c", "d"])
        # With every pair already met, it keeps the standings order.
        everyone = Set((a, b) for a in ("a", "b", "c", "d") for b in ("a", "b", "c", "d") if a != b)
        @test T.swiss_pairings(["a", "b", "c", "d"], everyone) == [("a", "b"), ("c", "d")]

        # Two groups of 21 that have played every cross-group pair must each pair
        # inside the group, and an odd group can't, so no clean pairing exists.
        # Searching every pairing would take hours; the step budget ends it at once.
        a = ["a$(i)" for i in 1:21]
        b = ["b$(i)" for i in 1:21]
        cross = Set{Tuple{String,String}}()
        for x in a, y in b
            push!(cross, (x, y))
            push!(cross, (y, x))
        end
        pairs = T.swiss_pairings(vcat(a, b), cross)
        @test count(in(cross), pairs) == 1
        @test sort!(collect(Iterators.flatten(pairs))) == sort!(vcat(a, b))
    end

    @testset "Swiss rounds: the split first round and byes" begin
        pairs, bye = T.swiss_round(["a", "b", "c", "d", "e", "f"], 1, Set{Tuple{String,String}}(), Set{String}())
        @test pairs == [("a", "d"), ("b", "e"), ("c", "f")]
        @test bye === nothing
        # The lowest-ranked team without a bye sits out.
        pairs, bye = T.swiss_round(["a", "b", "c", "d", "e"], 2, Set{Tuple{String,String}}(), Set(["e"]))
        @test bye == "d"
        @test Set(Iterators.flatten(pairs)) == Set(["a", "b", "c", "e"])
        # When everyone has had one, the last team sits out again.
        _, bye = T.swiss_round(["a", "b", "c"], 3, Set{Tuple{String,String}}(), Set(["a", "b", "c"]))
        @test bye == "c"
    end

    @testset "snake seeding into pools" begin
        @test T.snake_pools(8, 3) == [1, 2, 3, 3, 2, 1, 1, 2]
        @test T.snake_pools(4, 1) == [1, 1, 1, 1]
        @test isempty(T.snake_pools(0, 2))
        for count in 1:30, pools in 1:6
            assigned = T.snake_pools(count, pools)
            @test all(1 .<= assigned .<= pools)
            sizes = [Base.count(==(pool), assigned) for pool in 1:pools]
            @test maximum(sizes) - minimum(sizes) <= 1
        end
        @test_throws ArgumentError T.snake_pools(4, 0)
    end

    @testset "bracket seed order" begin
        @test T.bracket_order(2) == [1, 2]
        @test T.bracket_order(4) == [1, 4, 2, 3]
        @test T.bracket_order(8) == [1, 8, 4, 5, 2, 7, 3, 6]
        # 1 and 2 land in opposite halves at every size
        for size in (4, 8, 16, 32)
            order = T.bracket_order(size)
            half = size ÷ 2
            @test (findfirst(==(1), order) <= half) != (findfirst(==(2), order) <= half)
        end
    end

    @testset "bracket plans" begin
        # Six teams: the top two seeds get byes, and every game's feeders come first.
        plan = T.plan_bracket(["t$(i)" for i in 1:6])
        @test (plan.bracket_size, plan.bye_count, length(plan.matches)) == (8, 2, 5)
        @test all(side.source_match_index === nothing || side.source_match_index < index
                  for (index, match) in enumerate(plan.matches) for side in (match.home, match.away))
        @test Set(side.team for match in plan.matches for side in (match.home, match.away)
                  if side.team !== nothing) == Set("t$(i)" for i in 1:6)
        # Double elimination: everyone but the champion loses twice.
        double = T.plan_bracket(["t$(i)" for i in 1:8]; bracket_type = "double")
        @test length(double.matches) == 2 * 8 - 2
        third = T.plan_bracket(["t$(i)" for i in 1:8]; third_place = true)
        @test count(match -> match.slot_number == 2 && match.home.take == "loser", third.matches) == 1
        @test_throws ArgumentError T.plan_bracket(["a"])
        @test_throws ArgumentError T.plan_bracket(["a", "b"]; bracket_type = "triple")
        @test_throws ArgumentError T.plan_bracket(["a", "b", "c"]; split_mode = "upper_lower")
        @test_throws ArgumentError T.plan_bracket(["t$(i)" for i in 1:6]; fifth_place = true)
        # A repeated seed, or options that would place the same teams twice.
        @test_throws ArgumentError T.plan_bracket(["a", "b", "a", "c"])
        @test_throws ArgumentError T.plan_bracket(["a", "b", "c"]; third_place = true)
        sixteen = ["t$(i)" for i in 1:16]   # enough for each consolation game on its own
        for options in ((; third_place = true), (; fifth_place = true), (; ninth_place = true),
                        (; full_placement = true), (; split_mode = "upper_lower"))
            @test_throws ArgumentError T.plan_bracket(sixteen; bracket_type = "double", options...)
        end
        for options in ((; third_place = true), (; fifth_place = true), (; ninth_place = true),
                        (; split_mode = "upper_lower"))
            @test_throws ArgumentError T.plan_bracket(sixteen; full_placement = true, options...)
        end
    end

    @testset "consolation games take the losers of the round they name" begin
        # Byes can make the first round as wide as the quarterfinals (12 teams)
        # or the round of 16 (24 teams); those first-round losers finish lower.
        for (n, option, games, before_final) in (
                (12, :fifth_place, 4, 2), (20, :fifth_place, 4, 2), (8, :fifth_place, 4, 2),
                (24, :ninth_place, 8, 3), (16, :ninth_place, 8, 3))
            plan = T.plan_bracket(["t$(i)" for i in 1:n]; (option => true,)...)
            final_round = maximum(m.round_number for m in plan.matches if m.slot_number == 1)
            sources = [f.source_match_index for m in plan.matches
                       if m.slot_number > 200 for f in (m.home, m.away) if f.take == "loser"]
            @test length(sources) == games
            @test all(i -> plan.matches[i].round_number == final_round - before_final, sources)
        end
    end

    @testset "bracket games start once the games feeding them end" begin
        fields(count) = ["f$(i)" for i in 1:count]
        start = DateTime(2026, 6, 6, 9)
        # The losers bracket plays alongside the winners bracket, so a double
        # elimination takes as many one-hour slots as its longest chain of games.
        for (team_count, field_count, slots) in ((4, 2, 4), (8, 4, 6), (16, 8, 8))
            plan = T.plan_bracket(["t$(i)" for i in 1:team_count]; bracket_type = "double")
            schedule = T.schedule_bracket(plan, start, 60, fields(field_count))
            @test schedule.time_slot_count == slots
            @test schedule.scheduled_ends_at == start + Hour(slots)
        end
        # Every team in a game comes from a game feeding it or from its seed, so
        # waiting `rest_slots` after each feeder rests every team that long.
        for options in ((; bracket_type = "double"), (; full_placement = true),
                        (; third_place = true, fifth_place = true)),
                team_count in 8:3:26, field_count in 1:5, rest_slots in 0:2
            plan = T.plan_bracket(["t$(i)" for i in 1:team_count]; options...)
            games = T.schedule_bracket(plan, start, 60, fields(field_count); rest_slots).games
            @test [game.plan_index for game in games] == collect(eachindex(plan.matches))
            @test allunique((game.starts_at, game.field) for game in games)
            @test all(games[index].starts_at >= games[side.source_match_index].ends_at + Hour(rest_slots)
                      for (index, match) in enumerate(plan.matches)
                      for side in (match.home, match.away) if side.source_match_index !== nothing)
        end
        # A field another schedule holds is skipped while held; untimed brackets
        # get slots and fields but no times; no fields means no schedule.
        plan = T.plan_bracket(["t$(i)" for i in 1:4])
        held = T.HeldTime("f1" => [(start, start + Hour(1))])
        games = T.schedule_bracket(plan, start, 60, fields(2); held).games
        @test all(game.field != "f1" for game in games if game.starts_at == start)
        untimed = T.schedule_bracket(plan, nothing, 60, fields(2))
        @test all(game.starts_at === nothing && game.field !== nothing for game in untimed.games)
        @test untimed.scheduled_ends_at === nothing
        @test isempty(T.schedule_bracket(plan, start, 60, String[]).games)
        # Each game's slot, timed or not.
        plan = T.plan_bracket(["t$(i)" for i in 1:8]; third_place = true)
        timed = T.schedule_bracket(plan, start, 60, fields(2))
        untimed = T.schedule_bracket(plan, nothing, 60, fields(2))
        @test all(game.starts_at == start + Hour(game.slot - 1) for game in timed.games)
        @test [game.slot for game in untimed.games] == [game.slot for game in timed.games]
        @test maximum(game.slot for game in untimed.games) == untimed.time_slot_count
        # Zero-length rounds, negative rest, and a repeated field would double-book.
        @test_throws ArgumentError T.schedule_bracket(plan, start, 0, fields(2))
        @test_throws ArgumentError T.schedule_bracket(plan, start, 60, fields(2); rest_slots = -1)
        @test_throws ArgumentError T.schedule_bracket(plan, start, 60, ["f1", "f1"])
        @test length(T.schedule_bracket(plan, nothing, 0, fields(1)).games) == length(plan.matches)
    end

    @testset "fields spread each team's games evenly and skip held time" begin
        start = DateTime(2026, 6, 6, 9)
        function round_robin_games(n, field_count, held)
            games = @NamedTuple{home::String, away::String, starts_at::DateTime, ends_at::DateTime}[]
            slot = 0
            for pairs in T.round_robin(["t$(i)" for i in 1:n])
                left = copy(pairs)
                while !isempty(left)
                    starts_at = start + Hour(slot)
                    slot += 1
                    free = count(i -> T.field_free(held, "f$(i)", starts_at, starts_at + Hour(1)), 1:field_count)
                    free == 0 && continue
                    for (home, away) in splice!(left, 1:min(free, length(left)))
                        push!(games, (; home, away, starts_at, ends_at = starts_at + Hour(1)))
                    end
                end
            end
            return games
        end
        spread(games, assigned, fields, n) = maximum(
            maximum(counts) - minimum(counts) for counts in
            ([count(i -> assigned[i] == field && team in (games[i].home, games[i].away), eachindex(games))
              for field in fields] for team in ("t$(i)" for i in 1:n)))
        for n in 4:2:12, field_count in 2:3, blocked in (false, true)
            held = blocked ? T.HeldTime("f1" => [(start + Hour(2), start + Hour(4))]) : T.HeldTime()
            fields = ["f$(i)" for i in 1:field_count]
            games = round_robin_games(n, field_count, held)
            assigned = T.assign_fields(games, fields; held)
            @test length(assigned) == length(games)
            # No field holds two games at once, and held time stays free.
            @test allunique((game.starts_at, field) for (game, field) in zip(games, assigned))
            @test all(T.field_free(held, field, game.starts_at, game.ends_at)
                      for (game, field) in zip(games, assigned))
            # Two fields and nothing held: every team within one game of an even split,
            # except four teams, whose round's two games always share a start.
            if field_count == 2 && !blocked
                @test spread(games, assigned, fields, n) == (n == 4 ? 3 : 1)
            elseif n > 4
                @test spread(games, assigned, fields, n) <= 2
            end
        end
        # The same games always get the same fields.
        games = round_robin_games(8, 2, T.HeldTime())
        @test T.assign_fields(games, ["f1", "f2"]) == T.assign_fields(copy(games), ["f1", "f2"])
        @test_throws ArgumentError T.assign_fields(games[1:2], ["f1"])
        # Games that overlap without starting together, and repeated field ids.
        game(home, away, from, hours) = (; home, away, starts_at = start + Hour(from),
                                         ends_at = start + Hour(from + hours))
        @test_throws ArgumentError T.assign_fields([game("a", "b", 0, 2), game("c", "d", 1, 2)], ["f1", "f2"])
        @test T.assign_fields([game("a", "b", 0, 1), game("c", "d", 1, 1)], ["f1"]) == ["f1", "f1"]
        @test_throws ArgumentError T.assign_fields([game("a", "b", 0, 1)], ["f1", "f1"])
        @test T.field_free(T.HeldTime("f1" => [(start, start + Hour(1))]), "f1", start + Hour(1), start + Hour(2))
    end

    include("golden.jl")
end
