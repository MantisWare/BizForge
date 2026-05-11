defmodule Bizforge.Schemas.Phase do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "phases" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "active"

    belongs_to :workspace, Bizforge.Schemas.Workspace
    belongs_to :project, Bizforge.Schemas.Project
    belongs_to :parent, Bizforge.Schemas.Phase
    has_many :children, Bizforge.Schemas.Phase, foreign_key: :parent_id
    has_many :tasks, Bizforge.Schemas.Task

    timestamps()
  end

  def changeset(phase, attrs) do
    phase
    |> cast(attrs, [:title, :description, :status, :workspace_id, :project_id, :parent_id])
    |> validate_required([:title, :workspace_id])
    |> validate_not_self_parent()
  end

  defp validate_not_self_parent(changeset) do
    parent_id = get_field(changeset, :parent_id)
    id = get_field(changeset, :id)

    if parent_id && parent_id == id do
      add_error(changeset, :parent_id, "cannot be the same as the phase's own ID")
    else
      changeset
    end
  end
end
