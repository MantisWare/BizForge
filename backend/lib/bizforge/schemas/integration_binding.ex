defmodule Bizforge.Schemas.IntegrationBinding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @owner_types ~w(project team agent skill)

  schema "integration_bindings" do
    field :owner_type, :string
    field :owner_id, :binary_id
    field :provider, :string
    field :config_overrides, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :integration, Bizforge.Schemas.Integration

    timestamps()
  end

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, [:owner_type, :owner_id, :provider, :config_overrides, :enabled, :integration_id])
    |> validate_required([:owner_type, :owner_id, :provider, :integration_id])
    |> validate_inclusion(:owner_type, @owner_types)
    |> unique_constraint([:owner_type, :owner_id, :provider])
    |> foreign_key_constraint(:integration_id)
  end
end
