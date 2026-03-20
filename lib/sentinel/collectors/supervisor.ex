defmodule Sentinel.Collectors.Supervisor do
  @moduledoc """
  Supervises all metric collectors with :one_for_one strategy.

  Each collector is independent — if one crashes, others keep running.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Sentinel.Collectors.System,
      Sentinel.Collectors.Disk
      # Milestone 3: Sentinel.Collectors.Docker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
