defmodule Sentinel.Alerting.CooldownTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Sentinel.Alerting.Cooldown)
    :ok
  end

  test "can_alert?/1 returns true for unknown key" do
    assert Sentinel.Alerting.Cooldown.can_alert?(:never_seen)
  end

  test "can_alert?/1 returns false after record_alert within cooldown window" do
    key = :test_alert
    Sentinel.Alerting.Cooldown.record_alert(key)

    # Default cooldown is 15 minutes, so this should be false
    refute Sentinel.Alerting.Cooldown.can_alert?(key)
  end

  test "can_alert?/1 returns true after cooldown expires" do
    key = :expired_alert

    # Manually insert an old record (well past cooldown)
    :ets.insert(:sentinel_cooldowns, {key, System.system_time(:second) - 3600})

    assert Sentinel.Alerting.Cooldown.can_alert?(key)
  end

  test "clear/0 resets all cooldowns" do
    Sentinel.Alerting.Cooldown.record_alert(:alert_a)
    Sentinel.Alerting.Cooldown.record_alert(:alert_b)

    refute Sentinel.Alerting.Cooldown.can_alert?(:alert_a)
    refute Sentinel.Alerting.Cooldown.can_alert?(:alert_b)

    Sentinel.Alerting.Cooldown.clear()

    assert Sentinel.Alerting.Cooldown.can_alert?(:alert_a)
    assert Sentinel.Alerting.Cooldown.can_alert?(:alert_b)
  end

  test "different keys are independent" do
    Sentinel.Alerting.Cooldown.record_alert(:alert_x)

    refute Sentinel.Alerting.Cooldown.can_alert?(:alert_x)
    assert Sentinel.Alerting.Cooldown.can_alert?(:alert_y)
  end
end
