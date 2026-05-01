defmodule Bizforge.CLI.Pause do
  @moduledoc """
  Handles the `bizforge pause` command.

  Pauses all heartbeat schedules without killing active sessions.
  Agents remain in their current state but no new heartbeats fire.
  """

  def run(_argv) do
    IO.puts("Pausing all heartbeat schedules...")

    case Bizforge.Headless.Monitor.pause_all() do
      {:ok, count} ->
        IO.puts("Paused #{count} schedule(s). Use 'bizforge resume' to restart.")

      {:error, :not_running} ->
        IO.puts(:stderr, "No headless instance is running.")
        System.halt(1)
    end
  end
end
