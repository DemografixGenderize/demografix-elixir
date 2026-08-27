defmodule Demografix.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/DemografixGenderize/demografix-elixir"

  def project do
    [
      app: :demografix,
      version: @version,
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Demografix",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Predict gender, age, and nationality from names. Official Elixir client for the " <>
      "genderize.io, agify.io, and nationalize.io APIs: look up one name or batch up to 100 " <>
      "names per request for bulk demographic analysis, optionally scoped to a country, " <>
      "with quota on every response."
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Demografix"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://genderize.io/documentation/api"
      },
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}"
    ]
  end
end
