defmodule Bizforge.CLI.Resume do
  @moduledoc """
  Handles the `bizforge resume` command.

  Resumes previously paused heartbeat schedules.
  """

  def run(_argv) do
    IO.puts("Resuming all heartbeat schedules...")

    case Bizforge.Headless.Monitor.resume_all() do
      {:ok, count} ->
        IO.puts("Resumed #{count} schedule(s).")

      {:error, :not_running} ->
        IO.puts(:stderr, "No headless instance is running.")
        System.halt(1)
    end
  end
end
