defmodule Bizforge.Work do
  @moduledoc "Work management context — tasks, projects, phases."

  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Project, Phase, Comment}
  import Ecto.Query

  # ── Tasks ──────────────────────────────────────────────────────────────────

  def list_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from t in Task, order_by: [desc: t.updated_at], limit: ^limit, offset: ^offset

    query = if ws = opts[:workspace_id], do: where(query, [t], t.workspace_id == ^ws), else: query
    query = if s = opts[:status], do: where(query, [t], t.status == ^s), else: query
    query = if p = opts[:priority], do: where(query, [t], t.priority == ^p), else: query
    query = if pid = opts[:project_id], do: where(query, [t], t.project_id == ^pid), else: query
    query = if aid = opts[:assignee_id], do: where(query, [t], t.assignee_id == ^aid), else: query

    {Repo.all(query), Repo.aggregate(Task, :count)}
  end

  def get_task(id), do: Repo.get(Task, id)

  def get_task_with_comments(id), do: Repo.get(Task, id) |> Repo.preload(:comments)

  def create_task(attrs) do
    result = %Task{} |> Task.changeset(attrs) |> Repo.insert()

    case result do
      {:ok, task} ->
        task = maybe_auto_assign(task)

        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.workspace_topic(task.workspace_id),
          %{event: "task.created", task_id: task.id, title: task.title}
        )

        if task.assignee_id do
          Bizforge.EventBus.broadcast(
            Bizforge.EventBus.workspace_topic(task.workspace_id),
            %{event: "task.assigned", task_id: task.id, agent_id: task.assignee_id}
          )
        end

        {:ok, task}

      error ->
        error
    end
  end

  defp maybe_auto_assign(%Task{assignee_id: aid} = task) when not is_nil(aid), do: task

  defp maybe_auto_assign(%Task{} = task) do
    project = if task.project_id, do: Repo.get(Project, task.project_id), else: nil
    auto_assign? = project !== nil && Map.get(project.config || %{}, "auto_assign", false)

    if auto_assign? do
      case Bizforge.Dispatch.SkillRouter.choose(task, project_id: task.project_id) do
        {:ok, agent_id} ->
          {:ok, updated} =
            task
            |> Ecto.Changeset.change(assignee_id: agent_id)
            |> Repo.update()

          updated

        {:error, _} ->
          task
      end
    else
      task
    end
  end

  def update_task(%Task{} = task, attrs) do
    old_status = task.status
    result = task |> Task.changeset(attrs) |> Repo.update()

    case result do
      {:ok, updated} when old_status != updated.status ->
        Bizforge.EventBus.broadcast(
          Bizforge.EventBus.workspace_topic(updated.workspace_id),
          %{
            event: "task.status_changed",
            task_id: updated.id,
            from: old_status,
            to: updated.status
          }
        )

        {:ok, updated}

      other ->
        other
    end
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  def assign_task(%Task{} = task, agent_id) do
    {:ok, updated} = task |> Ecto.Changeset.change(assignee_id: agent_id) |> Repo.update()

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.workspace_topic(updated.workspace_id),
      %{event: "task.assigned", task_id: updated.id, agent_id: agent_id}
    )

    {:ok, updated}
  end

  def resolve_execution_order(project_id) do
    tasks = Repo.all(from t in Task, where: t.project_id == ^project_id)
    id_map = Map.new(tasks, &{&1.id, &1})
    sorted = topological_sort(tasks)

    Enum.with_index(sorted, 1)
    |> Enum.each(fn {task, order} ->
      if Map.get(id_map, task.id) do
        from(t in Task, where: t.id == ^task.id)
        |> Repo.update_all(set: [execution_order: order])
      end
    end)

    :ok
  end

  def ready_tasks(project_id) do
    done_statuses = ~w(done closed)

    tasks =
      Repo.all(
        from t in Task,
          where: t.project_id == ^project_id and t.status in ["backlog", "todo"],
          order_by: [asc: t.execution_order, asc: t.inserted_at]
      )

    done_ids =
      Repo.all(
        from t in Task,
          where: t.project_id == ^project_id and t.status in ^done_statuses,
          select: t.id
      )
      |> MapSet.new()

    Enum.filter(tasks, fn task ->
      deps = task.depends_on_ids || []
      Enum.all?(deps, &MapSet.member?(done_ids, &1))
    end)
  end

  defp topological_sort(tasks) do
    graph = Map.new(tasks, &{&1.id, &1.depends_on_ids || []})
    ids = Enum.map(tasks, & &1.id)
    id_map = Map.new(tasks, &{&1.id, &1})

    {sorted, _} =
      Enum.reduce(ids, {[], MapSet.new()}, fn id, {acc, visited} ->
        visit(id, graph, id_map, acc, visited, MapSet.new())
      end)

    Enum.reverse(sorted)
  end

  defp visit(id, graph, id_map, acc, visited, in_stack) do
    cond do
      MapSet.member?(visited, id) ->
        {acc, visited}

      MapSet.member?(in_stack, id) ->
        {acc, visited}

      true ->
        deps = Map.get(graph, id, [])
        next_stack = MapSet.put(in_stack, id)

        {acc2, visited2} =
          Enum.reduce(deps, {acc, visited}, fn dep_id, {a, v} ->
            visit(dep_id, graph, id_map, a, v, next_stack)
          end)

        task = Map.get(id_map, id)
        result = if task !== nil, do: [task | acc2], else: acc2
        {result, MapSet.put(visited2, id)}
    end
  end

  def checkout_task(task_id, agent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.update_all(
           from(t in Task,
             where: t.id == ^task_id and is_nil(t.checked_out_by)
           ),
           set: [checked_out_by: agent_id, status: "in_progress", updated_at: now]
         ) do
      {1, _} -> {:ok, Repo.get!(Task, task_id)}
      {0, _} -> {:error, :already_checked_out}
    end
  end

  def create_comment(task_id, attrs) do
    %Comment{}
    |> Comment.changeset(Map.put(attrs, "issue_id", task_id))
    |> Repo.insert()
  end

  def list_comments(task_id) do
    Repo.all(
      from c in Comment,
        where: c.issue_id == ^task_id,
        order_by: [asc: c.inserted_at]
    )
  end

  # ── Projects ────────────────────────────────────────────────────────────────

  def list_projects(opts \\ []) do
    query = from p in Project, order_by: [desc: p.updated_at]
    query = if ws = opts[:workspace_id], do: where(query, [p], p.workspace_id == ^ws), else: query
    Repo.all(query)
  end

  def get_project(id), do: Repo.get(Project, id)

  def get_project_with_phases(id), do: Repo.get(Project, id) |> Repo.preload(:phases)

  def create_project(attrs), do: %Project{} |> Project.changeset(attrs) |> Repo.insert()

  def update_project(%Project{} = p, attrs), do: p |> Project.changeset(attrs) |> Repo.update()

  def delete_project(%Project{} = p), do: Repo.delete(p)

  def list_project_phases(project_id) do
    Repo.all(from p in Phase, where: p.project_id == ^project_id, order_by: [asc: p.title])
  end

  # ── Phases ──────────────────────────────────────────────────────────────────

  def list_phases(opts \\ []) do
    query = from p in Phase, order_by: [asc: p.title]
    query = if ws = opts[:workspace_id], do: where(query, [p], p.workspace_id == ^ws), else: query
    query = if pid = opts[:project_id], do: where(query, [p], p.project_id == ^pid), else: query
    Repo.all(query)
  end

  def get_phase(id), do: Repo.get(Phase, id)

  def get_phase_with_children(id) do
    phase = Repo.get(Phase, id)
    children = if phase, do: Repo.all(from p in Phase, where: p.parent_id == ^id), else: []

    task_count =
      if phase, do: Repo.aggregate(from(t in Task, where: t.phase_id == ^id), :count), else: 0

    {phase, children, task_count}
  end

  def create_phase(attrs), do: %Phase{} |> Phase.changeset(attrs) |> Repo.insert()

  def update_phase(%Phase{} = p, attrs), do: p |> Phase.changeset(attrs) |> Repo.update()

  def delete_phase(%Phase{} = p), do: Repo.delete(p)

  def get_phase_ancestry(phase_id) do
    build_ancestry(phase_id, MapSet.new())
  end

  defp build_ancestry(nil, _visited), do: []

  defp build_ancestry(phase_id, visited) do
    if MapSet.member?(visited, phase_id) do
      []
    else
      case Repo.get(Phase, phase_id) do
        nil -> []
        phase -> [phase | build_ancestry(phase.parent_id, MapSet.put(visited, phase_id))]
      end
    end
  end
end
