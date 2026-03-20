defmodule Sentinel.Collectors.DiskTest do
  use ExUnit.Case, async: true

  describe "parse_df/1" do
    test "parses standard Linux df output" do
      output = """
      Filesystem     1024-blocks      Used Available Capacity Mounted on
      /dev/sda1        51475068  18234567  30601234      38% /
      /dev/sdb1        10240000   5120000   5120000      50% /data
      tmpfs             4029324         0   4029324       0% /dev/shm
      """

      entries = Sentinel.Collectors.Disk.parse_df(output)

      assert length(entries) == 2

      root = Enum.find(entries, &(&1.mount == "/"))
      assert root.filesystem == "/dev/sda1"
      assert root.total_kb == 51_475_068
      assert root.used_kb == 18_234_567
      assert root.available_kb == 30_601_234
      assert root.percent == 38

      data = Enum.find(entries, &(&1.mount == "/data"))
      assert data.filesystem == "/dev/sdb1"
      assert data.percent == 50
    end

    test "filters out non-physical filesystems" do
      output = """
      Filesystem     1024-blocks      Used Available Capacity Mounted on
      /dev/sda1        51475068  18234567  30601234      38% /
      tmpfs             4029324         0   4029324       0% /dev/shm
      devtmpfs          4029324         0   4029324       0% /dev
      overlay          51475068  18234567  30601234      38% /var/lib/docker/overlay2
      """

      entries = Sentinel.Collectors.Disk.parse_df(output)

      assert length(entries) == 1
      assert hd(entries).mount == "/"
    end

    test "handles empty output" do
      output = """
      Filesystem     1024-blocks      Used Available Capacity Mounted on
      """

      assert Sentinel.Collectors.Disk.parse_df(output) == []
    end
  end
end
