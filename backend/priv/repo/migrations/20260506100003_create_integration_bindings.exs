defmodule Bizforge.Repo.Migrations.CreateIntegrationBindings do
  use Ecto.Migration

  def change do
    create table(:integration_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :provider, :string, null: false
      add :config_overrides, :map, default: %{}
      add :enabled, :boolean, default: true, null: false
      add :integration_id, references(:integrations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:integration_bindings, [:owner_type, :owner_id, :provider])
    create index(:integration_bindings, [:integration_id])
    create index(:integration_bindings, [:owner_type, :owner_id])
  end
end
