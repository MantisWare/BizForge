defmodule Bizforge.Schemas.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "goals" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "active"

    belongs_to :workspace, Bizforge.Schemas.Workspace
    belongs_to :project, Bizforge.Schemas.Project
    belongs_to :parent, Bizforge.Schemas.Goal
    has_many :children, Bizforge.Schemas.Goal, foreign_key: :parent_id
    has_many :issues, Bizforge.Schemas.Issue

    timestamps()
  end

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:title, :description, :status, :workspace_id, :project_id, :parent_id])
    |> validate_required([:title, :workspace_id])
    |> validate_not_self_parent()
  end

  defp validate_not_self_parent(changeset) do
    parent_id = get_field(changeset, :parent_id)
    id = get_field(changeset, :id)

    if parent_id && parent_id == id do
      add_error(changeset, :parent_id, "cannot be the same as the goal's own ID")
    else
      changeset
    end
  end
end
