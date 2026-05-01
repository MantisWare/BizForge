defmodule Bizforge.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :category, :string, null: false, default: "cloud"
      add :api_key, :text
      add :endpoint, :string
      add :config, :map, default: %{}
      add :models, {:array, :string}, default: []
      add :is_default, :boolean, default: false
      add :status, :string, null: false, default: "untested"
      add :last_tested_at, :utc_datetime
      add :error_message, :text
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create index(:providers, [:workspace_id])
    create index(:providers, [:slug])
  end
end
