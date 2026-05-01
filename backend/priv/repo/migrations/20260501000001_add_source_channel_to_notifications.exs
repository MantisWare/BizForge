defmodule Bizforge.Repo.Migrations.AddSourceChannelToNotifications do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add :source_channel, :string
      add :reply_to, :map, default: %{}
    end

    create index(:notifications, [:source_channel])
  end
end
