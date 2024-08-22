defmodule Exfetch.MixProject do
  use Mix.Project

  def project do
    [
      app: :exfetch,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Exfetch.CLI],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # add deps here
    ]
  end
end
