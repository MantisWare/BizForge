defmodule BizforgeWeb.IntegrationController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.Integration
  import Ecto.Query

  def index(conn, params) do
    workspace_id = params["workspace_id"]

    query = from i in Integration, order_by: [asc: i.category, asc: i.name]
    query = if workspace_id, do: where(query, [i], i.workspace_id == ^workspace_id), else: query

    integrations = Repo.all(query)

    json(conn, %{integrations: Enum.map(integrations, &serialize/1)})
  end

  def connect(conn, %{"slug" => slug} = params) do
    workspace_id = params["workspace_id"]
    config = params["config"] || %{}

    existing =
      if workspace_id do
        Repo.one(
          from i in Integration, where: i.slug == ^slug and i.workspace_id == ^workspace_id
        )
      else
        Repo.one(from i in Integration, where: i.slug == ^slug, limit: 1)
      end

    result =
      case existing do
        nil ->
          attrs =
            Map.merge(params, %{
              "slug" => slug,
              "connected" => true,
              "config" => config
            })

          Integration.changeset(%Integration{}, attrs) |> Repo.insert()

        integration ->
          integration
          |> Integration.changeset(%{
            "connected" => true,
            "config" => Map.merge(integration.config || %{}, config)
          })
          |> Repo.update()
      end

    case result do
      {:ok, integration} ->
        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.workspace_topic(integration.workspace_id),
          %{event: "integration.connected", slug: slug, name: integration.name}
        )

        json(conn, %{integration: serialize(integration)})

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(changeset)})
    end
  end

  def disconnect(conn, %{"slug" => slug} = params) do
    workspace_id = params["workspace_id"]

    query = from i in Integration, where: i.slug == ^slug
    query = if workspace_id, do: where(query, [i], i.workspace_id == ^workspace_id), else: query

    case Repo.one(query) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      integration ->
        case integration
             |> Ecto.Changeset.change(connected: false)
             |> Repo.update() do
          {:ok, updated} ->
            Bizforge.EventBus.broadcast(
              Bizforge.EventBus.workspace_topic(updated.workspace_id),
              %{event: "integration.disconnected", slug: slug}
            )

            json(conn, %{integration: serialize(updated)})

          {:error, _changeset} ->
            conn |> put_status(500) |> json(%{error: "update_failed"})
        end
    end
  end

  def status(conn, %{"slug" => slug} = params) do
    workspace_id = params["workspace_id"]

    query = from i in Integration, where: i.slug == ^slug
    query = if workspace_id, do: where(query, [i], i.workspace_id == ^workspace_id), else: query

    case Repo.one(query) do
      nil ->
        json(conn, %{slug: slug, connected: false, status: "not_configured"})

      integration ->
        json(conn, %{
          slug: slug,
          connected: integration.connected,
          status: if(integration.connected, do: "connected", else: "disconnected"),
          last_synced_at: integration.last_synced_at
        })
    end
  end

  def connect_slack(conn, params) do
    workspace_id = params["workspace_id"]
    bot_token = params["bot_token"]
    signing_secret = params["signing_secret"]
    default_agent_id = params["default_agent_id"]
    channel_mappings = params["channel_mappings"] || %{}
    team_name = params["team_name"] || "Slack Workspace"

    attrs = %{
      workspace_id: workspace_id,
      bot_token: bot_token,
      signing_secret: signing_secret,
      default_agent_id: default_agent_id,
      channel_mappings: channel_mappings,
      team_name: team_name,
      active: true
    }

    existing =
      Repo.one(
        from s in Bizforge.Schemas.SlackInstallation,
          where: s.workspace_id == ^workspace_id and s.active == true,
          limit: 1
      )

    result =
      case existing do
        nil ->
          Bizforge.Schemas.SlackInstallation.changeset(
            %Bizforge.Schemas.SlackInstallation{},
            attrs
          )
          |> Repo.insert()

        installation ->
          Bizforge.Schemas.SlackInstallation.changeset(installation, attrs)
          |> Repo.update()
      end

    case result do
      {:ok, installation} ->
        json(conn, %{
          ok: true,
          slack_installation: %{
            id: installation.id,
            team_name: installation.team_name,
            active: installation.active,
            channel_mappings: installation.channel_mappings,
            default_agent_id: installation.default_agent_id
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(changeset)})
    end
  end

  def disconnect_slack(conn, params) do
    workspace_id = params["workspace_id"]

    query =
      from s in Bizforge.Schemas.SlackInstallation,
        where: s.workspace_id == ^workspace_id and s.active == true

    {count, _} = Repo.update_all(query, set: [active: false])

    json(conn, %{ok: true, deactivated: count})
  end

  def slack_status(conn, params) do
    workspace_id = params["workspace_id"]

    installation =
      Repo.one(
        from s in Bizforge.Schemas.SlackInstallation,
          where: s.workspace_id == ^workspace_id and s.active == true,
          limit: 1
      )

    case installation do
      nil ->
        json(conn, %{connected: false, status: "not_configured"})

      inst ->
        json(conn, %{
          connected: true,
          status: "connected",
          team_name: inst.team_name,
          channel_mappings: inst.channel_mappings,
          default_agent_id: inst.default_agent_id
        })
    end
  end

  def pull_all(conn, params) do
    workspace_id = params["workspace_id"]

    # Placeholder — future: trigger sync for all connected integrations
    query = from i in Integration, where: i.connected == true
    query = if workspace_id, do: where(query, [i], i.workspace_id == ^workspace_id), else: query

    connected = Repo.all(query)

    # Update last_synced_at as a no-op sync signal
    now = DateTime.utc_now()
    ids = Enum.map(connected, & &1.id)

    Repo.update_all(
      from(i in Integration, where: i.id in ^ids),
      set: [last_synced_at: now]
    )

    json(conn, %{
      ok: true,
      synced: length(connected),
      note: "Full sync not yet implemented"
    })
  end

  defp serialize(%Integration{} = i) do
    %{
      id: i.id,
      slug: i.slug,
      name: i.name,
      category: i.category,
      connected: i.connected,
      status: if(i.connected, do: "connected", else: "disconnected"),
      last_synced_at: i.last_synced_at,
      workspace_id: i.workspace_id,
      inserted_at: i.inserted_at,
      updated_at: i.updated_at
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
