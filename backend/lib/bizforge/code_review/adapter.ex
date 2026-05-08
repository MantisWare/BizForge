defmodule Bizforge.CodeReview.Adapter do
  @moduledoc """
  Behaviour contract for code review adapters.

  Three implementations:
    - GithubAdapter — real PRs via GitHub API
    - GitlabAdapter — real MRs via GitLab API
    - VirtualPRAdapter — diff-based review in output_path/code/ (fallback)
  """

  @type pr_handle :: %{
          adapter: atom(),
          pr_id: String.t(),
          pr_url: String.t() | nil,
          branch_name: String.t(),
          status: String.t()
        }

  @callback open_pr(issue :: map(), project :: map(), opts :: keyword()) ::
              {:ok, pr_handle()} | {:error, term()}

  @callback get_diff(pr_handle()) :: {:ok, String.t()} | {:error, term()}

  @callback add_comment(pr_handle(), comment :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback approve(pr_handle()) :: {:ok, pr_handle()} | {:error, term()}

  @callback request_changes(pr_handle(), reason :: String.t()) ::
              {:ok, pr_handle()} | {:error, term()}

  @callback merge(pr_handle()) :: {:ok, pr_handle()} | {:error, term()}

  @doc "Resolve the appropriate adapter for a project based on integration bindings."
  @spec adapter_for(map()) :: {:ok, module(), keyword()} | :no_remote
  def adapter_for(project) do
    bindings = project.integration_bindings || []

    cond do
      Enum.any?(bindings, fn b -> b.provider == "github" && b.enabled end) ->
        github_binding = Enum.find(bindings, fn b -> b.provider == "github" end)
        {:ok, Bizforge.CodeReview.GithubAdapter, [binding: github_binding]}

      Enum.any?(bindings, fn b -> b.provider == "gitlab" && b.enabled end) ->
        gitlab_binding = Enum.find(bindings, fn b -> b.provider == "gitlab" end)
        {:ok, Bizforge.CodeReview.GitlabAdapter, [binding: gitlab_binding]}

      true ->
        :no_remote
    end
  end
end
