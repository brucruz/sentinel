defmodule SentinelTest do
  use ExUnit.Case

  test "application starts" do
    assert Process.whereis(Sentinel.Supervisor) != nil
  end
end
