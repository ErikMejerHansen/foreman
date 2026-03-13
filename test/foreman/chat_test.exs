defmodule Foreman.ChatTest do
  use Foreman.DataCase, async: true

  import Foreman.Fixtures

  alias Foreman.Chat
  alias Foreman.Chat.Message

  describe "create_message/1" do
    test "succeeds with valid attributes" do
      project = create_project()
      task = create_task(project.id)
      assert {:ok, %Message{}} = Chat.create_message(message_attrs(task.id))
    end

    test "persists the message role" do
      project = create_project()
      task = create_task(project.id)
      {:ok, message} = Chat.create_message(message_attrs(task.id, %{"role" => "user"}))
      assert message.role == "user"
    end

    test "persists the message content" do
      project = create_project()
      task = create_task(project.id)
      {:ok, message} = Chat.create_message(message_attrs(task.id, %{"content" => "Hello!"}))
      assert message.content == "Hello!"
    end

    test "returns :duplicate when the same message already exists" do
      project = create_project()
      task = create_task(project.id)
      attrs = message_attrs(task.id, %{"role" => "assistant", "content" => "Done."})
      {:ok, _} = Chat.create_message(attrs)
      assert {:error, :duplicate} = Chat.create_message(attrs)
    end

    test "allows different roles with the same content" do
      project = create_project()
      task = create_task(project.id)
      {:ok, _} = Chat.create_message(message_attrs(task.id, %{"role" => "user", "content" => "Hello"}))
      assert {:ok, _} = Chat.create_message(message_attrs(task.id, %{"role" => "assistant", "content" => "Hello"}))
    end

    test "allows the same role with different content" do
      project = create_project()
      task = create_task(project.id)
      {:ok, _} = Chat.create_message(message_attrs(task.id, %{"role" => "assistant", "content" => "First"}))
      assert {:ok, _} = Chat.create_message(message_attrs(task.id, %{"role" => "assistant", "content" => "Second"}))
    end

  end

  describe "list_messages/1" do
    test "returns an empty list when task has no messages" do
      project = create_project()
      task = create_task(project.id)
      assert [] = Chat.list_messages(task.id)
    end

    test "returns all messages for a task" do
      project = create_project()
      task = create_task(project.id)
      create_message(task.id, %{"content" => "First"})
      create_message(task.id, %{"content" => "Second"})
      assert length(Chat.list_messages(task.id)) == 2
    end

    test "does not return messages from other tasks" do
      project = create_project()
      task_a = create_task(project.id, %{"title" => "Task A"})
      task_b = create_task(project.id, %{"title" => "Task B"})
      create_message(task_a.id)
      assert [] = Chat.list_messages(task_b.id)
    end

    test "returns messages ordered by insertion time" do
      project = create_project()
      task = create_task(project.id)
      create_message(task.id, %{"content" => "First"})
      create_message(task.id, %{"content" => "Second"})
      [first | _] = Chat.list_messages(task.id)
      assert first.content == "First"
    end
  end
end
