defmodule Bizforge.Schemas.OrganizationMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_memberships" do
    field :role, :string, default: "member"

    belongs_to :organization, Bizforge.Schemas.Organization
    belongs_to :user, Bizforge.Schemas.User

    timestamps()
  end

  def changeset(organization_membership, attrs) do
    organization_membership
    |> cast(attrs, [:role, :organization_id, :user_id])
    |> validate_required([:organization_id, :user_id])
    |> validate_inclusion(:role, ~w(owner admin member))
    |> unique_constraint([:organization_id, :user_id])
  end
end
