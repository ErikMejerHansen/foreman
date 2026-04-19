defmodule ForemanWeb.API.TaskJSON do
  def show(%{task: task}) do
    %{data: task_data(task)}
  end

  defp task_data(task) do
    %{
      id: task.id,
      title: task.title,
      instructions: task.instructions,
      status: task.status,
      position: task.position,
      project_id: task.project_id,
      created_via_api: task.created_via_api,
      inserted_at: task.inserted_at
    }
  end
end
