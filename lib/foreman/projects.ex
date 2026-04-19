defmodule Foreman.Projects do
  import Ecto.Query
  alias Foreman.Repo
  alias Foreman.Projects.Project

  def list_projects do
    Repo.all(from p in Project, order_by: [desc: p.inserted_at])
  end

  def get_project!(id) do
    Repo.get!(Project, id)
  end

  def get_project(id) do
    Repo.get(Project, id)
  end

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end
end
