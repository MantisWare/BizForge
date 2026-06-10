defmodule Bizforge.Schemas.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agents" do
    field :slug, :string
    field :name, :string
    field :role, :string
    field :adapter, :string
    field :model, :string
    field :temperature, :float, default: 0.3
    field :max_concurrent_runs, :integer, default: 1
    field :status, :string, default: "sleeping"
    field :config, :map, default: %{}
    field :system_prompt, :string
    field :avatar_emoji, :string, default: "🤖"
    field :last_session_summary, :string
    field :session_continuity, :map, default: %{}

    belongs_to :workspace, Bizforge.Schemas.Workspace
    belongs_to :provider, Bizforge.Schemas.Provider
    belongs_to :reports_to_agent, Bizforge.Schemas.Agent, foreign_key: :reports_to
    belongs_to :team, Bizforge.Schemas.Team
    has_many :sessions, Bizforge.Schemas.Session
    has_many :schedules, Bizforge.Schemas.Schedule
    has_many :app_permissions, Bizforge.Schemas.AppPermission
    has_many :tool_permissions, Bizforge.Schemas.ToolPermission
    has_many :agent_apps, Bizforge.Schemas.AgentApp
    has_many :integration_bindings, Bizforge.Schemas.IntegrationBinding,
      where: [owner_type: "agent"], foreign_key: :owner_id
    many_to_many :skills, Bizforge.Schemas.Skill, join_through: "agent_skills"

    timestamps()
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :slug,
      :name,
      :role,
      :adapter,
      :model,
      :temperature,
      :max_concurrent_runs,
      :status,
      :config,
      :system_prompt,
      :workspace_id,
      :provider_id,
      :reports_to,
      :avatar_emoji,
      :team_id,
      :last_session_summary,
      :session_continuity
    ])
    |> validate_required([:slug, :name, :role, :adapter, :model, :workspace_id])
    |> validate_inclusion(:status, ~w(active idle working running sleeping error paused))
    |> validate_inclusion(
      :adapter,
      ~w(osa claude-code codex bash http openclaw cursor cursor-cli gemini aider jido-claw windsurf)
    )
    |> unique_constraint([:workspace_id, :slug])
  end
end
