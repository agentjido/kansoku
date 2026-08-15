defmodule KansokuWeb do
  @moduledoc false

  @doc """
  Imports the shared LiveView setup for Kansoku screens.
  """
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView

      import KansokuWeb.CoreComponents
    end
  end

  @doc """
  Imports the shared HTML component setup for Kansoku views.
  """
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component

      import Phoenix.HTML
      import KansokuWeb.CoreComponents

      alias Phoenix.LiveView.JS
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
