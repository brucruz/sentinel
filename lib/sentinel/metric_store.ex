defmodule Sentinel.MetricStore do
  @moduledoc """
  ETS-backed in-memory store for the latest metric snapshots.

  Collectors write metrics here; the Evaluator and Telegram bot read from it.
  """

  # TODO: Milestone 2 — implement GenServer with ETS backing
end
