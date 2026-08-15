defmodule Kansoku.ValidationErrors do
  @moduledoc """
  Formatting helpers for structured Jizoku validation errors.
  """

  @doc """
  Formats a list of structured validation errors without exposing details maps.
  """
  @spec format(term()) :: String.t()
  def format(errors) when is_list(errors) do
    errors
    |> Enum.map(&format_error/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  def format(_errors), do: "Runtime spec validation failed."

  @doc """
  Formats one validation error path for display.
  """
  @spec format_path([term()]) :: String.t()
  def format_path([]), do: "spec"

  def format_path(path) when is_list(path) do
    Enum.map_join(path, ".", &to_string/1)
  end

  defp format_error(%{path: path, message: message}) when is_list(path) do
    "#{format_path(path)}: #{message}"
  end

  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(_error), do: ""
end
