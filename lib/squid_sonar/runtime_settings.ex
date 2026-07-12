defmodule SquidSonar.RuntimeSettings do
  @moduledoc """
  Builds the intentionally small, public runtime-settings projection.

  Host configuration is treated as sensitive. This module exposes only stable
  labels, booleans, counts, and package versions; it never serializes the
  configured values themselves.
  """

  alias SquidSonar.Runs

  @type projection :: %{
          squid_sonar_version: String.t(),
          squidie_version: String.t(),
          integration_status: String.t(),
          transport: String.t(),
          visibility: String.t(),
          control_access: String.t(),
          runtime_specs_configured: boolean(),
          runtime_specs_count: non_neg_integer(),
          saved_specs_configured: boolean(),
          saved_specs_count: non_neg_integer(),
          action_registry_configured: boolean()
        }

  @doc "Builds the safe runtime-settings projection from LiveView assigns."
  @spec project(map(), keyword()) :: projection()
  def project(settings, opts \\ []) when is_map(settings) and is_list(opts) do
    runtime_specs = Map.get(settings, :runtime_specs)
    runtime_spec = Map.get(settings, :runtime_spec)
    saved_specs = Map.get(settings, :saved_specs)

    squidie_version = version(:squidie)

    %{
      squid_sonar_version: version(:squid_sonar),
      squidie_version: squidie_version,
      integration_status: integration_status(opts),
      transport: transport_label(Map.get(settings, :live_transport)),
      visibility: visibility_label(Map.get(settings, :visibility_policy, :operator)),
      control_access: control_access(Map.get(settings, :visibility_policy, :operator)),
      runtime_specs_configured: configured?(runtime_specs) or not is_nil(runtime_spec),
      runtime_specs_count: runtime_specs_count(runtime_specs, runtime_spec),
      saved_specs_configured: configured?(saved_specs),
      saved_specs_count: collection_count(saved_specs),
      action_registry_configured: configured?(Map.get(settings, :action_registry))
    }
  end

  @doc "Encodes an already-safe runtime-settings projection as readable JSON."
  @spec json(projection()) :: String.t()
  def json(projection), do: Jason.encode!(projection, pretty: true)

  defp version(app) do
    case Application.spec(app, :vsn) do
      nil -> "unavailable"
      version when is_list(version) -> List.to_string(version)
      version -> to_string(version)
    end
  end

  defp transport_label("longpoll"), do: "Long polling"
  defp transport_label(_transport), do: "WebSocket"

  defp visibility_label(:operator), do: "Operator"
  defp visibility_label(:auditor), do: "Auditor"
  defp visibility_label(:external), do: "External policy"
  defp visibility_label(_policy), do: "Custom policy"

  defp control_access(:operator), do: "Operator controls enabled"
  defp control_access(_policy), do: "Read-only"

  defp integration_status(opts) do
    runs_opts = Keyword.take(opts, [:client, :squidie])

    case Runs.list_runs([limit: 1], runs_opts) do
      {:ok, _runs} -> "Ready"
      {:error, _reason} -> "Needs attention"
    end
  end

  defp configured?(nil), do: false
  defp configured?(collection) when collection in [[], %{}], do: false
  defp configured?(_value), do: true

  defp collection_count(collection) when is_map(collection), do: map_size(collection)
  defp collection_count(collection) when is_list(collection), do: length(collection)
  defp collection_count(_collection), do: 0

  defp runtime_specs_count(runtime_specs, runtime_spec) do
    case collection_count(runtime_specs) do
      0 -> if(is_nil(runtime_spec), do: 0, else: 1)
      count -> count
    end
  end
end
