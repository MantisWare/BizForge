defmodule BizforgeWeb.QaReportController do
  @moduledoc """
  Ingests QA automation reports, creates WorkProduct + Report rows,
  and broadcasts qa.report_ready for the IssueLifecycle FSM.
  """
  use BizforgeWeb, :controller

  alias Bizforge.Repo
  alias Bizforge.Schemas.{WorkProduct, Report}

  def create(conn, params) do
    issue_id = params["issue_id"]
    session_id = params["session_id"]
    agent_id = params["agent_id"]
    workspace_id = params["workspace_id"]

    summary = params["summary"] || %{}
    failures = params["failures"] || []
    status = if failures == [], do: "pass", else: "fail"

    with {:ok, wp} <- create_work_product(workspace_id, agent_id, session_id, issue_id, summary, status),
         {:ok, report} <- create_report(workspace_id, agent_id, summary, failures, status) do
      broadcast_qa_ready(workspace_id, issue_id, status, failures)

      conn
      |> put_status(201)
      |> json(%{
        ok: true,
        work_product_id: wp.id,
        report_id: report.id,
        status: status,
        total: summary["total"] || 0,
        passed: summary["passed"] || 0,
        failed: summary["failed"] || 0
      })
    else
      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  defp create_work_product(workspace_id, agent_id, session_id, issue_id, summary, status) do
    %WorkProduct{}
    |> WorkProduct.changeset(%{
      title: "QA Report: #{status} (#{summary["passed"] || 0}/#{summary["total"] || 0} passed)",
      product_type: "qa-report",
      issue_id: issue_id,
      session_id: session_id,
      agent_id: agent_id,
      workspace_id: workspace_id,
      metadata: summary
    })
    |> Repo.insert()
  end

  defp create_report(workspace_id, agent_id, summary, failures, status) do
    %Report{}
    |> Report.changeset(%{
      title: "QA Automation Report",
      category: "qa",
      status: status,
      workspace_id: workspace_id,
      agent_id: agent_id,
      data: %{
        "summary" => summary,
        "failures" => failures,
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    })
    |> Repo.insert()
  end

  defp broadcast_qa_ready(workspace_id, issue_id, status, failures) do
    report_payload = %{
      "pass" => status == "pass",
      "status" => status,
      "failures" => failures
    }

    Bizforge.EventBus.broadcast(
      Bizforge.EventBus.workspace_topic(workspace_id),
      %{event: "qa.report_ready", issue_id: issue_id, report: report_payload}
    )

    if issue_id do
      Bizforge.IssueLifecycle.notify_qa_report(issue_id, report_payload)
    end
  end
end
