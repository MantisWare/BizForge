defmodule BizforgeWeb.PhaseController do
  use BizforgeWeb, :controller
  require Logger

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Phase, Task}
  import Ecto.Query

  def index(conn, params) do
    workspace_id = params["workspace_id"]
    project_id = params["project_id"]

    query = from p in Phase, order_by: [asc: p.title]

    query =
      if workspace_id,
        do: where(query, [p], p.workspace_id == ^workspace_id),
        else: query

    query =
      if project_id,
        do: where(query, [p], p.project_id == ^project_id),
        else: query

    phases = Repo.all(query)
    json(conn, %{phases: Enum.map(phases, &serialize/1)})
  end

  def create(conn, params) do
    changeset = Phase.changeset(%Phase{}, params)

    case Repo.insert(changeset) do
      {:ok, phase} ->
        conn |> put_status(201) |> json(%{phase: serialize(phase)})

      {:error, cs} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(cs)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Phase, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      phase ->
        task_count = Repo.aggregate(from(t in Task, where: t.phase_id == ^id), :count)
        children = Repo.all(from(p in Phase, where: p.parent_id == ^id))

        json(conn, %{
          phase:
            serialize(phase)
            |> Map.put(:task_count, task_count)
            |> Map.put(:children, Enum.map(children, &serialize/1))
        })
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Repo.get(Phase, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      phase ->
        changeset = Phase.changeset(phase, params)

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{phase: serialize(updated)})

          {:error, cs} ->
            conn
            |> put_status(422)
            |> json(%{error: "validation_failed", details: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Repo.get(Phase, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      phase ->
        Repo.delete!(phase)
        json(conn, %{ok: true})
    end
  end

  def ancestry(conn, %{"phase_id" => id}) do
    case Repo.get(Phase, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      phase ->
        chain = build_ancestry(phase, [], 20, MapSet.new())
        json(conn, %{ancestry: chain})
    end
  end

  def decompose(conn, %{"phase_id" => phase_id} = params) do
    max_tasks =
      case Integer.parse(params["max_tasks"] || "10") do
        {n, ""} when n in 1..50 -> n
        _ -> 10
      end

    opts = [
      max_tasks: max_tasks,
      auto_assign: params["auto_assign"] not in [false, "false"]
    ]

    case Repo.get(Phase, phase_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Phase not found"})

      _phase ->
        Elixir.Task.Supervisor.start_child(Bizforge.TaskSupervisor, fn ->
          case Bizforge.PhaseDecomposer.decompose(phase_id, opts) do
            {:ok, tasks} ->
              phase = Repo.get(Phase, phase_id)

              if phase do
                Bizforge.EventBus.broadcast(
                  Bizforge.EventBus.workspace_topic(phase.workspace_id),
                  %{
                    event: "phase.decomposed",
                    phase_id: phase_id,
                    task_count: length(tasks),
                    task_ids: Enum.map(tasks, & &1.id)
                  }
                )
              end

            {:error, reason} ->
              Logger.warning(
                "[PhaseDecomposer] Async decompose failed for #{phase_id}: #{to_string(reason)}"
              )
          end
        end)

        conn
        |> put_status(202)
        |> json(%{
          status: "accepted",
          phase_id: phase_id,
          message: "Decomposition started. Tasks will appear when ready."
        })
    end
  end

  defp build_ancestry(%Phase{parent_id: nil} = phase, acc, _depth, _visited) do
    [serialize(phase) | acc]
  end

  defp build_ancestry(_phase, acc, 0, _visited), do: acc

  defp build_ancestry(%Phase{parent_id: parent_id} = phase, acc, depth, visited) do
    if MapSet.member?(visited, phase.id) do
      acc
    else
      new_visited = MapSet.put(visited, phase.id)

      case Repo.get(Phase, parent_id) do
        nil -> [serialize(phase) | acc]
        parent -> build_ancestry(parent, [serialize(phase) | acc], depth - 1, new_visited)
      end
    end
  end

  defp serialize(%Phase{} = p) do
    %{
      id: p.id,
      title: p.title,
      description: p.description,
      status: p.status,
      workspace_id: p.workspace_id,
      project_id: p.project_id,
      parent_id: p.parent_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end

  defp serialize(%Task{} = t) do
    %{
      id: t.id,
      title: t.title,
      description: t.description,
      status: t.status,
      priority: t.priority,
      workspace_id: t.workspace_id,
      project_id: t.project_id,
      phase_id: t.phase_id,
      assignee_id: t.assignee_id,
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
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
