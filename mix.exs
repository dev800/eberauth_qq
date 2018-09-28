defmodule Ueberauth.QQ.Mixfile do
  use Mix.Project

  @version "0.0.1"

  def project do
    [
      app: :ueberauth_qq,
      version: @version,
      name: "Ueberauth.QQ",
      package: package(),
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/dev800/ueberauth_qq",
      homepage_url: "https://github.com/dev800/ueberauth_qq",
      description: description(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [applications: [:logger, :ueberauth, :oauth2]]
  end

  defp deps do
    [
      {:timex, "~> 3.0"},
      {:httpoison, "~> 1.3"},
      {:oauth2, "~> 0.9"},
      {:ueberauth, "~> 0.4"},
      {:jason, "~> 1.0"},
      {:credo, "~> 0.8", only: [:dev, :test]},

      # docs dependencies
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp docs do
    [extras: ["README.md"]]
  end

  defp description do
    "An Ueberauth strategy for using QQ to authenticate your users."
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["dev800"],
      licenses: ["MIT"],
      links: %{GitHub: "https://github.com/dev800/ueberauth_qq"}
    ]
  end
end
