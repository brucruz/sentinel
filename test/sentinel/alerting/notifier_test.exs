defmodule Sentinel.Alerting.NotifierTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    %{bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  test "send_message/2 returns {:ok, body} on success", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "POST", "/bottest-token/sendMessage", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["chat_id"] == "test-chat-id"
      assert payload["text"] == "Hello!"
      assert payload["parse_mode"] == "HTML"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true, "result" => %{}}))
    end)

    assert {:ok, %{"ok" => true}} =
             Sentinel.Alerting.Notifier.send_message("Hello!", base_url: base_url)
  end

  test "send_message/2 returns {:error, {status, body}} on API error", %{
    bypass: bypass,
    base_url: base_url
  } do
    Bypass.expect_once(bypass, "POST", "/bottest-token/sendMessage", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(400, Jason.encode!(%{"ok" => false, "description" => "Bad Request"}))
    end)

    assert {:error, {400, _body}} =
             Sentinel.Alerting.Notifier.send_message("Hello!", base_url: base_url)
  end

  test "check_connectivity/1 returns :ok on success", %{bypass: bypass, base_url: base_url} do
    Bypass.expect_once(bypass, "GET", "/bottest-token/getMe", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"ok" => true}))
    end)

    assert :ok = Sentinel.Alerting.Notifier.check_connectivity(base_url: base_url)
  end

  test "check_connectivity/1 returns {:error, ...} on failure", %{
    bypass: bypass,
    base_url: base_url
  } do
    Bypass.expect_once(bypass, "GET", "/bottest-token/getMe", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(401, "Unauthorized")
    end)

    assert {:error, {401, _}} =
             Sentinel.Alerting.Notifier.check_connectivity(base_url: base_url)
  end
end
