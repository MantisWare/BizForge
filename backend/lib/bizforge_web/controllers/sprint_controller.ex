defmodule BizforgeWeb.SprintController do
  @moduledoc "CRUD and lifecycle management for project sprints."
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Sprint, Issue}
  import Ecto.Query

  def index(conn, params) do
    project_id = params["project_id"]
    workspace_id = conn.assigns[:workspace_id]

    query = from s in Sprint, order_by: [desc: s.start_date]
    query = if project_id, do: where(query, [s], s.project_id == ^project_id), else: query
    query = if workspace_id, do: where(query, [s], s.workspace_id == ^workspace_id), else: query

    sprints = Repo.all(query)

    sprints_with_counts =
      Enum.map(sprints, fn sprint ->
        issue_count = Repo.aggregate(from(i in Issue, where: i.sprint_id == ^sprint.id), :count)
        done_count = Repo.aggregate(from(i in Issue, where: i.sprint_id == ^sprint.id and i.status == "done"), :count)

        serialize(sprint)
        |> Map.put(:issue_count, issue_count)
        |> Map.put(:done_count, done_count)
      end)

    json(conn, %{sprints: sprints_with_counts})
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Sprint, id) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      sprint -> json(conn, %{sprint: serialize(sprint)})
    end
  end

  def create(conn, params) do
    workspace_id = conn.assigns[:workspace_id] || params["workspace_id"]

    attrs =
      params
      |> Map.take(~w(name goal start_date end_date velocity_target project_id config))
      |> Map.put("workspace_id", workspace_id)

    case %Sprint{} |> Sprint.changeset(attrs) |> Repo.insert() do
      {:ok, sprint} ->
        conn |> put_status(201) |> json(%{sprint: serialize(sprint)})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: "validation_failed", details: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Repo.get(Sprint, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      sprint ->
        attrs = Map.take(params, ~w(name goal start_date end_date status velocity_target velocity_actual config))

        case sprint |> Sprint.changeset(attrs) |> Repo.update() do
          {:ok, updated} ->
            json(conn, %{sprint: serialize(updated)})

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: "validation_failed", details: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Repo.get(Sprint, id) do
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
      sprint ->
        Repo.delete!(sprint)
        json(conn, %{ok: true})
    end
  end

  @doc "Start a sprint — transitions from planned to active."
  def start(conn, %{"sprint_id" => id}) do
    case Repo.get(Sprint, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      %Sprint{status: "planned"} = sprint ->
        {:ok, updated} = sprint |> Sprint.changeset(%{"status" => "active", "start_date" => Date.utc_today()}) |> Repo.update()
        json(conn, %{sprint: serialize(updated)})

      %Sprint{status: status} ->
        conn |> put_status(422) |> json(%{error: "invalid_transition", current_status: status})
    end
  end

  @doc "Complete a sprint — transitions from active to complete, calculates velocity."
  def complete(conn, %{"sprint_id" => id}) do
    case Repo.get(Sprint, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      %Sprint{status: "active"} = sprint ->
        done_count = Repo.aggregate(from(i in Issue, where: i.sprint_id == ^sprint.id and i.status == "done"), :count)

        {:ok, updated} =
          sprint
          |> Sprint.changeset(%{
            "status" => "complete",
            "end_date" => Date.utc_today(),
            "velocity_actual" => done_count
          })
          |> Repo.update()

        json(conn, %{sprint: serialize(updated), velocity: done_count})

      %Sprint{status: status} ->
        conn |> put_status(422) |> json(%{error: "invalid_transition", current_status: status})
    end
  end

  @doc "Assign issues to a sprint."
  def assign_issues(conn, %{"sprint_id" => sprint_id} = params) do
    issue_ids = params["issue_ids"] || []

    case Repo.get(Sprint, sprint_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "sprint_not_found"})

      _sprint ->
        {count, _} =
          Repo.update_all(
            from(i in Issue, where: i.id in ^issue_ids),
            set: [sprint_id: sprint_id]
          )

        json(conn, %{ok: true, assigned: count})
    end
  end

  @doc "Remove issues from a sprint."
  def unassign_issues(conn, %{"sprint_id" => sprint_id} = params) do
    issue_ids = params["issue_ids"] || []

    {count, _} =
      Repo.update_all(
        from(i in Issue, where: i.id in ^issue_ids and i.sprint_id == ^sprint_id),
        set: [sprint_id: nil]
      )

    json(conn, %{ok: true, unassigned: count})
  end

  defp serialize(%Sprint{} = s) do
    %{
      id: s.id,
      name: s.name,
      goal: s.goal,
      start_date: s.start_date,
      end_date: s.end_date,
      status: s.status,
      velocity_target: s.velocity_target,
      velocity_actual: s.velocity_actual,
      config: s.config,
      project_id: s.project_id,
      workspace_id: s.workspace_id,
      created_at: s.inserted_at,
      updated_at: s.updated_at
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
