defmodule Kansoku.ReleasePrepScript do
  @version_files ["README.md"]

  def main(args) do
    {opts, args, invalid} =
      OptionParser.parse(args,
        strict: [date: :string, notes_file: :string, notes_only: :boolean],
        aliases: [d: :date]
      )

    if invalid != [] do
      fail!("Invalid options: #{inspect(invalid)}")
    end

    version = single_version!(args)
    validate_version!(version)

    if opts[:notes_only] do
      notes = released_notes!(version)
      write_notes_file(opts[:notes_file], release_notes(notes))
      IO.puts("Prepared Kansoku #{version} release notes.")
    else
      validate_version_increase!(version)

      date = Keyword.get(opts, :date, Date.to_iso8601(Date.utc_today()))
      notes = unreleased_notes!()

      update_mix_version!(version)
      update_install_snippets!(version)
      update_changelog!(version, date, notes)
      write_notes_file(opts[:notes_file], release_notes(notes))

      IO.puts("Prepared Kansoku #{version} release metadata.")
    end
  end

  defp single_version!([version]), do: version

  defp single_version!(_args) do
    fail!(
      "Expected exactly one version argument, for example: " <>
        "elixir scripts/kansoku_release_prep.exs 0.2.1"
    )
  end

  defp validate_version!(version) do
    unless Regex.match?(~r/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/, version) do
      fail!("Expected a SemVer version without the leading v, got: #{inspect(version)}")
    end
  end

  defp validate_version_increase!(version) do
    current_version = current_mix_version!()

    unless Version.compare(version, current_version) == :gt do
      fail!("Release version #{version} must be newer than current version #{current_version}")
    end
  end

  defp current_mix_version! do
    case Regex.run(~r/version: "(?<version>\d+\.\d+\.\d+(?:[-+][^"]+)?)"/, File.read!("mix.exs"),
           capture: ["version"]
         ) do
      [version] -> version
      _missing -> fail!("Could not find mix.exs version")
    end
  end

  defp unreleased_notes! do
    body = File.read!("CHANGELOG.md")

    case Regex.run(~r/^## Unreleased\s*\n(?<notes>.*?)(?=^## \d)/ms, body, capture: ["notes"]) do
      [notes] ->
        case String.trim(notes) do
          "" -> fail!("CHANGELOG.md Unreleased section is empty")
          notes -> notes
        end

      _missing ->
        fail!("Could not find the CHANGELOG.md Unreleased section")
    end
  end

  defp released_notes!(version) do
    pattern =
      ~r/^## #{Regex.escape(version)} - [^\n]+\n(?<notes>.*?)(?=^## |\z)/ms

    case Regex.run(pattern, File.read!("CHANGELOG.md"), capture: ["notes"]) do
      [notes] ->
        case String.trim(notes) do
          "" -> fail!("CHANGELOG.md #{version} section is empty")
          notes -> notes
        end

      _missing ->
        fail!("Could not find the CHANGELOG.md #{version} section")
    end
  end

  defp update_mix_version!(version) do
    update_file!("mix.exs", fn body ->
      replace_once!(
        body,
        ~r/version: "\d+\.\d+\.\d+(?:[-+][^"]+)?"/,
        ~s(version: "#{version}"),
        "mix.exs version"
      )
    end)
  end

  defp update_install_snippets!(version) do
    Enum.each(@version_files, fn path ->
      update_file!(path, fn body ->
        replace_all!(
          body,
          ~r/{:kansoku, "~> \d+\.\d+\.\d+(?:[-+][^"]+)?"}/,
          ~s({:kansoku, "~> #{version}"}),
          "#{path} install snippet"
        )
      end)
    end)
  end

  defp update_changelog!(version, date, notes) do
    update_file!("CHANGELOG.md", fn body ->
      if Regex.match?(~r/^## #{Regex.escape(version)}\s+-/m, body) do
        fail!("CHANGELOG.md already has a #{version} section")
      end

      replacement = "## Unreleased\n\n## #{version} - #{date}\n\n#{notes}\n\n"

      replace_once!(
        body,
        ~r/^## Unreleased\s*\n.*?(?=^## \d)/ms,
        replacement,
        "CHANGELOG.md release insertion point"
      )
    end)
  end

  defp release_notes(notes), do: "## Changes\n\n#{notes}\n"

  defp write_notes_file(nil, _notes), do: :ok

  defp write_notes_file(path, notes) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, notes)
  end

  defp update_file!(path, fun) do
    body = File.read!(path)
    File.write!(path, fun.(body))
  end

  defp replace_once!(body, pattern, replacement, label) do
    if Regex.match?(pattern, body) do
      Regex.replace(pattern, body, replacement, global: false)
    else
      fail!("Could not find #{label}")
    end
  end

  defp replace_all!(body, pattern, replacement, label) do
    if Regex.match?(pattern, body) do
      Regex.replace(pattern, body, replacement)
    else
      fail!("Could not find #{label}")
    end
  end

  defp fail!(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Kansoku.ReleasePrepScript.main(System.argv())
