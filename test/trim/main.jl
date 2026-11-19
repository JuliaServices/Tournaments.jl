# Compiled with `juliac --trim=safe` in CI to check that every public function stays
# trim-safe, then run to check a few results.
using Dates
import Tournaments as T

function check(name::String, ok::Bool)::Bool
    println(Core.stdout, ok ? "ok   " : "FAIL ", name)
    return ok
end

function run_checks()::Bool
    teams = ["t1", "t2", "t3", "t4", "t5", "t6"]
    rounds = T.round_robin(teams)
    ok = check("round_robin", length(rounds) == 5 && sum(length, rounds) == 15)
    season, total = T.season_rounds(teams, 4)
    ok &= check("season_rounds", total == 12 && sum(length, season) == 12)
    pairs, bye = T.swiss_round(["a", "b", "c", "d", "e"], 2, Set([("a", "b"), ("b", "a")]), Set{String}())
    ok &= check("swiss_round", length(pairs) == 2 && bye == "e")
    ok &= check("snake_pools", T.snake_pools(6, 2) == [1, 2, 2, 1, 1, 2])
    ok &= check("bracket_order", T.bracket_order(4) == [1, 4, 2, 3])
    plan = T.plan_bracket(teams; bracket_type = "double")
    placement = T.plan_bracket(teams; third_place = true, full_placement = false)
    ok &= check("plan_bracket", length(plan.matches) == 10 && length(placement.matches) == 6)
    start = DateTime(2026, 6, 6, 9)
    held = T.HeldTime("f1" => [(start, start + Hour(1))])
    schedule = T.schedule_bracket(plan, start, 60, ["f1", "f2"]; held, rest_slots = 1)
    ok &= check("schedule_bracket", length(schedule.games) == 10 && schedule.scheduled_ends_at !== nothing)
    games = @NamedTuple{home::String, away::String, starts_at::DateTime, ends_at::DateTime}[]
    for (index, round) in enumerate(rounds), (home, away) in round
        starts_at = start + Hour(index)
        push!(games, (; home, away, starts_at, ends_at = starts_at + Hour(1)))
    end
    fields = T.assign_fields(games, ["f1", "f2", "f3"]; held)
    ok &= check("assign_fields", length(fields) == length(games) && all(!isempty, fields))
    ok &= check("field_free", T.field_free(held, "f2", start, start + Hour(1)))
    error_caught = try
        T.plan_bracket(["a", "b", "c"]; split_mode = "upper_lower")
        false
    catch e
        e isa ArgumentError
    end
    ok &= check("ArgumentError", error_caught)
    return ok
end

function (@main)(args::Vector{String})::Cint
    ok = run_checks()
    println(Core.stdout, ok ? "all checks passed" : "some checks failed")
    return ok ? Cint(0) : Cint(1)
end
