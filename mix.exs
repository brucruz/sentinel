defmodule Sentinel.MixProject do
  use Mix.Project

  def project do
    [
      app: :sentinel,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
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

  defp deps do
    [
      {:finch, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:ex_gram, "~> 0.55"},
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
