defmodule Bizforge.Repo.Migrations.AddMemoryHierarchyAndIssueDeps do
  use Ecto.Migration

  def change do
    # ── Memory hierarchy: scope memory to projects + classify origin ──────────
    alter table(:memory_entries) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
      add :scope, :string, default: "project"
      add :source, :string, default: "manual"
    end

    create index(:memory_entries, [:workspace_id, :project_id, :category])
    create index(:memory_entries, [:project_id])
    create index(:memory_entries, [:scope])

    # ── Issue dependencies & hierarchy ────────────────────────────────────────
    alter table(:issues) do
      add :parent_id, references(:issues, type: :binary_id, on_delete: :nilify_all)
      add :depends_on_ids, {:array, :binary_id}, default: []
      add :task_type, :string
      add :execution_order, :integer
    end

    create index(:issues, [:parent_id])
    create index(:issues, [:task_type])
    create index(:issues, [:execution_order])
  end
end
