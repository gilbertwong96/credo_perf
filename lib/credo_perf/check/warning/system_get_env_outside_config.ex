defmodule CredoPerf.Check.Warning.SystemGetEnvOutsideConfig do
  @moduledoc """
  Flags `System.get_env/1,2`, `System.fetch_env/1` and `System.fetch_env!/1` outside configuration
  files.

  Each read takes a VM-global mutex and walks the emulator's environment: measured on an M1 Pro at
  **10.5 us per call** (`:os.getenv/1` alone is 5.6 us; Elixir's wrapper adds the rest), with eight
  processes scaling only 6.0x instead of 8x. A single read per request therefore caps the whole node at
  roughly 95,000 calls a second and adds that latency to every response.

  Read the environment once — `config/runtime.exs`, a boot-time module, or an application env map — and
  have request code call that.
  """

  use Credo.Check,
    id: "CP1001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Reading the OS environment costs ~10.5 us and takes a VM-global lock.

      Load it once at boot (config/runtime.exs or a startup module) and read it from there.
      """,
      params: [excluded: "Regexes of file paths that may read the environment"]
    ]

  @default_excluded [
    ~r{^config/},
    ~r{^test/},
    ~r{^rel/},
    ~r{^mix\.exs$},
    ~r{/env(ironment)?\.ex$}
  ]

  @functions [:get_env, :fetch_env, :fetch_env!]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    excluded = Params.get(params, :excluded, @default_excluded) || @default_excluded

    if Enum.any?(excluded, &Regex.match?(&1, source_file.filename)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
      |> Enum.reverse()
    end
  end

  for function <- @functions do
    defp traverse(
           {{:., _, [{:__aliases__, meta, [:System]}, unquote(function)]}, _, _} = ast,
           issues,
           issue_meta
         ) do
      {ast, [issue_for(issue_meta, meta[:line], "System.#{unquote(function)}") | issues]}
    end
  end

  defp traverse({{:., _, [:os, :getenv]}, meta, _} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, Keyword.get(meta, :line), ":os.getenv/1") | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line, trigger) do
    format_issue(issue_meta,
      message:
        "#{trigger} reads the OS environment: ~10.5 us per call under a VM-global lock. " <>
          "Load it once at boot and read that instead.",
      trigger: trigger,
      line_no: line
    )
  end
end
