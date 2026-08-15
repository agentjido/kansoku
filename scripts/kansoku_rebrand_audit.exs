allowed_paths =
  MapSet.new([
    "CHANGELOG.md",
    "MIGRATION.md",
    "mix.lock",
    "examples/example_app/mix.lock"
  ])

legacy_tokens = [
  "Squid" <> "Sonar",
  "squid" <> "_" <> "sonar",
  "squid" <> "-" <> "sonar",
  "Squid" <> "ie",
  "squid" <> "ie",
  "SQUID" <> "IE"
]

{paths, 0} =
  System.cmd("git", ["ls-files", "--cached", "--others", "--exclude-standard", "-z"])

violations =
  paths
  |> String.split(<<0>>, trim: true)
  |> Enum.uniq()
  |> Enum.reject(&String.starts_with?(&1, ".codex/"))
  |> Enum.reject(&MapSet.member?(allowed_paths, &1))
  |> Enum.filter(&File.regular?/1)
  |> Enum.flat_map(fn path ->
    contents = File.read!(path)

    Enum.flat_map(legacy_tokens, fn token ->
      matches = []
      matches = if String.contains?(path, token), do: [{path, "path:#{token}"} | matches], else: matches
      if String.contains?(contents, token), do: [{path, token} | matches], else: matches
    end)
  end)

case violations do
  [] ->
    IO.puts("Kansoku brand audit passed")

  violations ->
    Enum.each(violations, fn {path, token} ->
      IO.puts(:stderr, "#{path}: contains legacy token #{inspect(token)}")
    end)

    System.halt(1)
end
