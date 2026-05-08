defmodule Bizforge.Dispatch.SkillRouter do
  @moduledoc """
  Skill-aware issue assignment router.

  Scores candidate agents by skill overlap with the issue's labels and keywords,
  factoring in load (active sessions) and team membership affinity.

  Priority chain:
    1. Same team, skill match, lowest load
    2. Same project team, skill match
    3. Workspace-wide, skill match
    4. Fallback to adapter-based routing (Delegation.find_agent_for_adapter)
  """

  require Logger
  import Ecto.Query

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Agent, Session, Issue}

  @doc """
  Choose the best agent for an issue within a workspace.

  Options:
    - `:team_id` — prefer agents in this team (optional)
    - `:project_id` — expand to project-bound teams (optional)
    - `:exclude_ids` — agent IDs to skip (e.g. the delegator)

  Returns `{:ok, agent_id}` or `{:error, :no_match}`.
  """
  @spec choose(Issue.t() | map(), keyword()) :: {:ok, String.t()} | {:error, :no_match}
  def choose(issue, opts \\ []) do
    workspace_id = issue.workspace_id
    team_id = opts[:team_id]
    project_id = opts[:project_id] || issue.project_id
    exclude_ids = opts[:exclude_ids] || []

    keywords = extract_keywords(issue)

    candidates =
      from(a in Agent,
        where: a.workspace_id == ^workspace_id and a.status in ["idle", "active"],
        where: a.id not in ^exclude_ids,
        preload: [:skills]
      )
      |> Repo.all()

    scored =
      candidates
      |> Enum.map(fn agent ->
        skill_names = Enum.map(agent.skills || [], & &1.name)
        overlap = skill_overlap_score(keywords, skill_names)
        load = active_session_count(agent.id)
        team_bonus = team_affinity(agent, team_id, project_id)

        score = overlap * 10.0 + team_bonus * 5.0 - load * 2.0

        {agent.id, score, overlap}
      end)
      |> Enum.filter(fn {_id, _score, overlap} -> overlap > 0 end)
      |> Enum.sort_by(fn {_id, score, _} -> score end, :desc)

    case scored do
      [{agent_id, _score, _overlap} | _] ->
        Logger.info("[SkillRouter] Assigned issue #{issue.id} to agent #{agent_id}")
        {:ok, agent_id}

      [] ->
        Logger.debug("[SkillRouter] No skill match found for issue #{issue.id}, trying adapter fallback")
        {:error, :no_match}
    end
  end

  @doc "Extract keywords from issue title, description, and labels for matching."
  @spec extract_keywords(map()) :: [String.t()]
  def extract_keywords(issue) do
    text_parts = [
      issue.title || "",
      issue.description || ""
    ]

    label_names =
      case issue do
        %{labels: labels} when is_list(labels) ->
          Enum.map(labels, fn
            %{name: name} -> name
            name when is_binary(name) -> name
            _ -> ""
          end)
        _ ->
          []
      end

    text = Enum.join(text_parts ++ label_names, " ") |> String.downcase()

    @keyword_to_skill_map
    |> Enum.filter(fn {keyword, _skill} ->
      String.contains?(text, keyword)
    end)
    |> Enum.map(fn {_keyword, skill} -> skill end)
    |> Enum.uniq()
  end

  defp skill_overlap_score(issue_skills, agent_skills) do
    agent_set = MapSet.new(agent_skills)
    issue_skills
    |> Enum.count(fn s -> MapSet.member?(agent_set, s) end)
    |> Kernel./(max(length(issue_skills), 1))
  end

  defp active_session_count(agent_id) do
    Repo.aggregate(
      from(s in Session, where: s.agent_id == ^agent_id and s.status == "active"),
      :count
    )
  end

  defp team_affinity(agent, preferred_team_id, project_id) do
    cond do
      preferred_team_id !== nil && agent.team_id == preferred_team_id -> 2.0
      project_id !== nil && agent_in_project_team?(agent.id, project_id) -> 1.0
      true -> 0.0
    end
  end

  defp agent_in_project_team?(_agent_id, nil), do: false

  defp agent_in_project_team?(agent_id, _project_id) do
    # For now a simple check: agent has a team_id set (full project-team binding comes in Phase 7)
    case Repo.get(Agent, agent_id) do
      %Agent{team_id: tid} when not is_nil(tid) -> true
      _ -> false
    end
  end

  @keyword_to_skill_map [
    {"appdb", "domo/appdb-manage"},
    {"app db", "domo/appdb-manage"},
    {"collection", "domo/appdb-manage"},
    {"dataflow", "domo/magic-etl"},
    {"etl", "domo/magic-etl"},
    {"magic etl", "domo/magic-etl"},
    {"connector", "domo/connector-build"},
    {"dataset", "domo/dataset-manage"},
    {"data set", "domo/dataset-manage"},
    {"stream api", "domo/dataset-manage"},
    {"pdp", "domo/governance"},
    {"governance", "domo/governance"},
    {"sso", "domo/governance"},
    {"audit", "domo/governance"},
    {"beast mode", "domo/dataset-manage"},
    {"code engine", "domo/code-engine"},
    {"codeengine", "domo/code-engine"},
    {"serverless", "domo/code-engine"},
    {"workflow", "domo/workflow-automate"},
    {"embed", "domo/embed-analytics"},
    {"embed analytics", "domo/embed-analytics"},
    {"token auth", "domo/embed-analytics"},
    {"manifest", "domo/app-scaffold"},
    {"domo app", "domo/app-scaffold"},
    {"da new", "domo/app-scaffold"},
    {"proxyid", "domo/app-scaffold"},
    {"proxy id", "domo/app-scaffold"},
    {"domo publish", "domo/app-publish"},
    {"publish app", "domo/app-publish"},
    {"api integrate", "domo/api-integrate"},
    {"oauth", "domo/api-integrate"},
    {"developer token", "domo/api-integrate"},
    {"data science", "domo/data-science"},
    {"jupyter", "domo/data-science"},
    {"automl", "domo/data-science"},
    {"instance admin", "domo/instance-admin"},
    {"user provision", "domo/instance-admin"},
    {"group manage", "domo/instance-admin"},
    {"test", "development/test"},
    {"unit test", "development/test"},
    {"integration test", "development/test"},
    {"qa", "qa/automate"},
    {"quality assurance", "qa/automate"},
    {"e2e", "qa/automate"},
    {"playwright", "qa/automate"},
    {"browser test", "browser/automation"},
    {"ui test", "browser/automation"},
    {"screenshot", "browser/automation"},
    {"functional test", "qa/automate"},
    {"startup", "qa/startup-probe"},
    {"start app", "qa/startup-probe"},
    {"deploy", "operations/deploy"},
    {"ci/cd", "operations/deploy"},
    {"docker", "operations/deploy"},
    {"kubernetes", "operations/deploy"},
    {"frontend", "development/code"},
    {"ui component", "development/code"},
    {"backend", "development/code"},
    {"api endpoint", "development/code"},
    {"database", "development/code"},
    {"schema", "development/code"},
    {"review", "development/code-review"},
    {"code review", "development/code-review"},
    {"refactor", "development/code"},
    {"documentation", "development/code"},
    {"sprint", "coordination/sprint-planning"},
    {"planning", "coordination/sprint-planning"},
    {"delegate", "coordination/delegate"},
    {"security", "security/audit"},
    {"vulnerability", "security/audit"},
    {"performance", "analysis/stats"},
    {"benchmark", "analysis/stats"},
  ]
end
