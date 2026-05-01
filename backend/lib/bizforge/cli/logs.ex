defmodule Bizforge.CLI.Logs do
  @moduledoc """
  Handles the `bizforge logs` command.

  Tails the headless instance log file with optional filtering
  by level, agent, or event type.
  """

  def run(argv) do
    {opts, _args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          level: :string,
          agent: :string,
          follow: :boolean,
          lines: :integer
        ],
        aliases: [l: :level, a: :agent, f: :follow, n: :lines]
      )

    log_dir = Path.expand(".bizforge/logs")
    log_file = Path.join(log_dir, "headless.log")

    unless File.exists?(log_file) do
      IO.puts("No headless log file found at #{log_file}")
      IO.puts("Start a headless instance with 'bizforge run' first.")
      System.halt(1)
    end

    lines = Keyword.get(opts, :lines, 50)
    follow? = Keyword.get(opts, :follow, true)

    args = ["-n", to_string(lines)]
    args = if follow?, do: args ++ ["-f"], else: args
    args = args ++ [log_file]

    port = Port.open({:spawn_executable, System.find_executable("tail")}, [:binary, args: args])

    level_filter = opts[:level]
    agent_filter = opts[:agent]

    stream_logs(port, level_filter, agent_filter)
  end

  defp stream_logs(port, level_filter, agent_filter) do
    receive do
      {^port, {:data, data}} ->
        lines = String.split(data, "\n", trim: true)

        lines
        |> Enum.filter(&matches_filters?(&1, level_filter, agent_filter))
        |> Enum.each(&IO.puts/1)

        stream_logs(port, level_filter, agent_filter)

      {:EXIT, ^port, _reason} ->
        :ok
    end
  end

  defp matches_filters?(_line, nil, nil), do: true

  defp matches_filters?(line, level, agent) do
    level_match = level === nil || String.contains?(String.downcase(line), String.downcase(level))

    agent_match =
      agent === nil || String.contains?(String.downcase(line), String.downcase(agent))

    level_match && agent_match
  end
end
