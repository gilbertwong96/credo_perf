defmodule CredoPerf.Scan do
  @moduledoc """
  Runs the checks over a directory and prints their issues.

  Credo normally drives checks through a project's `.credo.exs`; this is for looking at a codebase
  without wiring it up:

      MIX_ENV=test mix run -e 'CredoPerf.Scan.run("../some_project/lib")'
  """

  alias CredoPerf.Check.Warning.{
    EtsTableWalkForEviction,
    ProcessDictionaryCacheInPlug,
    SplitCacheAdmission,
    SystemGetEnvOutsideConfig
  }

  @checks [
    SystemGetEnvOutsideConfig,
    EtsTableWalkForEviction,
    SplitCacheAdmission,
    ProcessDictionaryCacheInPlug
  ]

  def run(path) do
    files = Path.wildcard(Path.join(path, "**/*.ex"))

    issues =
      for file <- files,
          source <- [Credo.SourceFile.parse(File.read!(file), file)],
          check <- @checks,
          issue <- check.run(source, []) do
        "#{issue.filename}:#{issue.line_no} #{inspect(issue.check)} #{issue.message}"
      end

    Enum.each(issues, &IO.puts/1)
    IO.puts("#{length(issues)} issue(s) in #{length(files)} file(s)")
    issues
  end
end
