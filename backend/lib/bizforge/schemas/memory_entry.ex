defmodule Bizforge.Schemas.MemoryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_scopes ~w(company project agent)
  @valid_sources ~w(manual forgemap ai_generated system)

  schema "memory_entries" do
    field :key, :string
    field :content, :string
    field :category, :string
    field :tags, {:array, :string}
    field :scope, :string, default: "project"
    field :source, :string, default: "manual"

    belongs_to :workspace, Bizforge.Schemas.Workspace
    belongs_to :project, Bizforge.Schemas.Project
    belongs_to :agent, Bizforge.Schemas.Agent

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:key, :content, :category, :tags, :scope, :source, :workspace_id, :project_id, :agent_id])
    |> validate_required([:key, :content, :workspace_id])
    |> validate_inclusion(:scope, @valid_scopes)
    |> validate_inclusion(:source, @valid_sources)
    |> foreign_key_constraint(:project_id)
  end
end
