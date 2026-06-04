defmodule SquidSonarWeb do
  @moduledoc false

  @doc """
  Imports the shared LiveView setup for SquidSonar screens.
  """
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView

      import SquidSonarWeb.CoreComponents
    end
  end

  @doc """
  Imports the shared HTML component setup for SquidSonar views.
  """
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component

      import Phoenix.HTML
      import SquidSonarWeb.CoreComponents

      alias Phoenix.LiveView.JS
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
