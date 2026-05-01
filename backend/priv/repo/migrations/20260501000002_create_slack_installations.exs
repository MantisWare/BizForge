defmodule Bizforge.Repo.Migrations.CreateSlackInstallations do
  use Ecto.Migration

  def change do
    create table(:slack_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false
      add :team_id, :string
      add :team_name, :string
      add :bot_token, :string, null: false
      add :signing_secret, :string, null: false
      add :default_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :channel_mappings, :map, default: %{}
      add :active, :boolean, default: true

      timestamps()
    end

    create unique_index(:slack_installations, [:workspace_id, :team_id])
    create index(:slack_installations, [:workspace_id])
    create index(:slack_installations, [:team_id])
  end
end
