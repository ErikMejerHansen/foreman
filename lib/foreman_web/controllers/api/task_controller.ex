defmodule ForemanWeb.API.TaskController do
  use ForemanWeb, :controller

  alias Foreman.Projects
  alias Foreman.Tasks

  def create(conn, %{"project_id" => project_id} = params) do
    task_params = Map.merge(params["task"] || %{}, %{
      "project_id" => project_id,
      "created_via_api" => true
    })

    with {:ok, project} <- fetch_project(project_id),
         {:ok, task} <- Tasks.create_task(Map.put(task_params, "project_id", project.id)) do
      conn
      |> put_status(:created)
      |> render(:show, task: task)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end

  defp fetch_project(id) do
    case Projects.get_project(id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
