defmodule Bizforge.Schemas.Sprint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(planned active complete cancelled)

  schema "sprints" do
    field :name, :string
    field :objective, :string
    field :start_date, :date
    field :end_date, :date
    field :status, :string, default: "planned"
    field :velocity_target, :integer
    field :velocity_actual, :integer
    field :config, :map, default: %{}

    belongs_to :project, Bizforge.Schemas.Project
    belongs_to :workspace, Bizforge.Schemas.Workspace
    has_many :tasks, Bizforge.Schemas.Task

    timestamps()
  end

  def changeset(sprint, attrs) do
    sprint
    |> cast(attrs, [
      :name,
      :objective,
      :start_date,
      :end_date,
      :status,
      :velocity_target,
      :velocity_actual,
      :config,
      :project_id,
      :workspace_id
    ])
    |> validate_required([:name, :project_id, :workspace_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_dates()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:workspace_id)
  end

  defp validate_dates(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date !== nil && end_date !== nil && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end
end
