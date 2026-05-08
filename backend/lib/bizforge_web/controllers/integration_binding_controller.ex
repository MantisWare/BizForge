defmodule BizforgeWeb.IntegrationBindingController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{IntegrationBinding, Integration}
  alias Bizforge.IntegrationResolver
  import Ecto.Query

  defp allowed_workspace_ids(conn) do
    conn.assigns[:user_workspace_ids] || []
  end

  defp scope_to_workspaces(query, workspace_ids) when workspace_ids == [], do: query

  defp scope_to_workspaces(query, workspace_ids) do
    from b in query,
      join: i in Integration,
      on: i.id == b.integration_id,
      where: i.workspace_id in ^workspace_ids
  end

  def index(conn, params) do
    owner_type = params["owner_type"]
    owner_id = params["owner_id"]
    workspace_ids = allowed_workspace_ids(conn)

    query =
      from b in IntegrationBinding,
        preload: [:integration],
        order_by: [asc: b.provider]

    query = scope_to_workspaces(query, workspace_ids)

    query =
      cond do
        owner_type != nil and owner_id != nil ->
          where(query, [b], b.owner_type == ^owner_type and b.owner_id == ^owner_id)

        owner_type != nil ->
          where(query, [b], b.owner_type == ^owner_type)

        true ->
          query
      end

    bindings = Repo.all(query)
    json(conn, %{bindings: Enum.map(bindings, &serialize/1)})
  end

  def create(conn, params) do
    workspace_ids = allowed_workspace_ids(conn)
    integration_id = params["integration_id"]

    integration = Repo.get(Integration, integration_id)

    cond do
      integration == nil ->
        conn |> put_status(404) |> json(%{error: "integration_not_found"})

      workspace_ids != [] and integration.workspace_id not in workspace_ids ->
        conn |> put_status(403) |> json(%{error: "forbidden", message: "Integration belongs to another workspace"})

      integration.provider != params["provider"] ->
        conn
        |> put_status(422)
        |> json(%{error: "provider_mismatch", message: "Submitted provider does not match integration's provider"})

      true ->
        attrs = %{
          "owner_type" => params["owner_type"],
          "owner_id" => params["owner_id"],
          "provider" => params["provider"],
          "integration_id" => integration_id,
          "config_overrides" => params["config_overrides"] || %{},
          "enabled" => Map.get(params, "enabled", true)
        }

        case IntegrationBinding.changeset(%IntegrationBinding{}, attrs) |> Repo.insert() do
          {:ok, binding} ->
            binding = Repo.preload(binding, :integration)
            conn |> put_status(201) |> json(%{binding: serialize(binding)})

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> json(%{error: "validation_failed", details: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    workspace_ids = allowed_workspace_ids(conn)

    query =
      from b in IntegrationBinding,
        join: i in Integration, on: i.id == b.integration_id,
        where: b.id == ^id,
        select: b

    query =
      if workspace_ids != [] do
        where(query, [b, i], i.workspace_id in ^workspace_ids)
      else
        query
      end

    case Repo.one(query) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      binding ->
        case Repo.delete(binding) do
          {:ok, _} -> json(conn, %{ok: true})
          {:error, _} -> conn |> put_status(500) |> json(%{error: "delete_failed"})
        end
    end
  end

  def delete_by_owner(conn, %{"owner_type" => owner_type, "owner_id" => owner_id, "provider" => provider}) do
    workspace_ids = allowed_workspace_ids(conn)

    query =
      from b in IntegrationBinding,
        join: i in Integration, on: i.id == b.integration_id,
        where: b.owner_type == ^owner_type and b.owner_id == ^owner_id and b.provider == ^provider,
        select: b

    query =
      if workspace_ids != [] do
        where(query, [b, i], i.workspace_id in ^workspace_ids)
      else
        query
      end

    case Repo.one(query) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      binding ->
        case Repo.delete(binding) do
          {:ok, _} -> json(conn, %{ok: true})
          {:error, _} -> conn |> put_status(500) |> json(%{error: "delete_failed"})
        end
    end
  end

  def resolve(conn, %{"agent_id" => agent_id}) do
    agent = Repo.get(Bizforge.Schemas.Agent, agent_id)

    case agent do
      nil ->
        conn |> put_status(404) |> json(%{error: "agent_not_found"})

      agent ->
        case IntegrationResolver.resolve_for_agent(agent) do
          {:ok, resolutions} ->
            json(conn, %{
              agent_id: agent_id,
              resolutions: Enum.map(resolutions, &serialize_resolution/1)
            })

          {:error, {:missing_integrations, providers}} ->
            conn
            |> put_status(422)
            |> json(%{
              error: "missing_integrations",
              missing_providers: providers,
              agent_id: agent_id
            })

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "resolution_failed", reason: inspect(reason)})
        end
    end
  end

  defp serialize(%IntegrationBinding{} = b) do
    integration = b.integration

    %{
      id: b.id,
      owner_type: b.owner_type,
      owner_id: b.owner_id,
      provider: b.provider,
      integration_id: b.integration_id,
      integration_name: if(integration, do: integration.name, else: nil),
      integration_status: if(integration && integration.connected, do: "connected", else: "disconnected"),
      config_overrides: b.config_overrides,
      enabled: b.enabled,
      inherited_from: nil,
      created_at: b.inserted_at
    }
  end

  defp serialize_resolution(resolution) do
    %{
      provider: resolution.provider,
      integration_id: resolution.integration_id,
      integration_name: resolution.integration_name,
      config: resolution.config,
      config_overrides: resolution.config_overrides,
      resolved_from: resolution.resolved_from
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
