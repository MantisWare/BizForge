defmodule Bizforge.AdapterTest do
  @moduledoc """
  Tests for the Bizforge.Adapter behaviour contract and all 11 adapter modules.

  These tests verify:
  - Each adapter implements all required callbacks
  - The resolve/1 dispatch maps correctly
  - Adapter.all/0 and Adapter.health_all/0 return correct shapes
  - Each adapter's metadata (type, name, capabilities) is well-formed
  - Event shape contracts for execute_heartbeat/1 and send_message/2
  """
  use ExUnit.Case, async: true

  alias Bizforge.Adapter

  @all_adapter_modules [
    Bizforge.Adapters.OSA,
    Bizforge.Adapters.ClaudeCode,
    Bizforge.Adapters.Codex,
    Bizforge.Adapters.Bash,
    Bizforge.Adapters.HTTP,
    Bizforge.Adapters.OpenClaw,
    Bizforge.Adapters.Cursor,
    Bizforge.Adapters.Gemini,
    Bizforge.Adapters.Aider,
    Bizforge.Adapters.JidoClaw,
    Bizforge.Adapters.Windsurf
  ]

  @adapter_type_map %{
    "osa" => Bizforge.Adapters.OSA,
    "claude-code" => Bizforge.Adapters.ClaudeCode,
    "codex" => Bizforge.Adapters.Codex,
    "bash" => Bizforge.Adapters.Bash,
    "http" => Bizforge.Adapters.HTTP,
    "openclaw" => Bizforge.Adapters.OpenClaw,
    "cursor" => Bizforge.Adapters.Cursor,
    "gemini" => Bizforge.Adapters.Gemini,
    "aider" => Bizforge.Adapters.Aider,
    "jido-claw" => Bizforge.Adapters.JidoClaw,
    "windsurf" => Bizforge.Adapters.Windsurf
  }

  # ── resolve/1 dispatch ──

  describe "Adapter.resolve/1" do
    for {type_string, module} <- %{
          "osa" => Bizforge.Adapters.OSA,
          "claude-code" => Bizforge.Adapters.ClaudeCode,
          "codex" => Bizforge.Adapters.Codex,
          "bash" => Bizforge.Adapters.Bash,
          "http" => Bizforge.Adapters.HTTP,
          "openclaw" => Bizforge.Adapters.OpenClaw,
          "cursor" => Bizforge.Adapters.Cursor,
          "gemini" => Bizforge.Adapters.Gemini,
          "aider" => Bizforge.Adapters.Aider,
          "jido-claw" => Bizforge.Adapters.JidoClaw,
          "windsurf" => Bizforge.Adapters.Windsurf
        } do
      test "resolves #{type_string} to #{inspect(module)}" do
        assert {:ok, unquote(module)} = Adapter.resolve(unquote(type_string))
      end
    end

    test "returns error for unknown adapter type" do
      assert {:error, {:unknown_adapter, "nonexistent"}} = Adapter.resolve("nonexistent")
    end

    test "returns error for empty string" do
      assert {:error, {:unknown_adapter, ""}} = Adapter.resolve("")
    end
  end

  # ── Adapter.all/0 ──

  describe "Adapter.all/0" do
    test "returns metadata for all 11 adapters" do
      result = Adapter.all()
      assert length(result) == 11
    end

    test "each entry has required keys" do
      for entry <- Adapter.all() do
        assert is_binary(entry.type), "type should be a string, got: #{inspect(entry.type)}"
        assert is_binary(entry.name), "name should be a string, got: #{inspect(entry.name)}"
        assert is_boolean(entry.supports_session)
        assert is_boolean(entry.supports_concurrent)
        assert is_list(entry.capabilities)
        assert length(entry.capabilities) > 0, "#{entry.type} should have at least one capability"
      end
    end

    test "adapter types are unique" do
      types = Adapter.all() |> Enum.map(& &1.type)
      assert types == Enum.uniq(types)
    end

    test "adapter types match resolve/1 dispatch table" do
      types = Adapter.all() |> Enum.map(& &1.type) |> Enum.sort()
      dispatch_types = Map.keys(@adapter_type_map) |> Enum.sort()
      assert types == dispatch_types
    end
  end

  # ── Adapter.health_all/0 ──

  describe "Adapter.health_all/0" do
    test "returns health info for all 11 adapters" do
      result = Adapter.health_all()
      assert length(result) == 11
    end

    test "each entry includes health field" do
      for entry <- Adapter.health_all() do
        assert Map.has_key?(entry, :health)

        case entry.health do
          :ok -> :ok
          {:error, reason} -> assert is_binary(reason)
        end
      end
    end
  end

  # ── Individual adapter behaviour compliance ──

  describe "behaviour compliance" do
    for mod <- @all_adapter_modules do
      module_name = mod |> Module.split() |> List.last()

      test "#{module_name} implements all required callbacks" do
        mod = unquote(mod)

        # type/0
        assert is_binary(mod.type())

        # name/0
        assert is_binary(mod.name())

        # supports_session?/0
        assert is_boolean(mod.supports_session?())

        # supports_concurrent?/0
        assert is_boolean(mod.supports_concurrent?())

        # capabilities/0
        caps = mod.capabilities()
        assert is_list(caps)
        assert Enum.all?(caps, &is_atom/1)

        # health/0
        health = mod.health()
        assert health == :ok or match?({:error, _}, health)
      end
    end
  end

  # ── Bash adapter (always available) — deeper tests ──

  describe "Bash adapter start/stop" do
    test "start returns ok with session map" do
      assert {:ok, session} = Bizforge.Adapters.Bash.start(%{"working_dir" => "/tmp"})
      assert session.cwd == "/tmp"
      assert session.shell == "/bin/bash"
    end

    test "start uses defaults when no config provided" do
      assert {:ok, session} = Bizforge.Adapters.Bash.start(%{})
      assert session.cwd == "."
      assert session.shell == "/bin/bash"
    end

    test "stop always returns :ok" do
      assert :ok = Bizforge.Adapters.Bash.stop(%{})
    end

    test "health always returns :ok" do
      assert :ok = Bizforge.Adapters.Bash.health()
    end
  end

  describe "Bash adapter execute_heartbeat/1" do
    test "streams output and completed events for simple command" do
      events =
        Bizforge.Adapters.Bash.execute_heartbeat(%{"context" => "echo hello"})
        |> Enum.to_list()

      assert length(events) >= 1

      types = Enum.map(events, & &1.event_type)
      assert "run.completed" in types

      # Should have output containing "hello"
      output_events = Enum.filter(events, &(&1.event_type == "run.output"))
      assert length(output_events) >= 1

      all_text =
        output_events
        |> Enum.map(& &1.data["text"])
        |> Enum.join("")

      assert all_text =~ "hello"
    end

    test "reports exit code in completed event" do
      events =
        Bizforge.Adapters.Bash.execute_heartbeat(%{"context" => "true"})
        |> Enum.to_list()

      completed = Enum.find(events, &(&1.event_type == "run.completed"))
      assert completed
      assert completed.data["exit_code"] == 0
    end

    test "reports non-zero exit code for failing commands" do
      events =
        Bizforge.Adapters.Bash.execute_heartbeat(%{"context" => "exit 42"})
        |> Enum.to_list()

      completed = Enum.find(events, &(&1.event_type == "run.completed"))
      assert completed
      assert completed.data["exit_code"] == 42
    end

    test "uses default context when none provided" do
      events =
        Bizforge.Adapters.Bash.execute_heartbeat(%{})
        |> Enum.to_list()

      assert length(events) >= 1
    end
  end

  describe "Bash adapter send_message/2" do
    test "executes message as bash command" do
      session = %{"working_dir" => "/tmp"}

      events =
        Bizforge.Adapters.Bash.send_message(session, "echo test_msg")
        |> Enum.to_list()

      types = Enum.map(events, & &1.event_type)
      assert "run.completed" in types

      all_text =
        events
        |> Enum.filter(&(&1.event_type == "run.output"))
        |> Enum.map(& &1.data["text"])
        |> Enum.join("")

      assert all_text =~ "test_msg"
    end
  end

  # ── HTTP adapter ──

  describe "HTTP adapter" do
    test "health always returns :ok" do
      assert :ok = Bizforge.Adapters.HTTP.health()
    end

    test "start requires url in config" do
      assert_raise RuntimeError, ~r/url/, fn ->
        Bizforge.Adapters.HTTP.start(%{})
      end
    end

    test "start returns session with url" do
      assert {:ok, session} = Bizforge.Adapters.HTTP.start(%{"url" => "http://example.com/api"})
      assert session.url == "http://example.com/api"
    end

    test "stop always returns :ok" do
      assert :ok = Bizforge.Adapters.HTTP.stop(%{})
    end
  end

  # ── ClaudeCode adapter ──

  describe "ClaudeCode adapter" do
    test "start returns session with cwd and model" do
      assert {:ok, session} = Bizforge.Adapters.ClaudeCode.start(%{"working_dir" => "/tmp"})
      assert session.cwd == "/tmp"
      assert session.model == "sonnet"
      assert is_binary(session.session_id)
    end

    test "stop with no port returns :ok" do
      assert :ok = Bizforge.Adapters.ClaudeCode.stop(%{})
    end
  end

  # ── Codex adapter ──

  describe "Codex adapter" do
    test "start returns session" do
      assert {:ok, session} = Bizforge.Adapters.Codex.start(%{"working_dir" => "/tmp"})
      assert session.cwd == "/tmp"
    end

    test "stop returns :ok" do
      assert :ok = Bizforge.Adapters.Codex.stop(%{})
    end
  end

  # ── Gemini adapter ──

  describe "Gemini adapter" do
    test "start without API key returns error" do
      # Clear any env var for the test
      original = System.get_env("GEMINI_API_KEY")
      System.delete_env("GEMINI_API_KEY")

      result = Bizforge.Adapters.Gemini.start(%{})
      assert result == {:error, :missing_api_key}

      # Restore
      if original, do: System.put_env("GEMINI_API_KEY", original)
    end

    test "start with API key returns session" do
      assert {:ok, session} = Bizforge.Adapters.Gemini.start(%{"api_key" => "test-key"})
      assert session.api_key == "test-key"
      assert session.model == "gemini-pro"
    end

    test "stop returns :ok" do
      assert :ok = Bizforge.Adapters.Gemini.stop(%{})
    end
  end

  # ── CLI-based adapters (OpenClaw, Cursor, Aider, JidoClaw, Windsurf) ──

  for {mod, adapter_name} <- [
        {Bizforge.Adapters.OpenClaw, "OpenClaw"},
        {Bizforge.Adapters.Cursor, "Cursor"},
        {Bizforge.Adapters.Aider, "Aider"},
        {Bizforge.Adapters.Windsurf, "Windsurf"}
      ] do
    describe "#{adapter_name} adapter" do
      test "stop returns :ok" do
        assert :ok = unquote(mod).stop(%{})
      end

      test "type returns expected string" do
        type = unquote(mod).type()
        assert is_binary(type)
        assert String.length(type) > 0
      end

      test "health returns :ok or error tuple" do
        result = unquote(mod).health()
        assert result == :ok or match?({:error, _}, result)
      end
    end
  end

  describe "JidoClaw adapter" do
    test "stop returns :ok" do
      assert :ok = Bizforge.Adapters.JidoClaw.stop(%{})
    end

    test "type returns jido-claw" do
      assert "jido-claw" = Bizforge.Adapters.JidoClaw.type()
    end

    test "supports both native and CLI modes" do
      assert is_boolean(Bizforge.Adapters.JidoClaw.supports_session?())
      assert is_boolean(Bizforge.Adapters.JidoClaw.supports_concurrent?())
    end
  end

  # ── OSA adapter ──

  describe "OSA adapter" do
    test "type returns osa" do
      assert "osa" = Bizforge.Adapters.OSA.type()
    end

    test "supports sessions and concurrency" do
      assert Bizforge.Adapters.OSA.supports_session?() == true
      assert Bizforge.Adapters.OSA.supports_concurrent?() == true
    end

    test "has rich capabilities" do
      caps = Bizforge.Adapters.OSA.capabilities()
      assert :chat in caps
      assert :tools in caps
    end
  end

  # ── Event shape contract ──

  describe "event shape contract" do
    test "Bash adapter events have required keys" do
      events =
        Bizforge.Adapters.Bash.execute_heartbeat(%{"context" => "echo contract_test"})
        |> Enum.to_list()

      for event <- events do
        assert Map.has_key?(event, :event_type), "event missing :event_type"
        assert Map.has_key?(event, :data), "event missing :data"
        assert is_binary(event.event_type)
        assert is_map(event.data)
      end
    end

    test "event_type follows run.* convention" do
      valid_types = ~w[run.output run.completed run.failed run.tool_call run.tool_result run.thinking]

      events =
        Bizforge.Adapters.Bash.execute_heartbeat(%{"context" => "echo convention_test"})
        |> Enum.to_list()

      for event <- events do
        assert event.event_type in valid_types,
               "unexpected event_type: #{event.event_type}"
      end
    end
  end
end
