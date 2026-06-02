defmodule SquidSonarWeb.WorkflowGraphLayout do
  @moduledoc false

  @node_width 210
  @node_height 58
  @recovery_node_height 112
  @deadline_node_height 118
  @deadline_recovery_node_height 172
  @column_gap 72
  @row_gap 42
  @padding_x 24
  @padding_y 20
  @line_size 2

  def build(%{nodes: []}) do
    %{
      width: 0,
      height: 0,
      nodes: [],
      segments: [],
      ports: []
    }
  end

  def build(%{nodes: nodes, edges: edges}) do
    node_order = node_order(nodes)
    graph_edges = graph_edges(edges, node_order)
    columns = columns(nodes, graph_edges, node_order)
    track_height = track_height(nodes)
    positions = positions(nodes, graph_edges, columns, node_order, track_height)
    positioned_nodes = positioned_nodes(nodes, positions)

    %{
      width: dimension(positions, :column, @node_width, @column_gap, @padding_x),
      height: dimension(positions, :row, track_height, @row_gap, @padding_y),
      nodes: positioned_nodes,
      segments: segments(graph_edges, positions),
      ports: ports(graph_edges, positions)
    }
  end

  defp node_order(nodes) do
    nodes
    |> Enum.with_index()
    |> Map.new(fn {%{name: name}, index} -> {node_key(name), index} end)
  end

  defp graph_edges(edges, node_order) do
    edges
    |> Enum.map(fn %{from: from, to: to} -> {node_key(from), node_key(to)} end)
    |> Enum.filter(fn {from, to} ->
      Map.has_key?(node_order, from) and Map.has_key?(node_order, to) and
        Map.fetch!(node_order, from) < Map.fetch!(node_order, to)
    end)
  end

  defp columns(nodes, graph_edges, node_order) do
    initial_columns = Map.new(nodes, fn %{name: name} -> {node_key(name), 1} end)

    Enum.reduce(1..map_size(node_order), initial_columns, fn _iteration, columns ->
      Enum.reduce(graph_edges, columns, fn {from, to}, columns ->
        next_column = Map.fetch!(columns, from) + 1

        if next_column > Map.fetch!(columns, to) do
          Map.put(columns, to, next_column)
        else
          columns
        end
      end)
    end)
  end

  defp positions(nodes, graph_edges, columns, node_order, track_height) do
    parents_by_node =
      Enum.reduce(graph_edges, %{}, fn {from, to}, parents ->
        Map.update(parents, to, [from], &[from | &1])
      end)

    nodes
    |> Enum.sort_by(fn %{name: name} ->
      key = node_key(name)
      {Map.fetch!(columns, key), Map.fetch!(node_order, key)}
    end)
    |> Enum.reduce({%{}, %{}}, fn %{name: name} = node, {positions, occupied_rows} ->
      key = node_key(name)
      column = Map.fetch!(columns, key)
      desired_row = desired_row(Map.get(parents_by_node, key, []), positions)
      row = available_row(Map.get(occupied_rows, column, MapSet.new()), desired_row)

      position = %{
        column: column,
        row: row,
        x: @padding_x + (column - 1) * (@node_width + @column_gap),
        y: @padding_y + (row - 1) * (track_height + @row_gap),
        width: @node_width,
        height: node_height(node)
      }

      {
        Map.put(positions, key, position),
        Map.update(occupied_rows, column, MapSet.new([row]), &MapSet.put(&1, row))
      }
    end)
    |> elem(0)
  end

  defp desired_row(parents, positions) do
    parents
    |> Enum.reverse()
    |> Enum.find_value(1, fn parent ->
      case Map.fetch(positions, parent) do
        {:ok, %{row: row}} -> row
        :error -> nil
      end
    end)
  end

  defp available_row(occupied_rows, desired_row) do
    if MapSet.member?(occupied_rows, desired_row) do
      available_row(occupied_rows, desired_row + 1)
    else
      desired_row
    end
  end

  defp track_height(nodes) do
    nodes
    |> Enum.map(&node_height/1)
    |> Enum.max(fn -> @node_height end)
  end

  defp node_height(node) do
    cond do
      deadline_node?(node) and recovery_node?(node) -> @deadline_recovery_node_height
      deadline_node?(node) -> @deadline_node_height
      recovery_node?(node) -> @recovery_node_height
      true -> @node_height
    end
  end

  defp deadline_node?(%{deadline: deadline}) when is_map(deadline), do: true
  defp deadline_node?(_node), do: false

  defp recovery_node?(%{recovery: recovery}) when is_map(recovery) do
    case Map.get(recovery, :compensation) || Map.get(recovery, "compensation") do
      compensation when is_map(compensation) ->
        not is_nil(Map.get(compensation, :callback) || Map.get(compensation, "callback"))

      _other ->
        false
    end
  end

  defp recovery_node?(_node), do: false

  defp positioned_nodes(nodes, positions) do
    Enum.map(nodes, fn %{name: name} = node ->
      position = Map.fetch!(positions, node_key(name))

      %{
        node: node,
        x: position.x,
        y: position.y,
        width: position.width,
        height: position.height
      }
    end)
  end

  defp dimension(positions, field, item_size, gap, padding) do
    max_index =
      positions
      |> Map.values()
      |> Enum.map(&Map.fetch!(&1, field))
      |> Enum.max(fn -> 1 end)

    padding * 2 + max_index * item_size + (max_index - 1) * gap
  end

  defp segments(graph_edges, positions) do
    Enum.flat_map(graph_edges, fn {from, to} ->
      source = Map.fetch!(positions, from)
      target = Map.fetch!(positions, to)
      x1 = source.x + source.width
      x2 = target.x
      y1 = source.y + source.height / 2
      y2 = target.y + target.height / 2
      mid_x = x1 + (x2 - x1) / 2

      if y1 == y2 do
        [horizontal_segment(x1, y1, x2 - x1)]
      else
        [
          horizontal_segment(x1, y1, mid_x - x1),
          vertical_segment(mid_x, y1, y2),
          horizontal_segment(mid_x, y2, x2 - mid_x)
        ]
      end
    end)
  end

  defp horizontal_segment(x, y, width) do
    %{
      orientation: :horizontal,
      x: x,
      y: y - @line_size / 2,
      width: width,
      height: @line_size
    }
  end

  defp vertical_segment(x, y1, y2) do
    %{
      orientation: :vertical,
      x: x - @line_size / 2,
      y: min(y1, y2),
      width: @line_size,
      height: abs(y2 - y1)
    }
  end

  defp ports(graph_edges, positions) do
    graph_edges
    |> Enum.flat_map(fn {from, to} ->
      source = Map.fetch!(positions, from)
      target = Map.fetch!(positions, to)

      [
        %{x: source.x + source.width, y: source.y + source.height / 2},
        %{x: target.x, y: target.y + target.height / 2}
      ]
    end)
    |> Enum.uniq()
  end

  defp node_key(value), do: to_string(value)
end
