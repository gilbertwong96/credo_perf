defmodule CredoPerf.Check.Warning.ProcessDictionaryCacheInPlug do
  @moduledoc """
  Flags a `Plug` (a module that defines `call/2`) that uses `Process.put/2`, which is almost always an
  attempt to memoize across requests.

  Bandit and Cowboy serve each request in a fresh process, so the dictionary never survives: measured
  in a port that cached a parsed header and a signed cookie this way, the hit rate was **0%** — one miss
  per request — and the memo was pure overhead.

  For per-request state, pass it through the conn or an argument. To keep something across requests, use
  ETS, `:persistent_term` or a process you own — with a bound and an owner.
  """

  use Credo.Check,
    id: "CP1004",
    base_priority: :normal,
    category: :warning,
    explanations: [
      check: """
      A process dictionary in a Plug cannot outlive one request: every request is served in a new
      process, so the memo never hits.

      Use the conn for per-request state, or ETS / :persistent_term for anything longer lived.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    if plug?(source_file) do
      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
      |> Enum.reverse()
    else
      []
    end
  end

  defp plug?(source_file) do
    plug? =
      Credo.Code.prewalk(
        source_file,
        fn
          {:def, _, [{:call, _, args} | _]} = ast, _acc
          when is_list(args) and length(args) == 2 ->
            {ast, true}

          ast, acc ->
            {ast, acc}
        end,
        false
      )

    plug?
  end

  defp traverse(
         {{:., _, [{:__aliases__, meta, [:Process]}, :put]}, _, _} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line) do
    format_issue(issue_meta,
      message:
        "Process.put/2 in a Plug cannot outlive one request: every request runs in a new process, " <>
          "so this memo never hits. Use the conn, ETS or :persistent_term.",
      trigger: "Process.put",
      line_no: line
    )
  end
end
