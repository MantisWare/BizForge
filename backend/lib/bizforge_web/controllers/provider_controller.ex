defmodule BizforgeWeb.ProviderController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.Provider
  import Ecto.Query

  def index(conn, params) do
    query =
      from(p in Provider, order_by: [desc: p.is_default, asc: p.inserted_at])

    query =
      case params["workspace_id"] do
        nil -> query
        ws_id -> from(p in query, where: p.workspace_id == ^ws_id)
      end

    providers = Repo.all(query)
    json(conn, %{providers: Enum.map(providers, &serialize/1)})
  end

  def create(conn, params) do
    changeset = Provider.changeset(%Provider{}, params)

    case Repo.insert(changeset) do
      {:ok, provider} ->
        if provider.is_default do
          clear_other_defaults(provider.id, provider.workspace_id)
        end

        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.activity_topic(),
          %{event: "provider.added", provider_id: provider.id, slug: provider.slug}
        )

        conn |> put_status(201) |> json(%{provider: serialize(provider)})

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Provider, id) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      provider -> json(conn, %{provider: serialize(provider)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Repo.get(Provider, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      provider ->
        changeset = Provider.changeset(provider, params)

        case Repo.update(changeset) do
          {:ok, updated} ->
            if updated.is_default do
              clear_other_defaults(updated.id, updated.workspace_id)
            end

            json(conn, %{provider: serialize(updated)})

          {:error, cs} ->
            conn
            |> put_status(422)
            |> json(%{error: "validation_failed", details: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Repo.get(Provider, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      provider ->
        Repo.delete!(provider)

        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.activity_topic(),
          %{event: "provider.removed", provider_id: id}
        )

        json(conn, %{ok: true})
    end
  end

  def test(conn, %{"provider_id" => id}) do
    case Repo.get(Provider, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      provider ->
        result = perform_test(provider)

        changes = %{
          status: result.status,
          last_tested_at: DateTime.utc_now(),
          error_message: result[:error_message]
        }

        changes =
          if result.status == "connected" and result[:models] != [] do
            Map.put(changes, :models, result[:models] || [])
          else
            changes
          end

        case provider |> Ecto.Changeset.change(changes) |> Repo.update() do
          {:ok, updated} ->
            json(conn, %{
              provider: serialize(updated),
              test_result: %{
                status: result.status,
                latency_ms: result[:latency_ms],
                models: result[:models] || [],
                error_message: result[:error_message]
              }
            })

          {:error, _changeset} ->
            conn |> put_status(500) |> json(%{error: "update_failed"})
        end
    end
  end

  defp perform_test(%Provider{} = provider) do
    endpoint = resolve_endpoint(provider)
    start_ms = System.monotonic_time(:millisecond)

    test_result =
      case provider.category do
        "local" -> test_local(endpoint, provider.api_key)
        _ -> test_cloud(endpoint, provider.slug, provider.api_key)
      end

    elapsed_ms = System.monotonic_time(:millisecond) - start_ms

    case test_result do
      {:ok, models} ->
        %{status: "connected", latency_ms: elapsed_ms, models: models}

      {:error, reason} ->
        %{status: "error", latency_ms: elapsed_ms, models: [], error_message: reason}
    end
  end

  defp test_local(endpoint, api_key) do
    url = String.trim_trailing(endpoint, "/") <> "/v1/models"
    headers = build_bearer_headers(api_key)

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: code, body: body}} when code in 200..299 ->
        models = extract_model_ids(body)
        {:ok, models}

      {:ok, %{status: code}} ->
        {:error, "Endpoint returned HTTP #{code}"}

      {:error, %{reason: reason}} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  defp test_cloud(endpoint, slug, api_key) do
    {url, headers} = build_test_request(endpoint, slug, api_key)

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: code, body: body}} when code in 200..299 ->
        models = extract_model_ids(body)
        {:ok, models}

      {:ok, %{status: 401}} ->
        {:error, "Authentication failed — check your API key"}

      {:ok, %{status: 403}} ->
        {:error, "Access denied — verify API key permissions"}

      {:ok, %{status: code}} ->
        {:error, "Endpoint returned HTTP #{code}"}

      {:error, %{reason: reason}} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  defp build_test_request(endpoint, slug, api_key) do
    base = String.trim_trailing(endpoint || "", "/")

    case slug do
      "anthropic" ->
        {base <> "/v1/models", [{"x-api-key", api_key || ""}, {"anthropic-version", "2023-06-01"}]}

      _ ->
        {base <> "/v1/models", build_bearer_headers(api_key)}
    end
  end

  defp resolve_endpoint(%Provider{category: "local", config: config}) when is_map(config) do
    Map.get(config, "local_endpoint") ||
      Map.get(config, :local_endpoint) ||
      "http://localhost:11434"
  end

  defp resolve_endpoint(%Provider{endpoint: endpoint}) when is_binary(endpoint) and endpoint != "" do
    endpoint
  end

  defp resolve_endpoint(_), do: "http://localhost:11434"

  defp extract_model_ids(body) when is_map(body) do
    case body do
      %{"data" => data} when is_list(data) ->
        Enum.map(data, fn m -> m["id"] || m["name"] || "" end)
        |> Enum.filter(&(&1 != ""))

      %{"models" => models} when is_list(models) ->
        Enum.map(models, fn m -> m["name"] || m["model"] || m["id"] || "" end)
        |> Enum.filter(&(&1 != ""))

      _ ->
        []
    end
  end

  defp extract_model_ids(_), do: []

  defp build_bearer_headers(nil), do: []
  defp build_bearer_headers(""), do: []
  defp build_bearer_headers(key), do: [{"authorization", "Bearer #{key}"}]

  defp clear_other_defaults(current_id, workspace_id) do
    query =
      from(p in Provider,
        where: p.id != ^current_id and p.is_default == true
      )

    query =
      if workspace_id do
        from(p in query, where: p.workspace_id == ^workspace_id)
      else
        query
      end

    Repo.update_all(query, set: [is_default: false])
  end

  defp serialize(%Provider{} = p) do
    %{
      id: p.id,
      slug: p.slug,
      name: p.name,
      category: p.category,
      api_key_set: p.api_key != nil and p.api_key != "",
      endpoint: p.endpoint,
      config: p.config || %{},
      models: p.models || [],
      is_default: p.is_default,
      status: p.status,
      last_tested_at: p.last_tested_at,
      error_message: p.error_message,
      workspace_id: p.workspace_id,
      created_at: p.inserted_at,
      updated_at: p.updated_at
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
