defmodule Bizforge.Schemas.Issue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issues" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "backlog"
    field :priority, :string, default: "medium"

    belongs_to :workspace, Bizforge.Schemas.Workspace
    belongs_to :project, Bizforge.Schemas.Project
    belongs_to :goal, Bizforge.Schemas.Goal
    belongs_to :sprint, Bizforge.Schemas.Sprint
    belongs_to :assignee, Bizforge.Schemas.Agent
    belongs_to :checked_out_by_agent, Bizforge.Schemas.Agent, foreign_key: :checked_out_by
    field :checked_out_at, :utc_datetime
    field :adapter_override, :string
    field :delegation_chain, :map, default: %{}
    has_many :comments, Bizforge.Schemas.Comment
    many_to_many :labels, Bizforge.Schemas.Label, join_through: "issue_labels"

    timestamps()
  end

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, [
      :title,
      :description,
      :status,
      :priority,
      :workspace_id,
      :project_id,
      :goal_id,
      :sprint_id,
      :assignee_id,
      :checked_out_by,
      :adapter_override,
      :delegation_chain
    ])
    |> validate_required([:title, :workspace_id])
    |> validate_inclusion(:status, ~w(backlog todo in_progress in_review done cancelled closed))
    |> validate_inclusion(:priority, ~w(low medium high critical))
  end
end
