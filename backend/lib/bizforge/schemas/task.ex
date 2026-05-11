defmodule Bizforge.Schemas.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_task_types ~w(prerequisite feature subtask validation scaffold)

  schema "issues" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "backlog"
    field :priority, :string, default: "medium"

    belongs_to :workspace, Bizforge.Schemas.Workspace
    belongs_to :project, Bizforge.Schemas.Project
    belongs_to :phase, Bizforge.Schemas.Phase, foreign_key: :phase_id
    belongs_to :sprint, Bizforge.Schemas.Sprint
    belongs_to :assignee, Bizforge.Schemas.Agent
    belongs_to :checked_out_by_agent, Bizforge.Schemas.Agent, foreign_key: :checked_out_by
    belongs_to :parent, Bizforge.Schemas.Task, foreign_key: :parent_id
    field :checked_out_at, :utc_datetime
    field :adapter_override, :string
    field :delegation_chain, :map, default: %{}
    field :depends_on_ids, {:array, :binary_id}, default: []
    field :task_type, :string
    field :execution_order, :integer
    has_many :comments, Bizforge.Schemas.Comment, foreign_key: :issue_id
    has_many :subtasks, Bizforge.Schemas.Task, foreign_key: :parent_id
    many_to_many :labels, Bizforge.Schemas.Label, join_through: "issue_labels"

    timestamps()
  end

  def changeset(task, attrs) do
    changeset =
      task
      |> cast(attrs, [
        :title,
        :description,
        :status,
        :priority,
        :workspace_id,
        :project_id,
        :phase_id,
        :sprint_id,
        :assignee_id,
        :checked_out_by,
        :adapter_override,
        :delegation_chain,
        :parent_id,
        :depends_on_ids,
        :task_type,
        :execution_order
      ])
      |> validate_required([:title, :workspace_id])
      |> validate_inclusion(:status, ~w(backlog todo in_progress in_review done cancelled closed))
      |> validate_inclusion(:priority, ~w(low medium high critical))
      |> foreign_key_constraint(:parent_id)

    if get_change(changeset, :task_type) !== nil do
      validate_inclusion(changeset, :task_type, @valid_task_types)
    else
      changeset
    end
  end
end
