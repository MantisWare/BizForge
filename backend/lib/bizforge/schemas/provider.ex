defmodule Bizforge.Schemas.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "providers" do
    field :slug, :string
    field :name, :string
    field :category, :string, default: "cloud"
    field :api_key, :string
    field :endpoint, :string
    field :config, :map, default: %{}
    field :models, {:array, :string}, default: []
    field :is_default, :boolean, default: false
    field :default_model, :string
    field :status, :string, default: "untested"
    field :last_tested_at, :utc_datetime
    field :error_message, :string

    belongs_to :workspace, Bizforge.Schemas.Workspace

    timestamps()
  end

  @required_fields ~w(slug name)a
  @optional_fields ~w(category api_key endpoint config models is_default default_model status
                      last_tested_at error_message workspace_id)a

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:category, ~w(cloud local))
    |> validate_inclusion(:status, ~w(untested connected error))
  end
end
