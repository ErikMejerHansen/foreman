defmodule Foreman.ReviewNotifications do
  use GenServer

  @pubsub Foreman.PubSub
  @topic "review_notifications"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, MapSet.new(), name: __MODULE__)
  end

  def notify(project_id) do
    GenServer.cast(__MODULE__, {:notify, project_id})
  end

  def clear(project_id) do
    GenServer.cast(__MODULE__, {:clear, project_id})
  end

  def pending_project_ids do
    GenServer.call(__MODULE__, :get_all)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:notify, project_id}, state) do
    new_state = MapSet.put(state, project_id)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:review_notification, project_id})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:clear, project_id}, state) do
    new_state = MapSet.delete(state, project_id)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:review_notification_cleared, project_id})
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    {:reply, MapSet.to_list(state), state}
  end
end
