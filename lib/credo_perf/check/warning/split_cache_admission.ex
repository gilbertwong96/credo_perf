defmodule CredoPerf.Check.Warning.SplitCacheAdmission do
  @moduledoc """
  Flags a cache that inserts into ETS and accounts for its bytes with `:counters` in the same file.

  Request processes run both steps concurrently, so two admissions can each see room, both insert, and
  the cache exceeds its budget with a counter that does not describe what is stored. A review of one
  such cache called it out: "public ETS budget check, accounting and insertion are separate operations
  across request processes".

  Admit inside the process that owns the bound, or reserve with `:atomics.add_get/3` first and release
  if the reservation does not fit.
  """

  use Credo.Check,
    id: "CP1003",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      The budget check, the accounting and the insert cannot be separate operations across request
      processes: concurrent admissions can exceed the bound and miscount replacements.

      Admit in the owning process, or reserve atomically and release on rejection.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    {insert, counters} = scan(source_file)

    if insert && counters do
      [
        format_issue(issue_meta,
          message:
            "This module inserts into ETS and accounts for its bytes with :counters in separate steps. " <>
              "Under concurrency the cache can exceed its bound: admit in the owning process, or " <>
              "reserve with :atomics.add_get/3 and release on rejection.",
          trigger: ":ets.insert",
          line_no: insert
        )
      ]
    else
      []
    end
  end

  defp scan(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn ast, {insert, counters} ->
        case ast do
          {{:., _, [:ets, :insert]}, meta, _} ->
            {ast, {insert || meta[:line], counters}}

          {{:., _, [{:__aliases__, _, [:ets]}, :insert]}, meta, _} ->
            {ast, {insert || meta[:line], counters}}

          {{:., _, [:counters, name]}, meta, _} when name in [:add, :sub, :put] ->
            {ast, {insert, counters || meta[:line]}}

          {{:., _, [{:__aliases__, _, [:counters]}, name]}, meta, _}
          when name in [:add, :sub, :put] ->
            {ast, {insert, counters || meta[:line]}}

          _ ->
            {ast, {insert, counters}}
        end
      end,
      {nil, nil}
    )
  end
end
