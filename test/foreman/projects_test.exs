defmodule Foreman.ProjectsTest do
  use Foreman.DataCase, async: true

  import Foreman.Fixtures

  alias Foreman.Projects
  alias Foreman.Projects.Project

  describe "create_project/1" do
    test "succeeds with valid attributes" do
      assert {:ok, %Project{}} = Projects.create_project(project_attrs())
    end

    test "persists the project name" do
      {:ok, project} = Projects.create_project(project_attrs(%{"name" => "My Repo"}))
      assert project.name == "My Repo"
    end

    test "persists the repo path" do
      {:ok, project} = Projects.create_project(project_attrs(%{"repo_path" => "/home/code/myapp"}))
      assert project.repo_path == "/home/code/myapp"
    end

    test "fails when name is missing" do
      assert {:error, changeset} = Projects.create_project(project_attrs(%{"name" => nil}))
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails when repo_path is missing" do
      assert {:error, changeset} = Projects.create_project(project_attrs(%{"repo_path" => nil}))
      assert %{repo_path: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_projects/0" do
    test "returns an empty list when no projects exist" do
      assert [] = Projects.list_projects()
    end

    test "returns all projects" do
      create_project(%{"name" => "Alpha"})
      create_project(%{"name" => "Beta"})

      assert length(Projects.list_projects()) == 2
    end

  end

  describe "get_project!/1" do
    test "returns the project with the given id" do
      project = create_project()
      assert Projects.get_project!(project.id).id == project.id
    end

    test "raises when project does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_project/2" do
    test "updates the project name" do
      project = create_project(%{"name" => "Old Name"})
      {:ok, updated} = Projects.update_project(project, %{"name" => "New Name"})
      assert updated.name == "New Name"
    end

    test "fails when updating with an invalid name" do
      project = create_project()
      assert {:error, changeset} = Projects.update_project(project, %{"name" => ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_project/1" do
    test "removes the project from the database" do
      project = create_project()
      {:ok, _} = Projects.delete_project(project)
      assert_raise Ecto.NoResultsError, fn -> Projects.get_project!(project.id) end
    end
  end

  describe "change_project/2" do
    test "returns a changeset for the project" do
      project = create_project()
      assert %Ecto.Changeset{} = Projects.change_project(project)
    end

    test "returns a changeset with applied changes" do
      project = create_project()
      changeset = Projects.change_project(project, %{"name" => "Updated"})
      assert changeset.changes.name == "Updated"
    end
  end
end
