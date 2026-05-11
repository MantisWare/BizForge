defmodule Bizforge.Repo.Migrations.RenameGoalsToPhases do
  use Ecto.Migration

  def change do
    # 1. Rename the goals table to phases
    rename table(:goals), to: table(:phases)

    # 2. Rename issues.goal_id -> issues.phase_id
    rename table(:issues), :goal_id, to: :phase_id

    # 3. Rename sprints.goal -> sprints.objective
    rename table(:sprints), :goal, to: :objective
  end
end
