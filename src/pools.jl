"""
    snake_pools(count::Int, pool_count::Int) -> Vector{Int}

The pool, from 1 to `pool_count`, for each of `count` seeds in seed order, dealt in
a snake: seeds 1 to P go to pools 1 to P, the next P to pools P down to 1, and so
on. Each pool then gets a similar spread of strong and weak seeds.

```julia
julia> Tournaments.snake_pools(8, 3)
8-element Vector{Int64}:
 1
 2
 3
 3
 2
 1
 1
 2
```
"""
function snake_pools(count::Int, pool_count::Int)
    pool_count >= 1 || throw(ArgumentError("pool_count must be at least 1"))
    pools = Int[]
    for index in 1:count
        block, position = divrem(index - 1, pool_count)
        push!(pools, iseven(block) ? position + 1 : pool_count - position)
    end
    return pools
end
