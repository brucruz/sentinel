defmodule Sentinel.Collectors.Behaviour do
  @moduledoc """
  Defines the contract for metric collectors.

  Each collector periodically gathers metrics and writes them to MetricStore.
  """

  @callback collect() :: :ok
  @callback interval() :: pos_integer()
end
