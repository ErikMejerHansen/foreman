defmodule Foreman.Agent.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_runner(args) do
    DynamicSupervisor.start_child(__MODULE__, {Foreman.Agent.Runner, args})
  end

  def find_runner(task_id) do
    case Registry.lookup(Foreman.Agent.Registry, task_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def stop_runner(task_id) do
    case find_runner(task_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
end
