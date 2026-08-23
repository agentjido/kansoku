defmodule Kansoku.RebrandContractTest do
  use ExUnit.Case, async: true

  test "uses the Kansoku application and public namespace" do
    assert Mix.Project.config()[:app] == :kansoku
    assert Code.ensure_loaded?(Kansoku)
    assert Code.ensure_loaded?(Kansoku.Router)
    assert Code.ensure_loaded?(KansokuWeb)
    assert macro_exported?(Kansoku.Router, :kansoku, 1)
    assert macro_exported?(Kansoku.Router, :kansoku, 2)
  end

  test "publishes the Kansoku package identity over Jizoku" do
    project = Mix.Project.config()

    assert project[:package][:name] == "kansoku"
    assert project[:source_url] == "https://github.com/agentjido/kansoku"
    assert Enum.any?(project[:deps], &match?({:jizoku, _requirement}, &1))
  end

  test "ships only Kansoku assets" do
    assert File.exists?(Application.app_dir(:kansoku, "priv/static/kansoku.css"))

    legacy_asset = "squid" <> "_" <> "sonar.css"
    refute File.exists?(Application.app_dir(:kansoku, "priv/static/#{legacy_asset}"))
  end
end
