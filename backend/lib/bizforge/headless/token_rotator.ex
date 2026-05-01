defmodule Bizforge.Headless.TokenRotator do
  @moduledoc """
  Rotates API keys for long-running headless instances.

  Generates a new API key on a configurable schedule (default 24h),
  writes it to `.bizforge/auth`, and maintains a grace period during
  which the old key remains valid.

  The rotation schedule and grace period can be configured via:
    - BIZFORGE_TOKEN_ROTATION_HOURS (default 24)
    - BIZFORGE_TOKEN_GRACE_HOURS (default 1)
  """
  use GenServer
  require Logger

  @default_rotation_hours 24
  @default_grace_hours 1

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def current_keys do
    GenServer.call(__MODULE__, :current_keys)
  catch
    :exit, _ -> []
  end

  @impl true
  def init(_opts) do
    rotation_ms = rotation_hours() * 3_600_000
    grace_ms = grace_hours() * 3_600_000

    state = %{
      current_key: load_or_generate_key(),
      previous_key: nil,
      rotation_ms: rotation_ms,
      grace_ms: grace_ms,
      last_rotation: DateTime.utc_now(),
      rotations: 0
    }

    if rotation_enabled?() do
      Logger.info(
        "[TokenRotator] Active — rotating every #{rotation_hours()}h, grace period #{grace_hours()}h"
      )

      Process.send_after(self(), :rotate, rotation_ms)
    else
      Logger.info("[TokenRotator] Disabled — no API key configured")
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:current_keys, _from, state) do
    keys =
      [state.current_key, state.previous_key]
      |> Enum.reject(&is_nil/1)

    {:reply, keys, state}
  end

  @impl true
  def handle_info(:rotate, state) do
    new_key = generate_key()

    Logger.info("[TokenRotator] Rotating API key (rotation ##{state.rotations + 1})")

    write_key(new_key)

    Application.put_env(:bizforge, :headless,
      Application.get_env(:bizforge, :headless, [])
      |> Keyword.put(:api_key, new_key)
    )

    state = %{
      state
      | previous_key: state.current_key,
        current_key: new_key,
        last_rotation: DateTime.utc_now(),
        rotations: state.rotations + 1
    }

    Process.send_after(self(), :expire_previous, state.grace_ms)
    Process.send_after(self(), :rotate, state.rotation_ms)

    Bizforge.Headless.Notifier.notify("security.token_rotated", %{
      rotation_number: state.rotations,
      grace_period_hours: grace_hours()
    })

    {:noreply, state}
  end

  def handle_info(:expire_previous, state) do
    Logger.debug("[TokenRotator] Grace period expired — previous key invalidated")
    {:noreply, %{state | previous_key: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp load_or_generate_key do
    config = Application.get_env(:bizforge, :headless, [])
    existing = Keyword.get(config, :api_key)

    case existing do
      nil -> nil
      key -> key
    end
  end

  defp generate_key do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp write_key(key) do
    auth_file = Path.expand(".bizforge/auth")
    File.mkdir_p!(Path.dirname(auth_file))
    File.write!(auth_file, key)
  end

  defp rotation_enabled? do
    Application.get_env(:bizforge, :headless, [])
    |> Keyword.get(:api_key)
    |> Kernel.!==(nil)
  end

  defp rotation_hours do
    case System.get_env("BIZFORGE_TOKEN_ROTATION_HOURS") do
      nil -> @default_rotation_hours
      val -> String.to_integer(val)
    end
  end

  defp grace_hours do
    case System.get_env("BIZFORGE_TOKEN_GRACE_HOURS") do
      nil -> @default_grace_hours
      val -> String.to_integer(val)
    end
  end
end
