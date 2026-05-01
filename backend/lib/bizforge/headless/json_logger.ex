defmodule Bizforge.Headless.JsonLogger do
  @moduledoc """
  Custom Logger formatter that outputs structured JSON lines.

  Activated when `BIZFORGE_LOG_FORMAT=json`. Each log entry is a
  single-line JSON object with timestamp, level, message, and metadata.

  ## Usage in config/runtime.exs

      if System.get_env("BIZFORGE_LOG_FORMAT") == "json" do
        config :logger, :console,
          format: {Bizforge.Headless.JsonLogger, :format},
          metadata: :all
      end
  """

  @spec format(
          Logger.level(),
          Logger.message(),
          Logger.Formatter.date_time_ms(),
          keyword()
        ) :: iodata()
  def format(level, message, timestamp, metadata) do
    ts = format_timestamp(timestamp)
    msg = IO.iodata_to_binary(message)

    base = %{
      timestamp: ts,
      level: Atom.to_string(level),
      message: msg
    }

    meta =
      metadata
      |> Keyword.drop([:erl_level, :gl, :time])
      |> Enum.reduce(%{}, fn
        {key, value}, acc when is_binary(value) or is_number(value) or is_atom(value) ->
          Map.put(acc, key, value)

        {key, value}, acc ->
          Map.put(acc, key, inspect(value))
      end)

    entry =
      if map_size(meta) > 0 do
        Map.put(base, :metadata, meta)
      else
        base
      end

    case Jason.encode(entry) do
      {:ok, json} -> [json, "\n"]
      {:error, _} -> ["#{ts} [#{level}] #{msg}\n"]
    end
  end

  defp format_timestamp({date, {h, m, s, ms}}) do
    {year, month, day} = date

    :io_lib.format(
      "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
      [year, month, day, h, m, s, ms]
    )
    |> IO.iodata_to_binary()
  end
end
