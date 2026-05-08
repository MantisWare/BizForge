defmodule Bizforge.Schemas.IntegrationSecret do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "integration_secrets" do
    field :key, :string

    belongs_to :integration, Bizforge.Schemas.Integration
    belongs_to :secret, Bizforge.Schemas.Secret

    timestamps()
  end

  def changeset(integration_secret, attrs) do
    integration_secret
    |> cast(attrs, [:key, :integration_id, :secret_id])
    |> validate_required([:key, :integration_id, :secret_id])
    |> unique_constraint([:integration_id, :key])
    |> foreign_key_constraint(:integration_id)
    |> foreign_key_constraint(:secret_id)
  end
end
