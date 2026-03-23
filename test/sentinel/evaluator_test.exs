defmodule Sentinel.EvaluatorTest do
  use ExUnit.Case, async: false

  describe "check_threshold/2 — system CPU" do
    test "triggers when CPU exceeds threshold" do
      snapshot = %{system: %{cpu_percent: {95.0, 1_000}}}

      alerts = Sentinel.Evaluator.check_threshold(
        {:system, :cpu_percent, :gt, 90, :warning},
        snapshot
      )

      assert [%{key: {:system, :cpu_percent}, severity: :warning}] = alerts
      assert hd(alerts).message =~ "95.0%"
    end

    test "does not trigger when CPU is below threshold" do
      snapshot = %{system: %{cpu_percent: {50.0, 1_000}}}

      alerts = Sentinel.Evaluator.check_threshold(
        {:system, :cpu_percent, :gt, 90, :warning},
        snapshot
      )

      assert alerts == []
    end

    test "does not trigger when system metrics are missing" do
      alerts = Sentinel.Evaluator.check_threshold(
        {:system, :cpu_percent, :gt, 90, :warning},
        %{}
      )

      assert alerts == []
    end
  end

  describe "check_threshold/2 — system memory" do
    test "triggers when memory exceeds threshold" do
      snapshot = %{system: %{memory: {%{percent: 90.0}, 1_000}}}

      alerts = Sentinel.Evaluator.check_threshold(
        {:system, :memory_percent, :gt, 85, :warning},
        snapshot
      )

      assert [%{key: {:system, :memory_percent}, severity: :warning}] = alerts
    end

    test "does not trigger when memory is below threshold" do
      snapshot = %{system: %{memory: {%{percent: 50.0}, 1_000}}}

      alerts = Sentinel.Evaluator.check_threshold(
        {:system, :memory_percent, :gt, 85, :warning},
        snapshot
      )

      assert alerts == []
    end
  end

  describe "check_threshold/2 — disk" do
    test "triggers when disk usage exceeds threshold" do
      snapshot = %{disk: %{"/" => {%{percent: 85, mount: "/"}, 1_000}}}

      alerts = Sentinel.Evaluator.check_threshold(
        {:disk, "/", :gt, 80, :warning},
        snapshot
      )

      assert [%{key: {:disk, "/", 80}, severity: :warning}] = alerts
      assert hd(alerts).message =~ "85%"
    end

    test "does not trigger for unknown mount" do
      snapshot = %{disk: %{"/" => {%{percent: 50, mount: "/"}, 1_000}}}

      alerts = Sentinel.Evaluator.check_threshold(
        {:disk, "/data", :gt, 80, :warning},
        snapshot
      )

      assert alerts == []
    end
  end

  describe "check_threshold/2 — docker container stopped" do
    test "triggers for each stopped container" do
      snapshot = %{
        docker: %{
          containers: {
            [
              %{name: "web", state: "running", status: "Up 2h"},
              %{name: "redis", state: "exited", status: "Exited (1) 5m ago"},
              %{name: "worker", state: "exited", status: "Exited (137) 1m ago"}
            ],
            1_000
          }
        }
      }

      alerts = Sentinel.Evaluator.check_threshold(
        {:docker, :container_stopped, :any, nil, :critical},
        snapshot
      )

      assert length(alerts) == 2
      names = Enum.map(alerts, & &1.key) |> Enum.map(&elem(&1, 2))
      assert "redis" in names
      assert "worker" in names
      assert Enum.all?(alerts, &(&1.severity == :critical))
    end

    test "does not trigger when all containers are running" do
      snapshot = %{
        docker: %{
          containers: {
            [%{name: "web", state: "running", status: "Up 2h"}],
            1_000
          }
        }
      }

      alerts = Sentinel.Evaluator.check_threshold(
        {:docker, :container_stopped, :any, nil, :critical},
        snapshot
      )

      assert alerts == []
    end

    test "does not trigger when no docker data" do
      alerts = Sentinel.Evaluator.check_threshold(
        {:docker, :container_stopped, :any, nil, :critical},
        %{}
      )

      assert alerts == []
    end
  end
end
