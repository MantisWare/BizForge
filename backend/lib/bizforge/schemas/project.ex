defmodule Bizforge.Schemas.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :output_path, :string
    field :config, :map, default: %{}

    belongs_to :workspace, Bizforge.Schemas.Workspace
    has_many :goals, Bizforge.Schemas.Goal
    has_many :issues, Bizforge.Schemas.Issue
    has_many :integration_bindings, Bizforge.Schemas.IntegrationBinding,
      where: [owner_type: "project"], foreign_key: :owner_id

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :status, :workspace_id, :output_path, :config])
    |> validate_required([:name, :workspace_id])
    |> validate_inclusion(:status, ~w(active archived completed))
    |> foreign_key_constraint(:workspace_id)
  end
end
