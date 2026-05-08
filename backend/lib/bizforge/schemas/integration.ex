defmodule Bizforge.Schemas.Integration do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "integrations" do
    field :slug, :string
    field :name, :string
    field :provider, :string
    field :category, :string
    field :config, :map, default: %{}
    field :connected, :boolean, default: false
    field :last_synced_at, :utc_datetime

    belongs_to :workspace, Bizforge.Schemas.Workspace
    has_many :integration_secrets, Bizforge.Schemas.IntegrationSecret
    has_many :integration_bindings, Bizforge.Schemas.IntegrationBinding

    timestamps()
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:slug, :name, :provider, :category, :config, :connected, :workspace_id])
    |> validate_required([:slug, :name, :provider, :category, :workspace_id])
    |> unique_constraint([:workspace_id, :slug])
  end
end
