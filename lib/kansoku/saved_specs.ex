defmodule Kansoku.SavedSpecs do
  @moduledoc """
  Host-owned saved workflow spec boundary.

  Kansoku normalizes and previews values the host provides, but persistence,
  approval policy, action registry ownership, and activation remain host-owned.
  """

  alias Jizoku.Workflow.EditorSpec

  @default_title "Saved workflow spec"

  @type validation :: %{status: :valid | :invalid, errors: [map()]}
  @type saved_spec :: %{
          key: String.t(),
          title: String.t(),
          status: atom() | String.t() | nil,
          status_label: String.t(),
          description: String.t() | nil,
          updated_at: term(),
          editor_json: term(),
          source_spec: term(),
          spec: term(),
          validation: validation(),
          preview: {:ok, map()} | {:error, term()} | nil,
          diff: {:ok, map()} | {:error, term()} | nil,
          startable?: boolean()
        }

  @doc """
  Lists saved workflow spec records from host-provided keyed data.
  """
  @spec list(term(), term()) :: [saved_spec()]
  def list(saved_specs, action_registry \\ nil) do
    saved_specs
    |> entries()
    |> Enum.map(&build(&1, action_registry))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Fetches one saved workflow spec record by its stable host key.
  """
  @spec get(term(), String.t(), term()) :: {:ok, saved_spec()} | {:error, :not_found}
  def get(saved_specs, key, action_registry \\ nil) when is_binary(key) do
    saved_specs
    |> entries()
    |> Enum.find(fn {entry_key, _attrs} -> to_string(entry_key) == key end)
    |> case do
      nil -> {:error, :not_found}
      entry -> built_result(build(entry, action_registry))
    end
  end

  @doc """
  Builds example payload JSON for a saved spec's executable runtime spec.
  """
  @spec payload_json(saved_spec()) :: String.t()
  def payload_json(%{spec: spec}) do
    spec
    |> payload_fields()
    |> sample_payload()
    |> Jason.encode!(pretty: true)
  end

  def payload_json(_saved_spec), do: Jason.encode!(%{}, pretty: true)

  defp entries(nil), do: []

  defp entries(saved_specs) when is_map(saved_specs) do
    Enum.map(saved_specs, fn {key, attrs} -> {key, attrs} end)
  end

  defp entries(saved_specs) when is_list(saved_specs) do
    if Keyword.keyword?(saved_specs) do
      Enum.map(saved_specs, fn {key, attrs} -> {key, attrs} end)
    else
      []
    end
  end

  defp entries(_saved_specs), do: []

  defp build({_key, nil}, _action_registry), do: nil

  defp build({key, attrs}, action_registry) when is_map(attrs) do
    editor_json = editor_json(attrs)
    source_spec = source_spec(attrs)
    validation = validate(editor_json, action_registry)
    preview = preview(editor_json, action_registry)
    diff = diff(source_spec, editor_json, action_registry)
    status = field(attrs, :status, "status")

    %{
      key: to_string(key),
      title: title(key, attrs),
      status: status,
      status_label: status_label(status, validation),
      description: field(attrs, :description, "description"),
      updated_at: field(attrs, :updated_at, "updated_at"),
      editor_json: editor_json,
      source_spec: source_spec,
      spec: field(attrs, :spec, "spec"),
      validation: validation,
      preview: preview,
      diff: diff,
      startable?: startable?(status, validation, attrs)
    }
  end

  defp build({_key, _attrs}, _action_registry), do: nil

  defp built_result(nil), do: {:error, :not_found}
  defp built_result(saved_spec), do: {:ok, saved_spec}

  defp title(key, attrs) do
    field(attrs, :title, "title") ||
      field(attrs, :name, "name") ||
      key
      |> to_string()
      |> String.replace("_", " ")
      |> String.capitalize()
      |> case do
        "" -> @default_title
        title -> title
      end
  end

  defp editor_json(attrs) do
    value =
      first_field(attrs, [
        {:editor_json, "editor_json"},
        {:editor_spec, "editor_spec"},
        {:draft, "draft"}
      ])

    case value do
      nil -> spec_to_editor_json(field(attrs, :spec, "spec"))
      value -> spec_to_editor_json(value)
    end
  end

  defp source_spec(attrs) do
    case first_field(attrs, [{:source_spec, "source_spec"}, {:source, "source"}]) do
      nil -> nil
      value -> spec_to_editor_json(value)
    end
  end

  defp spec_to_editor_json(value) when is_map(value), do: EditorSpec.to_map(value)
  defp spec_to_editor_json(value), do: value

  defp validate(editor_json, action_registry) do
    case EditorSpec.validate_map(editor_json, validation_opts(action_registry)) do
      :ok -> %{status: :valid, errors: []}
      {:error, {:invalid_workflow_editor_spec, errors}} -> %{status: :invalid, errors: errors}
    end
  end

  defp preview(editor_json, action_registry) do
    EditorSpec.preview_graph(editor_json, validation_opts(action_registry))
  end

  defp diff(nil, _editor_json, _action_registry), do: nil

  defp diff(source_spec, editor_json, action_registry) do
    EditorSpec.diff(source_spec, editor_json, validation_opts(action_registry))
  end

  defp validation_opts(nil), do: []
  defp validation_opts(action_registry), do: [action_registry: action_registry]

  defp status_label(status, %{status: :invalid}), do: human_status(status || :invalid)
  defp status_label(status, _validation), do: human_status(status || :valid)

  defp human_status(status) when is_atom(status) do
    status
    |> Atom.to_string()
    |> human_status()
  end

  defp human_status(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp human_status(_status), do: "Saved"

  defp startable?(status, %{status: :valid}, attrs) do
    approved_status?(status) and is_map(field(attrs, :spec, "spec"))
  end

  defp startable?(_status, _validation, _attrs), do: false

  defp approved_status?(:approved), do: true
  defp approved_status?("approved"), do: true
  defp approved_status?(_status), do: false

  defp first_field(attrs, keys) do
    Enum.find_value(keys, fn {atom_key, string_key} -> field(attrs, atom_key, string_key) end)
  end

  defp field(value, atom_key, string_key) when is_map(value) do
    cond do
      Map.has_key?(value, atom_key) -> Map.fetch!(value, atom_key)
      Map.has_key?(value, string_key) -> Map.fetch!(value, string_key)
      true -> nil
    end
  end

  defp field(_value, _atom_key, _string_key), do: nil

  defp payload_fields(%{payload: payload}) when is_list(payload), do: payload
  defp payload_fields(%{"payload" => payload}) when is_list(payload), do: payload
  defp payload_fields(_spec), do: []

  defp sample_payload(payload_fields) do
    Enum.reduce(payload_fields, %{}, fn field, payload ->
      case field(field, :name, "name") do
        nil ->
          payload

        name ->
          field_name = to_string(name)
          Map.put(payload, field_name, sample_payload_value(field(field, :type, "type")))
      end
    end)
  end

  defp sample_payload_value(type) when type in [:integer, "integer"], do: 1
  defp sample_payload_value(type) when type in [:float, "float"], do: 1.0
  defp sample_payload_value(type) when type in [:boolean, "boolean"], do: true
  defp sample_payload_value(type) when type in [:map, "map"], do: %{}
  defp sample_payload_value(type) when type in [:list, "list"], do: []
  defp sample_payload_value(_type), do: "example"
end
