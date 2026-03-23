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

  @snapshot %{system: @system_metrics, disk: @disk_metrics}

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
      assert msg =~ "/help"
    end

    test "is valid HTML with header" do
      msg = Formatter.help_message()
      assert msg =~ "<b>Sentinel Commands</b>"
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
