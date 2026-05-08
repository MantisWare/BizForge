defmodule Bizforge.Repo.Migrations.AddConfigToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :config, :map, default: %{}
    end
  end
end
