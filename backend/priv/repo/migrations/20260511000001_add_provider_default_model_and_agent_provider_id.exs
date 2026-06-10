defmodule Bizforge.Repo.Migrations.AddProviderDefaultModelAndAgentProviderId do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :default_model, :string
    end

    alter table(:agents) do
      add :provider_id, references(:providers, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:agents, [:provider_id])
  end
end
