defmodule CredoPerf.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :credo_perf,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "CredoPerf"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp description do
    """
    Credo checks for per-request cost in Phoenix and Plug applications: environment reads,
    cache-table walks, split cache admission and process-dictionary caches.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/gilbertwong96/credo_perf"}
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7"}
    ]
  end
end
