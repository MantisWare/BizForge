defmodule Bizforge.Repo.Migrations.AddLifecycleConfigToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :lifecycle_config, :map, default: %{}
    end
  end
end
