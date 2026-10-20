defmodule CredoPerf.Check.Warning.EtsTableWalkForEviction do
  @moduledoc """
  Flags a whole-table ETS walk: `:ets.tab2list/1`, `:ets.foldl/3` or an unbounded `:ets.select/2`.

  Measured in a port that pruned its fragment cache this way on the request path: four processes
  parked in `:ets.tab2list` during a load run, and posting went from 676 to 810-1,750 req/s once
  eviction used an ordered index. A walk also copies every stored value, so a cache of 20 KB bodies
  copies tens of megabytes per eviction.

  If this is eviction, keep an `:ordered_set` keyed by `{timestamp, key}` and retire with
  `:ets.first/1`; if it is reporting, move it out of the request path.
  """

  use Credo.Check,
    id: "CP1002",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A whole-table walk is O(n) and copies every value: 676 -> 810-1,750 req/s in the port this was
      measured on once eviction used an ordered index instead.

      Keep an :ordered_set keyed by {timestamp, key} and retire with :ets.first/1.
      """
    ]

  @walks [:tab2list, :foldl, :select]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
    |> Enum.reverse()
  end

  for name <- @walks do
    defp traverse({{:., _, [:ets, unquote(name)]}, meta, _} = ast, issues, issue_meta) do
      {ast, [issue_for(issue_meta, meta[:line], unquote(to_string(name))) | issues]}
    end

    defp traverse(
           {{:., _, [{:__aliases__, _, [:ets]}, unquote(name)]}, meta, _} = ast,
           issues,
           issue_meta
         ) do
      {ast, [issue_for(issue_meta, meta[:line], unquote(to_string(name))) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line, trigger) do
    format_issue(issue_meta,
      message:
        ":ets.#{trigger} walks the whole table and copies every value. If this is eviction, keep " <>
          "an :ordered_set keyed by {timestamp, key} and retire with :ets.first/1.",
      trigger: ":ets.#{trigger}",
      line_no: line
    )
  end
end
