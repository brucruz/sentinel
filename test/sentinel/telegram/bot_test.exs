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
        assert body[:text] =~ "/help"
        {:ok, %{message_id: 1}}
      end)

      ExGram.Test.push_update(bot_name, make_update("/help"))
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
