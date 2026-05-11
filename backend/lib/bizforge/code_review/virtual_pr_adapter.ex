defmodule Bizforge.CodeReview.VirtualPRAdapter do
  @moduledoc """
  Fallback code review adapter that works without GitHub/GitLab.

  Generates diffs from the project's output_path/code/ directory using git,
  stores them as VirtualPullRequest records, and manages reviewer comments
  through the existing Issue comments table.
  """
  @behaviour Bizforge.CodeReview.Adapter

  require Logger
  alias Bizforge.Repo
  alias Bizforge.Schemas.{Task, Comment}
  import Ecto.Changeset, only: [change: 2]

  @impl true
  def open_pr(issue, project, _opts \\ []) do
    output_path = project.output_path
    code_dir = if output_path, do: Path.join(output_path, "code"), else: nil

    if code_dir === nil || !File.dir?(code_dir) do
      {:error, :no_output_path}
    else
      ensure_git_init(code_dir)
      branch_name = "issue/#{issue.id}"

      diff = generate_diff(code_dir, branch_name)
      pr_id = Ecto.UUID.generate()

      {:ok, _} =
        issue
        |> change(%{
          delegation_chain:
            Map.merge(issue.delegation_chain || %{}, %{
              "pr" => %{
                "pr_id" => pr_id,
                "type" => "virtual",
                "branch_name" => branch_name,
                "diff" => diff,
                "status" => "open",
                "opened_at" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
            })
        })
        |> Repo.update()

      handle = %{
        adapter: __MODULE__,
        pr_id: pr_id,
        pr_url: nil,
        branch_name: branch_name,
        status: "open"
      }

      {:ok, handle}
    end
  end

  @impl true
  def get_diff(%{pr_id: pr_id}) do
    case find_issue_by_pr(pr_id) do
      nil -> {:error, :not_found}
      issue ->
        diff = get_in(issue.delegation_chain || %{}, ["pr", "diff"]) || ""
        {:ok, diff}
    end
  end

  @impl true
  def add_comment(%{pr_id: pr_id}, comment, opts \\ []) do
    case find_issue_by_pr(pr_id) do
      nil ->
        {:error, :not_found}

      issue ->
        agent_id = opts[:agent_id]

        {:ok, c} =
          %Comment{}
          |> Comment.changeset(%{
            issue_id: issue.id,
            body: "[PR Review] #{comment}",
            author_type: "agent",
            author_id: agent_id || "00000000-0000-0000-0000-000000000000"
          })
          |> Repo.insert()

        {:ok, %{id: c.id, body: c.body}}
    end
  end

  @impl true
  def approve(%{pr_id: pr_id} = handle) do
    case find_issue_by_pr(pr_id) do
      nil ->
        {:error, :not_found}

      issue ->
        update_pr_status(issue, "approved")
        Bizforge.TaskLifecycle.notify_review_approved(issue.id)
        {:ok, %{handle | status: "approved"}}
    end
  end

  @impl true
  def request_changes(%{pr_id: pr_id} = handle, reason) do
    case find_issue_by_pr(pr_id) do
      nil ->
        {:error, :not_found}

      issue ->
        update_pr_status(issue, "changes_requested")
        add_comment(handle, "Changes requested: #{reason}", author: "reviewer")
        Bizforge.TaskLifecycle.notify_changes_requested(issue.id)
        {:ok, %{handle | status: "changes_requested"}}
    end
  end

  @impl true
  def merge(%{pr_id: pr_id} = handle) do
    case find_issue_by_pr(pr_id) do
      nil ->
        {:error, :not_found}

      issue ->
        update_pr_status(issue, "merged")
        {:ok, %{handle | status: "merged"}}
    end
  end

  defp ensure_git_init(code_dir) do
    unless File.dir?(Path.join(code_dir, ".git")) do
      System.cmd("git", ["init"], cd: code_dir, stderr_to_stdout: true)
      System.cmd("git", ["add", "."], cd: code_dir, stderr_to_stdout: true)
      System.cmd("git", ["commit", "-m", "Initial commit", "--allow-empty"],
        cd: code_dir,
        stderr_to_stdout: true
      )
    end
  end

  defp generate_diff(code_dir, _branch_name) do
    case System.cmd("git", ["diff", "HEAD"], cd: code_dir, stderr_to_stdout: true) do
      {diff, 0} when diff != "" -> diff
      _ ->
        case System.cmd("git", ["diff", "--cached"], cd: code_dir, stderr_to_stdout: true) do
          {diff, 0} -> diff
          _ -> "(no changes detected)"
        end
    end
  end

  defp find_issue_by_pr(pr_id) do
    import Ecto.Query

    Repo.one(
      from i in Task,
        where: fragment("?->'pr'->>'pr_id' = ?", i.delegation_chain, ^pr_id),
        limit: 1
    )
  end

  defp update_pr_status(issue, status) do
    pr_data = get_in(issue.delegation_chain || %{}, ["pr"]) || %{}
    updated_pr = Map.put(pr_data, "status", status)
    chain = Map.put(issue.delegation_chain || %{}, "pr", updated_pr)

    issue |> change(delegation_chain: chain) |> Repo.update()
  end
end
