defmodule Bizforge.Schemas.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :logo_url, :string
    field :plan, :string, default: "free"
    field :settings, :map, default: %{}
    field :mission, :string
    field :description, :string
    field :issue_prefix, :string
    field :budget_monthly_cents, :integer
    field :budget_per_agent_cents, :integer
    field :budget_enforcement, :string, default: "visibility"
    field :governance, :map, default: %{}

    has_many :memberships, Bizforge.Schemas.OrganizationMembership
    has_many :invitations, Bizforge.Schemas.Invitation
    has_many :divisions, Bizforge.Schemas.Division
    has_many :workspaces, Bizforge.Schemas.Workspace

    timestamps()
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :name,
      :slug,
      :logo_url,
      :plan,
      :settings,
      :mission,
      :description,
      :issue_prefix,
      :budget_monthly_cents,
      :budget_per_agent_cents,
      :budget_enforcement,
      :governance
    ])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_inclusion(:budget_enforcement, ~w(visibility warning stop))
    |> unique_constraint(:slug)
  end
end
