defmodule ForemanWeb.Router do
  use ForemanWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ForemanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ForemanWeb do
    pipe_through :browser

    live "/", ProjectLive.Index, :index
    live "/projects", ProjectLive.Index, :index
    live "/projects/new", ProjectLive.Index, :new
    live "/projects/:id", ProjectLive.Show, :show
    live "/projects/:id/tasks/new", ProjectLive.Show, :new_task
    live "/stats", ProjectLive.GlobalStats, :show
    live "/projects/:id/stats", ProjectLive.Stats, :show
    live "/projects/:id/settings", ProjectLive.Settings, :show
    live "/projects/:project_id/tasks/:id", TaskLive.Show, :show
  end

  scope "/api", ForemanWeb.API do
    pipe_through :api

    post "/projects/:project_id/tasks", TaskController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:foreman, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ForemanWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
