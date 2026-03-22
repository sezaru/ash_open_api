defmodule AshOpenApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_open_api,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.19"},
      {:spark, "~> 2.4"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:oaskit, "~> 0.12"}
    ]
  end
end
