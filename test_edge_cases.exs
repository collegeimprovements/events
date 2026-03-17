import ExUnit.Assertions
alias FnTypes.Pipeline

# Edge case 1: Non-map return
result = Pipeline.new(%{x: 1})
|> Pipeline.step(:bad, fn _ctx -> {:ok, "not a map"} end)
|> Pipeline.run()
IO.inspect(result, label: "Non-map return")

# Edge case 2: Parallel with mixed returns
result2 = Pipeline.new(%{})
|> Pipeline.parallel([
  {:t1, fn _ctx -> {:ok, %{a: 1}} end},
  {:t2, fn _ctx -> {:ok, 42} end}
])
|> Pipeline.run()
IO.inspect(result2, label: "Parallel mixed returns")

# Edge case 3: Empty pipeline
result3 = Pipeline.new(%{x: 1}) |> Pipeline.run()
IO.inspect(result3, label: "Empty pipeline")

# Edge case 4: Rollback with failed step in first position
result4 = Pipeline.new(%{})
|> Pipeline.step(:step1, fn _ctx -> {:error, :failed} end, rollback: fn _ctx -> :ok end)
|> Pipeline.run_with_rollback()
IO.inspect(result4, label: "Rollback on first step")
