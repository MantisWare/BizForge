defmodule Bizforge.Repo.Migrations.AddOutputPathToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :output_path, :string
    end
  end
end
