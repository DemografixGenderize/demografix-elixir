defmodule Demografix.MixProject do
  use Mix.Project

  @version "0.1.0"
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
    "Official Elixir client for the Demografix APIs: genderize, agify, and nationalize."
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
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
