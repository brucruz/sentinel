defmodule Sentinel.Telegram.FormatterTest do
  use ExUnit.Case, async: true

  alias Sentinel.Telegram.Formatter

  @system_metrics %{
    cpu_percent: {45.2, System.monotonic_time()},
    memory:
      {%{percent: 62.5, used_kb: 4_194_304, total_kb: 8_388_608}, System.monotonic_time()},
    loadavg: {%{load1: 1.23, load5: 0.98, load15: 0.76}, System.monotonic_time()}
  }

  @disk_metrics %{
    "/" =>
      {%{mount: "/", percent: 55, used_kb: 52_428_800, total_kb: 104_857_600},
       System.monotonic_time()},
    "/home" =>
      {%{mount: "/home", percent: 30, used_kb: 10_485_760, total_kb: 31_457_280},
       System.monotonic_time()}
  }

  @containers [
    %{
      id: "abc123",
      name: "myapp-web",
      image: "myapp:latest",
      state: "running",
      status: "Up 2 hours",
      created: 1_700_000_000
    },
    %{
      id: "def456",
      name: "redis",
      image: "redis:7-alpine",
      state: "running",
      status: "Up 2 hours",
      created: 1_700_000_000
    },
    %{
      id: "ghi789",
      name: "old-worker",
      image: "worker:old",
      state: "exited",
      status: "Exited (0) 3 hours ago",
      created: 1_699_990_000
    }
  ]

  @myapp_stats %{
    cpu_percent: 12.5,
    memory_usage_bytes: 104_857_600,
    memory_limit_bytes: 1_073_741_824,
    memory_percent: 9.8
  }

  @redis_stats %{
    cpu_percent: 2.3,
    memory_usage_bytes: 52_428_800,
    memory_limit_bytes: 536_870_912,
    memory_percent: 9.8
  }

  @snapshot %{system: @system_metrics, disk: @disk_metrics}

  defp docker_metrics do
    ts = System.monotonic_time()

    %{
      :containers => {@containers, ts},
      {:stats, "myapp-web"} => {@myapp_stats, ts},
      {:stats, "redis"} => {@redis_stats, ts}
    }
  end

  defp snapshot_with_docker do
    Map.put(@snapshot, :docker, docker_metrics())
  end

  describe "startup_message/1" do
    test "includes header" do
      msg = Formatter.startup_message(@snapshot)
      assert msg =~ "<b>Sentinel Started</b>"
    end

    test "includes CPU, memory, and load" do
      msg = Formatter.startup_message(@snapshot)
      assert msg =~ "CPU"
      assert msg =~ "45.2%"
      assert msg =~ "MEM"
      assert msg =~ "62.5%"
      assert msg =~ "LOAD"
      assert msg =~ "1.23"
    end

    test "includes disk entries" do
      msg = Formatter.startup_message(@snapshot)
      assert msg =~ "/"
      assert msg =~ "/home"
      assert msg =~ "55%"
    end
  end

  describe "status_message/1" do
    test "includes System Status header" do
      msg = Formatter.status_message(@snapshot)
      assert msg =~ "<b>System Status</b>"
    end

    test "includes CPU, memory, and load" do
      msg = Formatter.status_message(@snapshot)
      assert msg =~ "45.2%"
      assert msg =~ "62.5%"
      assert msg =~ "1.23"
    end

    test "includes disk entries" do
      msg = Formatter.status_message(@snapshot)
      assert msg =~ "/"
      assert msg =~ "/home"
    end

    test "handles empty snapshot" do
      msg = Formatter.status_message(%{})
      assert msg =~ "CPU"
      assert msg =~ "0.0%"
      assert msg =~ "No disks found"
    end
  end

  describe "disk_message/1" do
    test "includes Disk Usage header" do
      msg = Formatter.disk_message(@disk_metrics)
      assert msg =~ "<b>Disk Usage</b>"
    end

    test "lists mount points with progress bars" do
      msg = Formatter.disk_message(@disk_metrics)
      assert msg =~ "/"
      assert msg =~ "/home"
      assert msg =~ "[#"
    end

    test "handles empty disk metrics" do
      msg = Formatter.disk_message(%{})
      assert msg =~ "No disks found"
    end

    test "filters non-primary mounts" do
      metrics =
        Map.put(@disk_metrics, "/snap/core", {
          %{mount: "/snap/core", percent: 10, used_kb: 1024, total_kb: 10240},
          System.monotonic_time()
        })

      msg = Formatter.disk_message(metrics)
      refute msg =~ "/snap/core"
    end
  end

  describe "help_message/0" do
    test "lists all commands" do
      msg = Formatter.help_message()
      assert msg =~ "/status"
      assert msg =~ "/disk"
      assert msg =~ "/containers"
      assert msg =~ "/container"
      assert msg =~ "/help"
    end

    test "is valid HTML with header" do
      msg = Formatter.help_message()
      assert msg =~ "<b>Sentinel Commands</b>"
    end
  end

  describe "status_message/1 with containers" do
    test "includes container summary" do
      msg = Formatter.status_message(snapshot_with_docker())
      assert msg =~ "Containers"
      assert msg =~ "2 running"
      assert msg =~ "1 stopped"
    end

    test "handles snapshot without docker" do
      msg = Formatter.status_message(@snapshot)
      assert msg =~ "No containers found"
    end
  end

  describe "containers_message/1" do
    test "includes header" do
      msg = Formatter.containers_message(docker_metrics())
      assert msg =~ "<b>Containers</b>"
    end

    test "lists all containers with state" do
      msg = Formatter.containers_message(docker_metrics())
      assert msg =~ "myapp-web"
      assert msg =~ "redis"
      assert msg =~ "old-worker"
    end

    test "shows CPU and memory for running containers" do
      msg = Formatter.containers_message(docker_metrics())
      assert msg =~ "12.5%"
      assert msg =~ "2.3%"
    end

    test "shows running indicator for running containers" do
      msg = Formatter.containers_message(docker_metrics())
      assert msg =~ "●"
      assert msg =~ "○"
    end

    test "handles empty containers" do
      msg = Formatter.containers_message(%{})
      assert msg =~ "No containers found"
    end
  end

  describe "container_detail_message/2" do
    test "shows detailed stats for a running container" do
      msg = Formatter.container_detail_message(docker_metrics(), "myapp-web")
      assert msg =~ "<b>Container: myapp-web</b>"
      assert msg =~ "running"
      assert msg =~ "Up 2 hours"
      assert msg =~ "myapp:latest"
      assert msg =~ "12.5%"
      assert msg =~ "100.0 MB"
    end

    test "shows not available for stopped container stats" do
      msg = Formatter.container_detail_message(docker_metrics(), "old-worker")
      assert msg =~ "old-worker"
      assert msg =~ "exited"
      assert msg =~ "not available"
    end

    test "returns not found for unknown container" do
      msg = Formatter.container_detail_message(docker_metrics(), "nonexistent")
      assert msg =~ "not found"
      assert msg =~ "/containers"
    end
  end

  describe "alert_message/2" do
    test "formats warning alert" do
      msg = Formatter.alert_message(:warning, "CPU at 95.0% (threshold: 90%)")
      assert msg =~ "<b>[WARNING] Alert</b>"
      assert msg =~ "CPU at 95.0%"
    end

    test "formats critical alert" do
      msg = Formatter.alert_message(:critical, "Container <b>redis</b> is exited")
      assert msg =~ "<b>[CRITICAL] Alert</b>"
      assert msg =~ "redis"
    end
  end
end
