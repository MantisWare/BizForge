defmodule Bizforge.Schemas.SlackInstallation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slack_installations" do
    field :team_id, :string
    field :team_name, :string
    field :bot_token, :string
    field :signing_secret, :string
    field :default_agent_id, :binary_id
    field :channel_mappings, :map, default: %{}
    field :active, :boolean, default: true

    belongs_to :workspace, Bizforge.Schemas.Workspace

    timestamps()
  end

  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [
      :workspace_id,
      :team_id,
      :team_name,
      :bot_token,
      :signing_secret,
      :default_agent_id,
      :channel_mappings,
      :active
    ])
    |> validate_required([:workspace_id, :bot_token, :signing_secret])
    |> unique_constraint(:team_id, name: :slack_installations_workspace_id_team_id_index)
  end
end
