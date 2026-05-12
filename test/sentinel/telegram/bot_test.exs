defmodule Sentinel.Telegram.BotTest do
  use ExUnit.Case
  use ExGram.Test

  alias Sentinel.MetricStore

  setup context do
    # Start MetricStore and History for this test
    start_supervised!(MetricStore)
    start_supervised!(Sentinel.History)

    # Seed metrics so commands have data to format
    MetricStore.put(:system, :cpu_percent, 25.0)
    MetricStore.put(:system, :memory, %{percent: 50.0, used_kb: 2_097_152, total_kb: 4_194_304})
    MetricStore.put(:system, :loadavg, %{load1: 0.5, load5: 0.4, load15: 0.3})

    MetricStore.put(:disk, "/", %{
      mount: "/",
      percent: 40,
      used_kb: 20_971_520,
      total_kb: 52_428_800
    })

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
        assert body[:text] =~ "/peak"
        assert body[:text] =~ "/since"
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

  describe "/peak" do
    test "responds with no samples message when history is empty", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Peak"
        assert body[:text] =~ "24h"
        assert body[:text] =~ "No samples"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/peak 24h"))
      ExGram.Test.verify!()
    end

    test "responds with peak values when history has samples", %{bot_name: bot_name} do
      now = System.system_time(:second)
      :ok = Sentinel.History.put(80.0, 50.0, 5.0, 1.2, now - 10)
      :ok = Sentinel.History.put(40.0, 90.0, 25.0, 0.4, now - 5)

      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Peak"
        assert body[:text] =~ "1h"
        assert body[:text] =~ "80.0%"
        assert body[:text] =~ "90.0%"
        assert body[:text] =~ "25.0%"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/peak 1h"))
      ExGram.Test.verify!()
    end

    test "defaults to 24h when no argument given", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "24h"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/peak"))
      ExGram.Test.verify!()
    end

    test "responds with usage on bad duration", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Usage"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/peak garbage"))
      ExGram.Test.verify!()
    end
  end

  describe "/since" do
    test "responds with peak values since given ISO 8601 timestamp", %{bot_name: bot_name} do
      now = System.system_time(:second)
      :ok = Sentinel.History.put(55.0, 30.0, 2.0, 0.3, now - 30)

      iso = now |> DateTime.from_unix!() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()

      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Peak"
        assert body[:text] =~ "since"
        assert body[:text] =~ "55.0%"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/since #{iso}"))
      ExGram.Test.verify!()
    end

    test "responds with usage when no timestamp given", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Usage"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/since"))
      ExGram.Test.verify!()
    end

    test "responds with usage on unparseable timestamp", %{bot_name: bot_name} do
      ExGram.Test.expect(:send_message, fn body ->
        assert body[:text] =~ "Usage"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/since not-a-date"))
      ExGram.Test.verify!()
    end
  end

  describe "parse_duration/1" do
    test "parses h/m/s/d suffixes" do
      assert {:ok, 86_400, "24h"} = Sentinel.Telegram.Bot.parse_duration("24h")
      assert {:ok, 1800, "30m"} = Sentinel.Telegram.Bot.parse_duration("30m")
      assert {:ok, 45, "45s"} = Sentinel.Telegram.Bot.parse_duration("45s")
      assert {:ok, 86_400, "1d"} = Sentinel.Telegram.Bot.parse_duration("1d")
    end

    test "defaults to 24h on empty string" do
      assert {:ok, 86_400, "24h"} = Sentinel.Telegram.Bot.parse_duration("")
    end

    test "returns :error on invalid input" do
      assert :error = Sentinel.Telegram.Bot.parse_duration("garbage")
      assert :error = Sentinel.Telegram.Bot.parse_duration("24x")
    end
  end

  describe "parse_since/1" do
    test "parses ISO 8601 with timezone" do
      assert {:ok, ts, _label} = Sentinel.Telegram.Bot.parse_since("2026-05-12T05:00:00Z")
      assert is_integer(ts)
    end

    test "returns :error on bad input" do
      assert :error = Sentinel.Telegram.Bot.parse_since("not-a-date")
      assert :error = Sentinel.Telegram.Bot.parse_since("")
    end
  end

  describe "bot_commands/0" do
    test "returns a non-empty list of well-formed BotCommand structs" do
      cmds = Sentinel.Telegram.Bot.bot_commands()

      assert is_list(cmds)
      assert cmds != []

      Enum.each(cmds, fn cmd ->
        assert %ExGram.Model.BotCommand{command: name, description: desc} = cmd
        assert is_binary(name)
        assert is_binary(desc)
        assert String.length(name) <= 32
        assert String.length(desc) <= 256
        assert Regex.match?(~r/^[a-z0-9_]{1,32}$/, name)
        assert desc != ""
      end)
    end

    test "command names are unique" do
      names = Enum.map(Sentinel.Telegram.Bot.bot_commands(), & &1.command)
      assert names == Enum.uniq(names)
    end

    test "includes the commands the bot handles" do
      names = Enum.map(Sentinel.Telegram.Bot.bot_commands(), & &1.command)

      for expected <- ~w(start status disk containers container peak since help) do
        assert expected in names
      end
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
