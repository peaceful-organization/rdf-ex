defmodule RDF.Mixfile do
  use Mix.Project

  @repo_url "https://github.com/rdf-elixir/rdf-ex"

  @version File.read!("VERSION") |> String.trim()

  def project do
    [
      app: :rdf,
      version: @version,
      elixir: "~> 1.10",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:protocol_ex],
      aliases: aliases(),

      # Dialyzer
      dialyzer: dialyzer(),

      # Hex
      package: package(),
      description: description(),

      # Docs
      name: "RDF.ex",
      docs: [
        main: "RDF",
        source_url: @repo_url,
        source_ref: "v#{@version}",
        extras: ["CHANGELOG.md"]
      ],

      # ExCoveralls
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        earl_reports: :test
      ]
    ]
  end

  defp description do
    """
    An implementation of RDF for Elixir.
    """
  end

  defp package do
    [
      maintainers: ["Marcel Otto"],
      licenses: ["MIT"],
      links: %{
        "Homepage" => "https://rdf-elixir.dev",
        "GitHub" => @repo_url,
        "Changelog" => @repo_url <> "/blob/master/CHANGELOG.md"
      },
      files: ~w[lib src/*.xrl src/*.yrl priv mix.exs .formatter.exs VERSION *.md]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:decimal, "~> 1.5 or ~> 2.0"},
      {:protocol_ex, "~> 0.4.4"},
      {:elixir_uuid, "~> 1.2", optional: true},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:excoveralls, "~> 0.14", only: :test},
      {:benchee, "~> 1.1", only: :bench}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore"
    ]
  end

  defp aliases do
    [
      earl_reports: &earl_reports/1
    ]
  end

  defp earl_reports(_) do
    files = [
      "test/acceptance/ntriples_w3c_test.exs",
      "test/acceptance/ntriples_star_w3c_test.exs",
      "test/acceptance/nquads_w3c_test.exs",
      "test/acceptance/turtle_w3c_test.exs",
      "test/acceptance/turtle_star_w3c_syntax_test.exs",
      "test/acceptance/turtle_star_w3c_eval_test.exs"
    ]

    Mix.Task.run("test", ["--formatter", "EarlFormatter", "--seed", "0"] ++ files)
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
