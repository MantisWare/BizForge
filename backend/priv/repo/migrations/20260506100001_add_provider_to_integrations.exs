defmodule Bizforge.Repo.Migrations.AddProviderToIntegrations do
  use Ecto.Migration

  def up do
    alter table(:integrations) do
      add :provider, :string
    end

    flush()

    execute "UPDATE integrations SET provider = slug WHERE provider IS NULL"

    alter table(:integrations) do
      modify :provider, :string, null: false
    end

    create index(:integrations, [:workspace_id, :provider])
  end

  def down do
    drop index(:integrations, [:workspace_id, :provider])

    alter table(:integrations) do
      remove :provider
    end
  end
end
