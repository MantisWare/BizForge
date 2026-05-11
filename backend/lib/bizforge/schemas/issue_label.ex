defmodule Bizforge.Schemas.IssueLabel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issue_labels" do
    belongs_to :task, Bizforge.Schemas.Task, foreign_key: :issue_id
    belongs_to :label, Bizforge.Schemas.Label

    timestamps(updated_at: false)
  end

  def changeset(issue_label, attrs) do
    issue_label
    |> cast(attrs, [:issue_id, :label_id])
    |> validate_required([:issue_id, :label_id])
    |> unique_constraint([:issue_id, :label_id])
  end
end
