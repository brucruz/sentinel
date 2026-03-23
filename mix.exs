defmodule Sentinel.MixProject do
  use Mix.Project

  def project do
    [
      app: :sentinel,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Sentinel.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:finch, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:ex_gram, "~> 0.55"},
      {:req, "~> 0.5"},
      {:dotenvy, "~> 0.8"},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp releases do
    [
      sentinel: [
        include_erts: true,
        strip_beams: true
      ]
    ]
  end
end
