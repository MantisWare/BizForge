defmodule Bizforge.IntegrationResolver do
  @moduledoc """
  Resolves integration bindings for an agent by walking the inheritance chain.

  The lookup order is: agent -> team -> project. The first match wins,
  meaning agent-level bindings are the most specific (highest priority) and
  project-level bindings serve as the fallback (lowest priority).

  Returns resolved configs with encrypted secret values, ready for decryption
  and injection into the agent's session environment by the adapter layer.

  Future: skill-level bindings can override agent-level when skill context is
  available in the session.
  """

  import Ecto.Query
  alias Bizforge.Repo
  alias Bizforge.Schemas.{IntegrationBinding, Integration, IntegrationSecret, Secret}

  @type resolution :: %{
          provider: String.t(),
          integration_id: String.t(),
          integration_name: String.t(),
          config: map(),
          secrets: map(),
          config_overrides: map(),
          resolved_from: %{owner_type: String.t(), owner_id: String.t()}
        }
  # Note: `secrets` contains encrypted values keyed by name.
  # Decryption is handled by the adapter/session layer before injection.

  @doc """
  Resolves all integration bindings for a given agent, walking: agent -> team.
  Use `resolve_for_agent_in_project/2` to extend the chain with a project fallback.

  Returns `{:ok, resolutions}` or `{:error, {:missing_integrations, providers}}`.
  """
  @spec resolve_for_agent(map()) :: {:ok, [resolution()]} | {:error, term()}
  def resolve_for_agent(agent) do
    providers_needed = required_providers_for_agent(agent)

    resolutions =
      Enum.map(providers_needed, fn provider ->
        resolve_provider(provider, agent)
      end)

    missing = Enum.filter(resolutions, &(&1 === :unresolved))

    if Enum.empty?(missing) do
      {:ok, Enum.reject(resolutions, &(&1 === :unresolved))}
    else
      unresolved_providers =
        providers_needed
        |> Enum.zip(resolutions)
        |> Enum.filter(fn {_p, r} -> r === :unresolved end)
        |> Enum.map(fn {p, _r} -> p end)

      {:error, {:missing_integrations, unresolved_providers}}
    end
  end

  @doc """
  Resolves a single provider for an agent by checking the inheritance chain.
  """
  def resolve_provider(provider, agent) do
    chain = build_lookup_chain(agent)

    Enum.find_value(chain, :unresolved, fn {owner_type, owner_id} ->
      case find_binding(owner_type, owner_id, provider) do
        nil -> nil
        binding -> build_resolution(binding)
      end
    end)
  end

  defp build_lookup_chain(agent) do
    chain = [{"agent", agent.id}]

    chain =
      if agent.team_id !== nil do
        chain ++ [{"team", agent.team_id}]
      else
        chain
      end

    # Project-level lookup requires knowing which project the agent is working on.
    # This is session-contextual and passed separately when available.
    chain
  end

  @doc """
  Extends the lookup chain with a project context (for session-level resolution).
  """
  def resolve_for_agent_in_project(agent, project_id) do
    providers_needed = required_providers_for_agent(agent)

    chain =
      build_lookup_chain(agent) ++ [{"project", project_id}]

    resolutions =
      Enum.map(providers_needed, fn provider ->
        resolve_provider_with_chain(provider, chain)
      end)

    missing =
      providers_needed
      |> Enum.zip(resolutions)
      |> Enum.filter(fn {_p, r} -> r === :unresolved end)
      |> Enum.map(fn {p, _r} -> p end)

    if Enum.empty?(missing) do
      {:ok, Enum.reject(resolutions, &(&1 === :unresolved))}
    else
      {:error, {:missing_integrations, missing}}
    end
  end

  defp resolve_provider_with_chain(provider, chain) do
    Enum.find_value(chain, :unresolved, fn {owner_type, owner_id} ->
      case find_binding(owner_type, owner_id, provider) do
        nil -> nil
        binding -> build_resolution(binding)
      end
    end)
  end

  defp find_binding(owner_type, owner_id, provider) do
    IntegrationBinding
    |> where([b], b.owner_type == ^owner_type and b.owner_id == ^owner_id and b.provider == ^provider)
    |> where([b], b.enabled == true)
    |> Repo.one()
  end

  defp build_resolution(binding) do
    case Repo.get(Integration, binding.integration_id) do
      nil ->
        :unresolved

      integration ->
        secrets = fetch_secrets(binding.integration_id)

        %{
          provider: binding.provider,
          integration_id: integration.id,
          integration_name: integration.name,
          config: integration.config,
          secrets: secrets,
          config_overrides: binding.config_overrides,
          resolved_from: %{owner_type: binding.owner_type, owner_id: binding.owner_id}
        }
    end
  end

  defp fetch_secrets(integration_id) do
    IntegrationSecret
    |> where([is], is.integration_id == ^integration_id)
    |> join(:inner, [is], s in Secret, on: is.secret_id == s.id)
    |> select([is, s], {is.key, s.encrypted_value})
    |> Repo.all()
    |> Map.new()
  end

  defp required_providers_for_agent(agent) do
    agent = Repo.preload(agent, :skills)
    skills = agent.skills || []

    providers_from_skills =
      Enum.flat_map(skills, fn skill ->
        extract_providers_from_skill(skill)
      end)

    providers_from_bindings =
      IntegrationBinding
      |> where([b], b.owner_type == "agent" and b.owner_id == ^agent.id)
      |> select([b], b.provider)
      |> Repo.all()

    (providers_from_skills ++ providers_from_bindings)
    |> Enum.uniq()
  end

  defp extract_providers_from_skill(skill) do
    case skill.trigger_rules do
      %{"required_integrations" => integrations} when is_list(integrations) ->
        Enum.map(integrations, fn
          %{"provider" => provider} -> provider
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end
end
