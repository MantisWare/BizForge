defmodule Bizforge.Schemas.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspaces" do
    field :name, :string
    field :path, :string
    field :status, :string, default: "active"

    belongs_to :owner, Bizforge.Schemas.User
    belongs_to :organization, Bizforge.Schemas.Organization
    has_many :agents, Bizforge.Schemas.Agent
    has_many :projects, Bizforge.Schemas.Project
    has_many :issues, Bizforge.Schemas.Issue
    has_many :skills, Bizforge.Schemas.Skill

    timestamps()
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :path, :status, :owner_id, :organization_id])
    |> validate_required([:name, :path])
    |> validate_inclusion(:status, ~w(active archived))
  end
end
