# The golden corpus: inputs that the scheduler this code came from saw in its unit
# and integration tests, plus a grid of shapes, each with a SHA-256 of the result
# that scheduler gave (or its error message). This package must give the same results.
using JSON, CodecZlib, SHA
include("golden_canon.jl")

_pairs(rounds) = [[home, away] for (home, away) in rounds]
_time(x) = x === nothing ? nothing : DateTime(String(x))
_text(x) = x === nothing ? nothing : string(x)
_held(x) = T.HeldTime(String(field) => [(DateTime(String(s)), DateTime(String(e))) for (s, e) in spans]
                      for (field, spans) in x)
_feeder(x) = T.BracketFeeder(; team = x["team"] === nothing ? nothing : String(x["team"]),
    seed = x["seed"], source_match_index = x["source_match_index"], take = String(x["take"]))
_plan(x) = T.BracketPlan(; bracket_size = x["bracket_size"], bye_count = x["bye_count"],
    matches = [T.BracketMatch(; round_number = m["round_number"], slot_number = m["slot_number"],
        field_ordinal = m["field_ordinal"], home = _feeder(m["home"]), away = _feeder(m["away"]))
        for m in x["matches"]])
_feeder_out(f::T.BracketFeeder) = Dict{String,Any}("team" => f.team, "seed" => f.seed,
    "source_match_index" => f.source_match_index, "take" => f.take)
_plan_out(plan::T.BracketPlan) = Dict{String,Any}("bracket_size" => plan.bracket_size,
    "bye_count" => plan.bye_count, "matches" => [Dict{String,Any}("round_number" => m.round_number,
        "slot_number" => m.slot_number, "field_ordinal" => m.field_ordinal,
        "home" => _feeder_out(m.home), "away" => _feeder_out(m.away)) for m in plan.matches])
_strings(x) = String[String(s) for s in x]

"This package's result for one corpus case, in the shape the corpus recorder wrote."
function _result(kind::String, input)
    if kind == "round_robin"
        return [_pairs(r) for r in T.round_robin(_strings(input["teams"]))]
    elseif kind == "season_rounds"
        rounds, total = T.season_rounds(_strings(input["teams"]), input["games_per_team"])
        return Dict{String,Any}("rounds" => [_pairs(r) for r in rounds], "total" => total)
    elseif kind == "bracket_order"
        return T.bracket_order(input["size"])
    elseif kind == "snake_pools"
        return T.snake_pools(input["count"], input["pool_count"])
    elseif kind == "swiss_round"
        played = Set{Tuple{String,String}}((String(a), String(b)) for (a, b) in input["played"])
        pairs, bye = T.swiss_round(_strings(input["standings"]), input["round_number"], played,
                                   Set{String}(_strings(input["prior_byes"])))
        return Dict{String,Any}("pairs" => _pairs(pairs), "bye" => bye)
    elseif kind == "plan_bracket"
        o = input["options"]
        return _plan_out(T.plan_bracket(_strings(input["seeds"]); bracket_type = String(o["bracket_type"]),
            split_mode = String(o["split_mode"]), third_place = o["third_place"],
            fifth_place = o["fifth_place"], ninth_place = o["ninth_place"],
            full_placement = o["full_placement"]))
    elseif kind == "schedule_bracket"
        schedule = T.schedule_bracket(_plan(input["plan"]), _time(input["starts_at"]),
            input["round_length_minutes"], _strings(input["fields"]);
            held = _held(input["held"]), rest_slots = input["rest_slots"])
        return Dict{String,Any}("time_slot_count" => schedule.time_slot_count,
            "scheduled_ends_at" => _text(schedule.scheduled_ends_at),
            "games" => [Dict{String,Any}("plan_index" => g.plan_index, "starts_at" => _text(g.starts_at),
                "ends_at" => _text(g.ends_at), "field" => g.field) for g in schedule.games])
    elseif kind == "assign_fields"
        games = [(; home = String(g["home"]), away = String(g["away"]),
                  starts_at = DateTime(String(g["starts_at"])), ends_at = DateTime(String(g["ends_at"])))
                 for g in input["games"]]
        return T.assign_fields(games, _strings(input["fields"]); held = _held(input["held"]))
    end
    error("unknown corpus kind $(kind)")
end

@testset "golden corpus: the same results as the original scheduler" begin
    counts = Dict{String,Int}()
    mismatches = String[]
    open(GzipDecompressorStream, joinpath(@__DIR__, "golden", "corpus.jsonl.gz")) do io
        for line in eachline(io)
            case = JSON.parse(line)
            kind = String(case["kind"])
            counts[kind] = get(counts, kind, 0) + 1
            same = if haskey(case, "error")
                try
                    _result(kind, case["input"])
                    false
                catch e
                    e isa ArgumentError && e.msg == case["error"]
                end
            else
                bytes2hex(sha256(canon(JSON.parse(JSON.json(_result(kind, case["input"])))))) == case["out_sha"]
            end
            same || length(mismatches) >= 5 || push!(mismatches, line[1:min(end, 300)])
            @test same
        end
    end
    isempty(mismatches) || @info "First mismatched cases" mismatches
    # Every kind of case is in the corpus.
    @test sort!(collect(keys(counts))) == ["assign_fields", "bracket_order", "plan_bracket", "round_robin",
                                           "schedule_bracket", "season_rounds", "snake_pools", "swiss_round"]
end
