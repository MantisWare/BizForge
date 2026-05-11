defmodule BizforgeWeb.TaskController do
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Comment, Agent, Label, IssueLabel}
  import Ecto.Query

  def index(conn, params) do
    limit = min(String.to_integer(params["limit"] || "50"), 100)
    offset = String.to_integer(params["offset"] || "0")

    workspace_id = params["workspace_id"]
    status = params["status"]
    priority = params["priority"]
    project_id = params["project_id"]
    assignee_id = params["assignee_id"]
    phase_id = params["phase_id"]

    query =
      from t in Task,
        order_by: [desc: t.updated_at],
        limit: ^limit,
        offset: ^offset

    query = if workspace_id, do: where(query, [t], t.workspace_id == ^workspace_id), else: query
    query = if status, do: where(query, [t], t.status == ^status), else: query
    query = if priority, do: where(query, [t], t.priority == ^priority), else: query
    query = if project_id, do: where(query, [t], t.project_id == ^project_id), else: query
    query = if assignee_id, do: where(query, [t], t.assignee_id == ^assignee_id), else: query
    query = if phase_id, do: where(query, [t], t.phase_id == ^phase_id), else: query

    count_query = from(t in Task)
    count_query = if workspace_id, do: where(count_query, [t], t.workspace_id == ^workspace_id), else: count_query
    count_query = if status, do: where(count_query, [t], t.status == ^status), else: count_query
    count_query = if priority, do: where(count_query, [t], t.priority == ^priority), else: count_query
    count_query = if project_id, do: where(count_query, [t], t.project_id == ^project_id), else: count_query
    count_query = if assignee_id, do: where(count_query, [t], t.assignee_id == ^assignee_id), else: count_query
    count_query = if phase_id, do: where(count_query, [t], t.phase_id == ^phase_id), else: count_query

    tasks = Repo.all(query) |> Repo.preload([:labels, :assignee, :comments])
    total = Repo.aggregate(count_query, :count)
    json(conn, %{tasks: Enum.map(tasks, &serialize/1), total: total})
  end

  def create(conn, params) do
    changeset = Task.changeset(%Task{}, params)

    case Repo.insert(changeset) do
      {:ok, task} ->
        task = Repo.preload(task, [:labels, :assignee, :comments])

        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.workspace_topic(task.workspace_id),
          %{event: "task.created", task_id: task.id, title: task.title}
        )

        conn |> put_status(201) |> json(%{task: serialize(task)})

      {:error, cs} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(cs)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Task, id) |> Repo.preload([:comments, :labels, :assignee]) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      task ->
        json(conn, %{
          task:
            serialize(task)
            |> Map.put(:comments, Enum.map(task.comments, &serialize_comment/1))
        })
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Repo.get(Task, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      task ->
        old_status = task.status
        changeset = Task.changeset(task, params)

        case Repo.update(changeset) do
          {:ok, updated} ->
            updated = Repo.preload(updated, [:labels, :assignee, :comments])

            if old_status != updated.status do
              Bizforge.EventBus.broadcast(
                Bizforge.EventBus.workspace_topic(updated.workspace_id),
                %{
                  event: "task.status_changed",
                  task_id: updated.id,
                  from: old_status,
                  to: updated.status
                }
              )
            end

            json(conn, %{task: serialize(updated)})

          {:error, cs} ->
            conn
            |> put_status(422)
            |> json(%{error: "validation_failed", details: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Repo.get(Task, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      task ->
        Repo.delete!(task)
        json(conn, %{ok: true})
    end
  end

  def assign(conn, %{"task_id" => id} = params) do
    agent_id = params["agent_id"]

    with %Task{} = task <- Repo.get(Task, id),
         %Agent{} <- Repo.get(Agent, agent_id) do
      case task
           |> Ecto.Changeset.change(assignee_id: agent_id)
           |> Repo.update() do
        {:ok, updated} ->
          updated = Repo.preload(updated, [:labels, :assignee, :comments])

          Bizforge.EventBus.broadcast(
            Bizforge.EventBus.workspace_topic(updated.workspace_id),
            %{event: "task.assigned", task_id: id, agent_id: agent_id}
          )

          json(conn, %{task: serialize(updated)})

        {:error, _changeset} ->
          conn |> put_status(500) |> json(%{error: "update_failed"})
      end
    else
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
    end
  end

  def checkout(conn, %{"task_id" => id} = params) do
    agent_id = params["agent_id"]

    case Repo.get(Task, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      _task ->
        case Bizforge.Work.checkout_task(id, agent_id) do
          {:ok, updated} ->
            updated = Repo.preload(updated, [:labels, :assignee, :comments])
            json(conn, %{task: serialize(updated)})

          {:error, :already_checked_out} ->
            conn
            |> put_status(409)
            |> json(%{error: "already_checked_out"})
        end
    end
  end

  def dispatch(conn, %{"task_id" => task_id}) do
    case Bizforge.TaskDispatcher.dispatch(task_id) do
      {:ok, :dispatched} ->
        json(conn, %{ok: true, message: "Agent dispatched"})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Task not found"})

      {:error, :not_assigned} ->
        conn |> put_status(422) |> json(%{error: "Task is not assigned to an agent"})

      {:error, :already_checked_out} ->
        conn |> put_status(409) |> json(%{error: "Task is already being worked on"})

      {:error, {:agent_not_ready, _}} ->
        conn |> put_status(422) |> json(%{error: "Assigned agent is not ready"})

      {:error, _reason} ->
        conn |> put_status(422) |> json(%{error: "Dispatch failed"})
    end
  end

  def add_label(conn, %{"id" => task_id, "label_id" => label_id}) do
    with %Task{} <- Repo.get(Task, task_id),
         %Label{} <- Repo.get(Label, label_id) do
      case Repo.insert(%IssueLabel{issue_id: task_id, label_id: label_id}, on_conflict: :nothing) do
        {:ok, _} ->
          json(conn, %{ok: true})

        {:error, cs} ->
          conn |> put_status(422) |> json(%{error: "failed", details: format_errors(cs)})
      end
    else
      nil -> conn |> put_status(404) |> json(%{error: "not_found"})
    end
  end

  def remove_label(conn, %{"id" => task_id, "label_id" => label_id}) do
    query = from il in IssueLabel, where: il.issue_id == ^task_id and il.label_id == ^label_id
    {count, _} = Repo.delete_all(query)

    if count > 0 do
      json(conn, %{ok: true})
    else
      conn |> put_status(404) |> json(%{error: "not_found"})
    end
  end

  def resolve_execution_order(conn, %{"project_id" => project_id}) do
    :ok = Bizforge.Work.resolve_execution_order(project_id)
    json(conn, %{ok: true})
  end

  def ready_tasks(conn, %{"project_id" => project_id}) do
    tasks =
      Bizforge.Work.ready_tasks(project_id)
      |> Repo.preload([:labels, :assignee, :comments])

    json(conn, %{tasks: Enum.map(tasks, &serialize/1)})
  end

  defp serialize(%Task{} = t) do
    assignee_name =
      if Ecto.assoc_loaded?(t.assignee) && t.assignee, do: t.assignee.name, else: nil

    comments_count =
      if Ecto.assoc_loaded?(t.comments), do: length(t.comments), else: 0

    labels =
      if Ecto.assoc_loaded?(t.labels),
        do: Enum.map(t.labels, fn l -> %{id: l.id, name: l.name, color: l.color} end),
        else: []

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
      assignee_name: assignee_name,
      labels: labels,
      comments_count: comments_count,
      created_by: nil,
      checked_out_by: t.checked_out_by,
      parent_id: t.parent_id,
      depends_on_ids: t.depends_on_ids || [],
      task_type: t.task_type,
      execution_order: t.execution_order,
      created_at: t.inserted_at,
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  defp serialize_comment(%Comment{} = c) do
    %{
      id: c.id,
      author_type: c.author_type,
      author_id: c.author_id,
      body: c.body,
      inserted_at: c.inserted_at
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
