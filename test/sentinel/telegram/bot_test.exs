defmodule Sentinel.Telegram.BotTest do
  use ExUnit.Case
  use ExGram.Test

  alias Sentinel.MetricStore

  setup context do
    # Start MetricStore for this test
    start_supervised!(MetricStore)

    # Seed metrics so commands have data to format
    MetricStore.put(:system, :cpu_percent, 25.0)
    MetricStore.put(:system, :memory, %{percent: 50.0, used_kb: 2_097_152, total_kb: 4_194_304})
    MetricStore.put(:system, :loadavg, %{load1: 0.5, load5: 0.4, load15: 0.3})
    MetricStore.put(:disk, "/", %{mount: "/", percent: 40, used_kb: 20_971_520, total_kb: 52_428_800})

    MetricStore.put(:docker, :containers, [
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
      }
    ])

    MetricStore.put(:docker, {:stats, "myapp-web"}, %{
      cpu_percent: 12.5,
      memory_usage_bytes: 104_857_600,
      memory_limit_bytes: 1_073_741_824,
      memory_percent: 9.8
    })

    MetricStore.put(:docker, {:stats, "redis"}, %{
      cpu_percent: 2.3,
      memory_usage_bytes: 52_428_800,
      memory_limit_bytes: 536_870_912,
      memory_percent: 9.8
    })

    {bot_name, _} = ExGram.Test.start_bot(context, Sentinel.Telegram.Bot)
    {:ok, bot_name: bot_name}
  end

  defp make_update(text) do
    chat_id_int = 123_456

    %ExGram.Model.Update{
      update_id: System.unique_integer([:positive]),
      message: %ExGram.Model.Message{
        message_id: System.unique_integer([:positive]),
        chat: %ExGram.Model.Chat{id: chat_id_int, type: "private"},
        text: text,
        date: System.os_time(:second)
      }
    }
  end

  describe "/status" do
    test "responds with system status", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "System Status"
        assert body[:text] =~ "CPU"
        assert body[:text] =~ "25.0%"
        assert body[:parse_mode] == "HTML"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/status"))
      ExGram.Test.verify!()
    end
  end

  describe "/disk" do
    test "responds with disk usage", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Disk Usage"
        assert body[:text] =~ "40%"
        assert body[:parse_mode] == "HTML"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/disk"))
      ExGram.Test.verify!()
    end
  end

  describe "/help" do
    test "responds with available commands", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Sentinel Commands"
        assert body[:text] =~ "/status"
        assert body[:text] =~ "/disk"
        assert body[:text] =~ "/containers"
        assert body[:text] =~ "/container"
        assert body[:text] =~ "/help"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/help"))
      ExGram.Test.verify!()
    end
  end

  describe "/status includes containers" do
    test "shows container summary", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Containers"
        assert body[:text] =~ "2 running"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/status"))
      ExGram.Test.verify!()
    end
  end

  describe "/containers" do
    test "responds with container list", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Containers"
        assert body[:text] =~ "myapp-web"
        assert body[:text] =~ "redis"
        assert body[:parse_mode] == "HTML"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/containers"))
      ExGram.Test.verify!()
    end
  end

  describe "/container" do
    test "responds with container detail", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "myapp-web"
        assert body[:text] =~ "running"
        assert body[:text] =~ "12.5%"
        assert body[:parse_mode] == "HTML"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/container myapp-web"))
      ExGram.Test.verify!()
    end

    test "responds with usage when no name given", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Usage"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/container"))
      ExGram.Test.verify!()
    end

    test "responds with not found for unknown container", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "not found"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/container nonexistent"))
      ExGram.Test.verify!()
    end
  end

  describe "unknown command" do
    test "responds with help suggestion", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Unknown command"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/foobar"))
      ExGram.Test.verify!()
    end
  end
end
