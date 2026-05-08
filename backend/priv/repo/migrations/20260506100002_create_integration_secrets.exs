defmodule Bizforge.Repo.Migrations.CreateIntegrationSecrets do
  use Ecto.Migration

  def change do
    create table(:integration_secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :integration_id, references(:integrations, type: :binary_id, on_delete: :delete_all),
        null: false
      add :secret_id, references(:secrets, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:integration_secrets, [:integration_id, :key])
    create index(:integration_secrets, [:secret_id])
  end
end
