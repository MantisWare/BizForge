defmodule Bizforge.LifecycleConfigs do
  @moduledoc """
  Default lifecycle configuration templates for projects.

  Each config defines the FSM states, transitions, and automation flags
  that TaskLifecycle uses to drive the dev pipeline.
  """

  @doc "Default lifecycle for Domo development projects."
  def domo_development do
    %{
      "name" => "Domo Development",
      "states" => ["backlog", "todo", "in_progress", "in_review", "testing", "done", "blocked", "cancelled"],
      "transitions" => [
        %{"from" => "backlog", "to" => "in_progress", "trigger" => "assigned_and_dispatched"},
        %{"from" => "in_progress", "to" => "in_review", "trigger" => "session_completed"},
        %{"from" => "in_review", "to" => "testing", "trigger" => "review_approved"},
        %{"from" => "in_review", "to" => "in_progress", "trigger" => "changes_requested"},
        %{"from" => "testing", "to" => "done", "trigger" => "qa_pass"},
        %{"from" => "testing", "to" => "in_progress", "trigger" => "qa_fail"},
        %{"from" => "in_progress", "to" => "blocked", "trigger" => "escalation"},
        %{"from" => "blocked", "to" => "in_progress", "trigger" => "unblocked"}
      ],
      "auto_review" => true,
      "auto_qa" => true,
      "require_approval_to_merge" => false,
      "qa_skill" => "qa/automate",
      "review_skill" => "development/code-review",
      "domo_specific" => %{
        "startup_probe" => "qa/startup-probe-domo",
        "qa_agent_preference" => "domo-qa-engineer",
        "manifest_size_test" => true,
        "appdb_security_test" => true,
        "code_engine_contract_test" => true
      }
    }
  end

  @doc "Default lifecycle for generic dev teams (non-Domo)."
  def generic_development do
    %{
      "name" => "Generic Development",
      "states" => ["backlog", "todo", "in_progress", "in_review", "testing", "done", "blocked", "cancelled"],
      "transitions" => [
        %{"from" => "backlog", "to" => "in_progress", "trigger" => "assigned_and_dispatched"},
        %{"from" => "in_progress", "to" => "in_review", "trigger" => "session_completed"},
        %{"from" => "in_review", "to" => "testing", "trigger" => "review_approved"},
        %{"from" => "in_review", "to" => "in_progress", "trigger" => "changes_requested"},
        %{"from" => "testing", "to" => "done", "trigger" => "qa_pass"},
        %{"from" => "testing", "to" => "in_progress", "trigger" => "qa_fail"},
        %{"from" => "in_progress", "to" => "blocked", "trigger" => "escalation"},
        %{"from" => "blocked", "to" => "in_progress", "trigger" => "unblocked"}
      ],
      "auto_review" => true,
      "auto_qa" => true,
      "require_approval_to_merge" => false,
      "qa_skill" => "qa/automate",
      "review_skill" => "development/code-review"
    }
  end

  @doc "Minimal lifecycle — dev straight to done, no review or QA gates."
  def minimal do
    %{
      "name" => "Minimal",
      "states" => ["backlog", "in_progress", "done"],
      "transitions" => [
        %{"from" => "backlog", "to" => "in_progress", "trigger" => "assigned_and_dispatched"},
        %{"from" => "in_progress", "to" => "done", "trigger" => "session_completed"}
      ],
      "auto_review" => false,
      "auto_qa" => false,
      "require_approval_to_merge" => false
    }
  end

  @doc "Lifecycle with delivery gate — full dev pipeline with project delivery checks."
  def delivery do
    %{
      "name" => "Software Delivery",
      "states" => ["backlog", "todo", "in_progress", "in_review", "testing", "done", "blocked", "cancelled"],
      "transitions" => [
        %{"from" => "backlog", "to" => "in_progress", "trigger" => "assigned_and_dispatched"},
        %{"from" => "in_progress", "to" => "in_review", "trigger" => "session_completed"},
        %{"from" => "in_review", "to" => "testing", "trigger" => "review_approved"},
        %{"from" => "in_review", "to" => "in_progress", "trigger" => "changes_requested"},
        %{"from" => "testing", "to" => "done", "trigger" => "qa_pass"},
        %{"from" => "testing", "to" => "in_progress", "trigger" => "qa_fail"},
        %{"from" => "in_progress", "to" => "blocked", "trigger" => "escalation"},
        %{"from" => "blocked", "to" => "in_progress", "trigger" => "unblocked"}
      ],
      "auto_review" => true,
      "auto_qa" => true,
      "require_approval_to_merge" => false,
      "qa_skill" => "qa/automate",
      "review_skill" => "development/code-review",
      "delivery_gate" => true
    }
  end

  @doc "Return all available templates for the UI picker."
  def all do
    [
      %{id: "domo_development", name: "Domo Development", config: domo_development()},
      %{id: "generic_development", name: "Generic Development", config: generic_development()},
      %{id: "delivery", name: "Software Delivery (with delivery gate)", config: delivery()},
      %{id: "minimal", name: "Minimal (no review/QA)", config: minimal()}
    ]
  end
end
