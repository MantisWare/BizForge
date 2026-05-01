defmodule Bizforge.Headless.SecretScrubber do
  @moduledoc """
  Scrubs sensitive values from strings, maps, and log output.

  Detects and redacts:
    - API keys (patterns like sk-*, Bearer tokens, hex strings > 32 chars)
    - Passwords and secrets in key-value pairs
    - Email credentials
    - Connection strings with embedded credentials

  Applied to health endpoint responses, log output, and notification payloads.
  """

  @sensitive_keys ~w(
    password secret token api_key apikey secret_key private_key
    access_token refresh_token authorization bearer credentials
    smtp_password webhook_secret tls_key
  )

  @redacted "[REDACTED]"

  @doc "Scrubs sensitive values from a map (recursive)."
  def scrub_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      key_str = to_string(key) |> String.downcase()

      cond do
        sensitive_key?(key_str) ->
          {key, @redacted}

        is_map(value) ->
          {key, scrub_map(value)}

        is_list(value) ->
          {key, Enum.map(value, &scrub_value/1)}

        is_binary(value) ->
          {key, scrub_string(value)}

        true ->
          {key, value}
      end
    end)
  end

  def scrub_map(value), do: value

  @doc "Scrubs sensitive patterns from a string."
  def scrub_string(str) when is_binary(str) do
    str
    |> redact_bearer_tokens()
    |> redact_api_keys()
    |> redact_connection_strings()
  end

  def scrub_string(value), do: value

  @doc "Scrubs a list of log lines."
  def scrub_logs(lines) when is_list(lines) do
    Enum.map(lines, &scrub_string/1)
  end

  defp scrub_value(value) when is_map(value), do: scrub_map(value)
  defp scrub_value(value) when is_binary(value), do: scrub_string(value)
  defp scrub_value(value), do: value

  defp sensitive_key?(key) do
    Enum.any?(@sensitive_keys, fn sensitive ->
      String.contains?(key, sensitive)
    end)
  end

  defp redact_bearer_tokens(str) do
    Regex.replace(~r/Bearer\s+[A-Za-z0-9\-_.~+\/]+=*/i, str, "Bearer #{@redacted}")
  end

  defp redact_api_keys(str) do
    str
    |> Regex.replace(~r/sk-[A-Za-z0-9]{20,}/, "sk-#{@redacted}")
    |> Regex.replace(~r/key-[A-Za-z0-9]{20,}/, "key-#{@redacted}")
    |> Regex.replace(~r/(?<=[=:]\s?)[A-Fa-f0-9]{40,}/, @redacted)
  end

  defp redact_connection_strings(str) do
    Regex.replace(
      ~r/(postgres|mysql|redis|amqp):\/\/[^:]+:[^@]+@/,
      str,
      "\\1://#{@redacted}:#{@redacted}@"
    )
  end
end
