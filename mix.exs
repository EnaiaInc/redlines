defmodule Redlines.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/EnaiaInc/redlines"

  def project do
    [
      app: :redlines,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:sweet_xml, "~> 0.7"},
      {:pdf_redlines, "~> 0.6"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39.3", only: :dev, runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Extract and normalize tracked changes (redlines) from DOCX and PDFs."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/redlines/changelog.html"
      },
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        ".credo.exs",
        ".dialyzer_ignore.exs",
        ".editorconfig",
        ".formatter.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "Redlines",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["CHANGELOG.md"]
    ]
  end

  defp dialyzer do
    [
      plt_ignore_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
