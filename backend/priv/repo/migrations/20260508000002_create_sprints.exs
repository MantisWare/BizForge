defmodule Bizforge.Repo.Migrations.CreateSprints do
  use Ecto.Migration

  def change do
    create table(:sprints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :goal, :text
      add :start_date, :date
      add :end_date, :date
      add :status, :string, default: "planned", null: false
      add :velocity_target, :integer
      add :velocity_actual, :integer
      add :config, :map, default: %{}

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:sprints, [:project_id])
    create index(:sprints, [:workspace_id])
    create index(:sprints, [:status])

    alter table(:issues) do
      add :sprint_id, references(:sprints, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:issues, [:sprint_id])
  end
end
