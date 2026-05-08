defmodule Bizforge.Browser.Tools do
  @moduledoc """
  Central entry point for browser automation tool calls.

  Validates tool permissions, resolves the sidecar worker, and dispatches
  the method call. Used by both LLM-tool-native adapters (via tool call handler)
  and the REST BrowserController (for bash-adapter agents).
  """
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.ToolPermission
  import Ecto.Query

  @browser_methods ~w(
    browser_navigate browser_navigate_back browser_snapshot
    browser_take_screenshot browser_click browser_mouse_click_xy
    browser_fill browser_type browser_hover browser_press_key
    browser_select browser_scroll browser_console_messages
    browser_network_requests browser_handle_dialog browser_tabs
    browser_eval browser_search browser_wait
  )

  @doc "Dispatch a browser tool call after permission check."
  @spec dispatch(String.t(), map(), String.t()) :: {:ok, term()} | {:error, term()}
  def dispatch(method, params, agent_id) when method in @browser_methods do
    case check_permission(agent_id) do
      :ok ->
        enriched_params = Map.put_new(params, "session_id", params["session_id"] || "default")
        Bizforge.Browser.Sidecar.call(method, enriched_params)

      {:error, _} = err ->
        err
    end
  end

  def dispatch(method, _params, _agent_id) do
    {:error, "Unknown browser method: #{method}"}
  end

  @doc "Return the list of available browser tool methods."
  @spec available_methods() :: [String.t()]
  def available_methods, do: @browser_methods

  @doc """
  Returns tool specifications for injection into LLM tool catalogs.
  Only call this after verifying the agent has browser_automation permission.
  """
  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      %{
        name: "browser_navigate",
        description: "Navigate to a URL",
        parameters: %{type: "object", properties: %{url: %{type: "string", description: "URL to navigate to"}}, required: ["url"]}
      },
      %{
        name: "browser_navigate_back",
        description: "Go back in browser history",
        parameters: %{type: "object", properties: %{}}
      },
      %{
        name: "browser_snapshot",
        description: "Get the current page accessibility tree snapshot (YAML). Use to inspect page structure and find element refs.",
        parameters: %{type: "object", properties: %{take_screenshot_afterwards: %{type: "boolean", description: "Also capture a screenshot"}}}
      },
      %{
        name: "browser_take_screenshot",
        description: "Take a screenshot of the current viewport",
        parameters: %{type: "object", properties: %{}}
      },
      %{
        name: "browser_click",
        description: "Click an element by CSS selector or ref",
        parameters: %{type: "object", properties: %{selector: %{type: "string"}, ref: %{type: "string"}}}
      },
      %{
        name: "browser_mouse_click_xy",
        description: "Click at specific x,y coordinates",
        parameters: %{type: "object", properties: %{x: %{type: "number"}, y: %{type: "number"}}, required: ["x", "y"]}
      },
      %{
        name: "browser_fill",
        description: "Clear and fill an input field",
        parameters: %{type: "object", properties: %{selector: %{type: "string"}, ref: %{type: "string"}, value: %{type: "string"}}, required: ["value"]}
      },
      %{
        name: "browser_type",
        description: "Type text (appends to current focus)",
        parameters: %{type: "object", properties: %{text: %{type: "string"}}, required: ["text"]}
      },
      %{
        name: "browser_hover",
        description: "Hover over an element",
        parameters: %{type: "object", properties: %{selector: %{type: "string"}, ref: %{type: "string"}}}
      },
      %{
        name: "browser_press_key",
        description: "Press a keyboard key (Enter, Tab, Escape, etc.)",
        parameters: %{type: "object", properties: %{key: %{type: "string"}}, required: ["key"]}
      },
      %{
        name: "browser_select",
        description: "Select an option from a dropdown",
        parameters: %{type: "object", properties: %{selector: %{type: "string"}, ref: %{type: "string"}, value: %{type: "string"}}, required: ["value"]}
      },
      %{
        name: "browser_scroll",
        description: "Scroll the page up or down",
        parameters: %{type: "object", properties: %{direction: %{type: "string", enum: ["up", "down"]}, amount: %{type: "number"}}}
      },
      %{
        name: "browser_console_messages",
        description: "Get recent browser console messages",
        parameters: %{type: "object", properties: %{}}
      },
      %{
        name: "browser_network_requests",
        description: "Get recent network requests",
        parameters: %{type: "object", properties: %{}}
      },
      %{
        name: "browser_handle_dialog",
        description: "Handle a browser dialog (alert/confirm/prompt)",
        parameters: %{type: "object", properties: %{accept: %{type: "boolean"}, promptText: %{type: "string"}}}
      },
      %{
        name: "browser_tabs",
        description: "List, create, switch, or close browser tabs",
        parameters: %{type: "object", properties: %{action: %{type: "string", enum: ["list", "new", "switch", "close"]}, tabId: %{type: "string"}}}
      },
      %{
        name: "browser_eval",
        description: "Evaluate a JavaScript expression in the page context",
        parameters: %{type: "object", properties: %{expression: %{type: "string"}}, required: ["expression"]}
      },
      %{
        name: "browser_search",
        description: "Search for text in the current page content",
        parameters: %{type: "object", properties: %{text: %{type: "string"}}, required: ["text"]}
      },
      %{
        name: "browser_wait",
        description: "Wait for a specified number of milliseconds",
        parameters: %{type: "object", properties: %{ms: %{type: "number"}}}
      }
    ]
  end

  @doc "Check if an agent has browser_automation tool permission."
  @spec has_permission?(String.t()) :: boolean()
  def has_permission?(agent_id) do
    check_permission(agent_id) == :ok
  end

  defp check_permission(agent_id) do
    exists =
      from(tp in ToolPermission,
        where: tp.agent_id == ^agent_id and tp.tool_name == "browser_automation" and tp.enabled == true
      )
      |> Repo.exists?()

    if exists, do: :ok, else: {:error, :permission_denied}
  end
end
