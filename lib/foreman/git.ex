defmodule Foreman.Git do
  require Logger

  def create_worktree(repo_path, branch_name, worktree_path) do
    case System.cmd("git", ["worktree", "add", "-b", branch_name, worktree_path],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "Failed to create worktree: #{output}"}
    end
  end

  def remove_worktree(repo_path, worktree_path) do
    case System.cmd("git", ["worktree", "remove", worktree_path, "--force"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "Failed to remove worktree: #{output}"}
    end
  end

  def diff(repo_path, branch_name, worktree_path \\ nil) do
    committed =
      case System.cmd("git", ["diff", "main...#{branch_name}"],
             cd: repo_path,
             stderr_to_stdout: true
           ) do
        {output, 0} -> output
        _ -> ""
      end

    uncommitted =
      if worktree_path && File.dir?(worktree_path) do
        staged =
          case System.cmd("git", ["diff", "--cached"],
                 cd: worktree_path,
                 stderr_to_stdout: true
               ) do
            {output, 0} -> output
            _ -> ""
          end

        unstaged =
          case System.cmd("git", ["diff"],
                 cd: worktree_path,
                 stderr_to_stdout: true
               ) do
            {output, 0} -> output
            _ -> ""
          end

        staged <> unstaged
      else
        ""
      end

    combined = committed <> uncommitted

    if combined == "" do
      {:ok, ""}
    else
      {:ok, combined}
    end
  end

  def diff_stat(repo_path, branch_name) do
    case System.cmd("git", ["diff", "--stat", "main...#{branch_name}"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, "Failed to get diff stat: #{output}"}
    end
  end

  def rebase_from_main(worktree_path) do
    case System.cmd("git", ["rebase", "main"],
           cd: worktree_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, _} ->
        # Abort the failed rebase
        System.cmd("git", ["rebase", "--abort"], cd: worktree_path, stderr_to_stdout: true)
        {:error, "Rebase failed (aborted): #{output}"}
    end
  end

  def merge_to_main(repo_path, branch_name) do
    case System.cmd("git", ["merge", branch_name, "--no-ff", "-m", "Merge #{branch_name}"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "Failed to merge: #{output}"}
    end
  end

  def delete_branch(repo_path, branch_name) do
    case System.cmd("git", ["branch", "-d", branch_name],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "Failed to delete branch: #{output}"}
    end
  end
end
