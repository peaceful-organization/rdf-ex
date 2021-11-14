defmodule RDF.Graph do
  @moduledoc """
  A set of RDF triples with an optional name.

  `RDF.Graph` implements:

  - Elixir's `Access` behaviour
  - Elixir's `Enumerable` protocol
  - Elixir's `Inspect` protocol
  - the `RDF.Data` protocol

  """

  defstruct name: nil, descriptions: %{}, prefixes: nil, base_iri: nil

  @behaviour Access

  alias RDF.{Description, IRI, PrefixMap, PropertyMap}
  alias RDF.Star.Statement

  import RDF.Utils

  @type graph_description :: %{Statement.subject() => Description.t()}

  @type t :: %__MODULE__{
          name: IRI.t() | nil,
          descriptions: graph_description,
          prefixes: PrefixMap.t() | nil,
          base_iri: IRI.t() | nil
        }

  @type input ::
          Statement.coercible_t()
          | {
              Statement.coercible_subject(),
              Description.input()
            }
          | Description.t()
          | t
          | %{
              Statement.coercible_subject() => %{
                Statement.coercible_predicate() =>
                  Statement.coercible_object() | [Statement.coercible_object()]
              }
            }
          | list(input)
  @type update_description_fun :: (Description.t() -> Description.t())

  @type get_and_update_description_fun :: (Description.t() -> {Description.t(), input} | :pop)

  @doc """
  Creates an empty unnamed `RDF.Graph`.
  """
  @spec new :: t
  def new, do: %__MODULE__{}

  @doc """
  Creates an `RDF.Graph`.

  If a keyword list with options is given an empty graph is created.
  Otherwise an unnamed graph initialized with the given data is created.

  See `new/2` for available arguments and the different ways to provide data.

  ## Examples

      RDF.Graph.new(name: EX.GraphName)

      RDF.Graph.new(init: {EX.S, EX.p, EX.O})

      RDF.Graph.new({EX.S, EX.p, EX.O})

  """
  @spec new(input | keyword) :: t
  def new(data_or_opts)

  def new(data_or_opts) when is_list(data_or_opts) and length(data_or_opts) != 0 do
    if Keyword.keyword?(data_or_opts) do
      {data, options} = Keyword.pop(data_or_opts, :init)
      new(data, options)
    else
      new(data_or_opts, [])
    end
  end

  def new(data), do: new(data, [])

  @doc """
  Creates an `RDF.Graph` initialized with data.

  The initial RDF triples can be provided

  - as a single statement tuple
  - a nested subject-predicate-object map
  - a `RDF.Description`
  - a `RDF.Graph`
  - or a list with any combination of the former

  Available options:

  - `name`: the name of the graph to be created
  - `prefixes`: some prefix mappings which should be stored alongside the graph
    and will be used for example when serializing in a format with prefix support
  - `base_iri`: a base IRI which should be stored alongside the graph
    and will be used for example when serializing in a format with base IRI support
  - `init`: some data with which the graph should be initialized; the data can be
    provided in any form accepted by `add/3` and above that also with a function returning
    the initialization data in any of these forms

  ## Examples

      RDF.Graph.new({EX.S, EX.p, EX.O})
      RDF.Graph.new({EX.S, EX.p, EX.O}, name: EX.GraphName)
      RDF.Graph.new({EX.S, EX.p, [EX.O1, EX.O2]})
      RDF.Graph.new([{EX.S1, EX.p1, EX.O1}, {EX.S2, EX.p2, EX.O2}])
      RDF.Graph.new(RDF.Description.new(EX.S, EX.P, EX.O))
      RDF.Graph.new([graph, description, triple])
      RDF.Graph.new({EX.S, EX.p, EX.O}, name: EX.GraphName, base_iri: EX.base)

  """
  @spec new(input, keyword) :: t
  def new(data, opts)

  def new(%__MODULE__{} = graph, opts) do
    %__MODULE__{graph | name: opts |> Keyword.get(:name) |> RDF.coerce_graph_name()}
    |> add_prefixes(Keyword.get(opts, :prefixes))
    |> set_base_iri(Keyword.get(opts, :base_iri))
  end

  def new(data, opts) do
    new()
    |> new(opts)
    |> init(data, opts)
  end

  defp init(graph, nil, _), do: graph
  defp init(graph, fun, opts) when is_function(fun), do: add(graph, fun.(), opts)
  defp init(graph, data, opts), do: add(graph, data, opts)

  @doc """
  Removes all triples from `graph`.

  This function is useful for getting an empty graph based on the settings of
  another graph, as this function keeps graph name, base IRI and default prefixes
  as they are and just removes the triples.
  """
  @spec clear(t) :: t
  def clear(%__MODULE__{} = graph) do
    %__MODULE__{graph | descriptions: %{}}
  end

  @doc """
  Returns the graph name IRI of `graph`.
  """
  @spec name(t) :: Statement.graph_name()
  def name(%__MODULE__{} = graph), do: graph.name

  @doc """
  Changes the graph name of `graph`.
  """
  @spec change_name(t, Statement.coercible_graph_name()) :: t
  def change_name(%__MODULE__{} = graph, new_name) do
    %__MODULE__{graph | name: RDF.coerce_graph_name(new_name)}
  end

  @doc """
  Adds triples to a `RDF.Graph`.

  The `input` can be provided

  - as a single statement tuple
  - a nested subject-predicate-object map
  - a `RDF.Description`
  - a `RDF.Graph`
  - or a list with any combination of the former

  When the statements to be added are given as another `RDF.Graph`,
  the graph name must not match graph name of the graph to which the statements
  are added. As opposed to that, `RDF.Data.merge/2` will produce a `RDF.Dataset`
  containing both graphs.

  Also when the statements to be added are given as another `RDF.Graph`, the
  prefixes of this graph will be added. In case of conflicting prefix mappings
  the original prefix from `graph` will be kept.

  RDF-star annotations to be added to all of the given statements can be specified with
  the `:add_annotations`, `:put_annotations` or `:put_annotation_properties` keyword
  options. They have different addition semantics similar to the `add_annotations/3`,
  `put_annotations/3` and `put_annotation_properties/3` counterparts.
  """
  @spec add(t, input, keyword) :: t
  def add(graph, input, opts \\ [])

  def add(%__MODULE__{} = graph, {subject, predications}, opts),
    do: do_add(graph, RDF.coerce_subject(subject), predications, opts)

  def add(%__MODULE__{} = graph, {subject, _, _} = triple, opts),
    do: do_add(graph, RDF.coerce_subject(subject), triple, opts)

  def add(graph, {subject, predicate, object, _}, opts),
    do: add(graph, {subject, predicate, object}, opts)

  def add(%__MODULE__{} = graph, %Description{} = description, opts) do
    if Description.count(description) > 0 do
      do_add(graph, description.subject, description, opts)
    else
      graph
    end
  end

  def add(graph, %__MODULE__{descriptions: descriptions, prefixes: prefixes}, opts) do
    # normalize the annotations here, so we don't have to do this repeatedly in do_add/4
    opts = RDF.Star.Graph.normalize_annotation_opts(opts)

    graph =
      Enum.reduce(descriptions, graph, fn {_, description}, graph ->
        add(graph, description, opts)
      end)

    if prefixes do
      add_prefixes(graph, prefixes, :ignore)
    else
      graph
    end
  end

  if Version.match?(System.version(), "~> 1.10") do
    def add(graph, input, opts) when is_list(input) or (is_map(input) and not is_struct(input)) do
      Enum.reduce(input, graph, &add(&2, &1, opts))
    end
  else
    def add(_, %_{}, _), do: raise(ArgumentError, "structs are not allowed as input")

    def add(graph, input, opts) when is_list(input) or is_map(input) do
      Enum.reduce(input, graph, &add(&2, &1, opts))
    end
  end

  defp do_add(%__MODULE__{descriptions: descriptions} = graph, subject, statements, opts) do
    %__MODULE__{
      graph
      | descriptions:
          lazy_map_update(
            descriptions,
            subject,
            # when new: create and initialize description with statements
            fn -> Description.new(subject, Keyword.put(opts, :init, statements)) end,
            # when update: merge statements description
            fn description -> Description.add(description, statements, opts) end
          )
    }
    |> RDF.Star.Graph.handle_addition_annotations({subject, statements}, opts)
  end

  @doc """
  Adds statements to a `RDF.Graph` overwriting existing statements with the subjects given in the `input` data.

  When the statements to be added are given as another `RDF.Graph`, the prefixes
  of this graph will be added. In case of conflicting prefix mappings the
  original prefix from `graph` will be kept.

  RDF-star annotations to be added to all of the given statements can be specified with
  the `:add_annotations`, `:put_annotations` or `:put_annotation_properties` keyword
  options. They have different addition semantics similar to the `add_annotations/3`,
  `put_annotations/3` and `put_annotation_properties/3` counterparts.

  What should happen with the annotations of statement which got delete during the
  overwrite, can be controlled with these keyword options:

  - `:delete_annotations_on_deleted`: deletes all or some annotations of the deleted
    statements (see `delete_annotations/3` on possible values)
  - `:add_annotations_on_deleted`, `:put_annotations_on_deleted`,
    `:put_annotation_properties_on_deleted`: add annotations about the deleted
    statements with the respective addition semantics similar to the keyword
    options with the `_on_deleted` suffix mentioned above

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}])
      ...> |> RDF.Graph.put([{EX.S1, EX.P3, EX.O3}])
      RDF.Graph.new([{EX.S1, EX.P3, EX.O3}, {EX.S2, EX.P2, EX.O2}])

  """
  @spec put(t, input, keyword) :: t
  def put(graph, input, opts \\ [])

  def put(%__MODULE__{} = graph, %__MODULE__{} = input, opts) do
    new_graph = %__MODULE__{
      graph
      | descriptions:
          Enum.reduce(
            input.descriptions,
            graph.descriptions,
            fn {subject, description}, descriptions ->
              Map.put(descriptions, subject, description)
            end
          )
    }

    if input.prefixes do
      add_prefixes(new_graph, input.prefixes, :ignore)
    else
      new_graph
    end
    |> RDF.Star.Graph.handle_overwrite_annotations(graph, input, opts)
    |> RDF.Star.Graph.handle_addition_annotations(input, opts)
  end

  def put(%__MODULE__{} = graph, input, opts) do
    put(graph, new() |> add(input, RDF.Star.Graph.clear_annotation_opts(opts)), opts)
  end

  @doc """
  Adds statements to a `RDF.Graph` and overwrites all existing statements with the same subject-predicate combinations given in the `input` data.

  When the statements to be added are given as another `RDF.Graph`, the prefixes
  of this graph will be added. In case of conflicting prefix mappings the
  original prefix from `graph` will be kept.

  RDF-star annotations to be added to all of the given statements can be specified with
  the `:add_annotations`, `:put_annotations` or `:put_annotation_properties` keyword
  options. They have different addition semantics similar to the `add_annotations/3`,
  `put_annotations/3` and `put_annotation_properties/3` counterparts.

  What should happen with the annotations of statement which got delete during the
  overwrite, can be controlled with these keyword options:

  - `:delete_annotations_on_deleted`: deletes all or some annotations of the deleted
    statements (see `delete_annotations/3` on possible values)
  - `:add_annotations_on_deleted`, `:put_annotations_on_deleted`,
    `:put_annotation_properties_on_deleted`: add annotations about the deleted
    statements with the respective addition semantics similar to the keyword
    options with the `_on_deleted` suffix mentioned above

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}])
      ...> |> RDF.Graph.put_properties([{EX.S1, EX.P2, EX.O3}, {EX.S2, EX.P2, EX.O3}])
      RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S1, EX.P2, EX.O3}, {EX.S2, EX.P2, EX.O3}])

  """
  @spec put_properties(t, input, keyword) :: t
  def put_properties(graph, input, opts \\ [])

  def put_properties(%__MODULE__{} = graph, %__MODULE__{} = input, opts) do
    new_graph = %__MODULE__{
      graph
      | descriptions:
          Enum.reduce(
            input.descriptions,
            graph.descriptions,
            fn {subject, description}, descriptions ->
              Map.update(
                descriptions,
                subject,
                description,
                fn current -> Description.put(current, description, opts) end
              )
            end
          )
    }

    if input.prefixes do
      add_prefixes(new_graph, input.prefixes, :ignore)
    else
      new_graph
    end
    |> RDF.Star.Graph.handle_overwrite_annotations(graph, input, opts)
    |> RDF.Star.Graph.handle_addition_annotations(input, opts)
  end

  def put_properties(%__MODULE__{} = graph, input, opts) do
    put_properties(graph, new() |> add(input, RDF.Star.Graph.clear_annotation_opts(opts)), opts)
  end

  @doc """
  Deletes statements from a `RDF.Graph`.

  When the statements to be deleted are given as another `RDF.Graph`,
  the graph name must not match graph name of the graph from which the statements
  are deleted. If you want to delete only statements with matching graph names, you can
  use `RDF.Data.delete/2`.

  The optional `:delete_annotations` keyword option allows to set which of
  RDF-star annotations of the deleted statements should be deleted.
  Any of the possible values of `delete_annotations/3` can be provided here.
  By default no annotations of the deleted statements will be removed.
  Alternatively, the `:add_annotations`, `:put_annotations` or `:put_annotation_properties`
  keyword options can be used to add annotations about the deleted statements
  with the addition semantics similar to the respective `add_annotations/3`,
  `put_annotations/3` and `put_annotation_properties/3` counterparts.
  """
  @spec delete(t, input, keyword) :: t
  def delete(graph, input, opts \\ [])

  def delete(%__MODULE__{} = graph, {subject, _, _} = triple, opts),
    do: do_delete(graph, RDF.coerce_subject(subject), triple, opts)

  def delete(%__MODULE__{} = graph, {subject, predications}, opts),
    do: do_delete(graph, RDF.coerce_subject(subject), predications, opts)

  def delete(graph, {subject, predicate, object, _}, opts),
    do: delete(graph, {subject, predicate, object}, opts)

  def delete(%__MODULE__{} = graph, %Description{} = description, opts),
    do: do_delete(graph, description.subject, description, opts)

  def delete(%__MODULE__{} = graph, %__MODULE__{} = input, opts) do
    Enum.reduce(input.descriptions, graph, fn {_, description}, graph ->
      delete(graph, description, opts)
    end)
  end

  if Version.match?(System.version(), "~> 1.10") do
    def delete(%__MODULE__{} = graph, input, opts)
        when is_list(input) or (is_map(input) and not is_struct(input)) do
      Enum.reduce(input, graph, &delete(&2, &1, opts))
    end
  else
    def delete(_, %_{}, _), do: raise(ArgumentError, "structs are not allowed as input")

    def delete(%__MODULE__{} = graph, input, opts) when is_list(input) or is_map(input) do
      Enum.reduce(input, graph, &delete(&2, &1, opts))
    end
  end

  defp do_delete(%__MODULE__{descriptions: descriptions} = graph, subject, input, opts) do
    if description = descriptions[subject] do
      new_description = Description.delete(description, input, opts)

      %__MODULE__{
        graph
        | descriptions:
            if Enum.empty?(new_description) do
              Map.delete(descriptions, subject)
            else
              Map.put(descriptions, subject, new_description)
            end
      }
    else
      graph
    end
    |> RDF.Star.Graph.handle_deletion_annotations({subject, input}, opts)
  end

  @doc """
  Deletes all statements with the given `subjects`.

  If `subjects` contains subjects that are not in `graph`, they're simply ignored.

  The optional `:delete_annotations` keyword option allows to set which of
  RDF-star annotations of the deleted statements should be deleted.
  Any of the possible values of `delete_annotations/3` can be provided here.
  By default no annotations of the deleted statements will be removed.
  Alternatively, the `:add_annotations`, `:put_annotations` or `:put_annotation_properties`
  keyword options can be used to add annotations about the deleted statements
  with the addition semantics similar to the respective `add_annotations/3`,
  `put_annotations/3` and `put_annotation_properties/3` counterparts.
  """
  @spec delete_descriptions(
          t,
          Statement.coercible_subject() | [Statement.coercible_subject()],
          keyword
        ) :: t
  def delete_descriptions(graph, subjects, opts \\ [])

  def delete_descriptions(%__MODULE__{} = graph, subjects, opts) when is_list(subjects) do
    Enum.reduce(subjects, graph, &delete_descriptions(&2, &1, opts))
  end

  def delete_descriptions(%__MODULE__{} = graph, subject, opts) do
    case Map.pop(graph.descriptions, RDF.coerce_subject(subject)) do
      {nil, _} ->
        graph

      {deleted_description, descriptions} ->
        %__MODULE__{graph | descriptions: descriptions}
        |> RDF.Star.Graph.handle_deletion_annotations(deleted_description, opts)
    end
  end

  defdelegate delete_subjects(graph, subjects), to: __MODULE__, as: :delete_descriptions
  defdelegate delete_subjects(graph, subjects, opts), to: __MODULE__, as: :delete_descriptions

  @doc """
  Adds RDF-star annotations to the given set of statements.

  The set of `statements` can be given in any input form (see `add/3`).

  The predicate-objects pairs to be added as annotations can be given as a tuple,
  a list of tuples or a map.
  """
  @spec add_annotations(t, input, Description.input() | nil) :: t
  defdelegate add_annotations(graph, statements, annotations), to: RDF.Star.Graph

  @doc """
  Adds RDF-star annotations to the given set of statements overwriting all existing annotations.

  The set of `statements` can be given in any input form (see `add/3`).

  The predicate-objects pairs to be added as annotations can be given as a tuple,
  a list of tuples or a map.
  """
  @spec put_annotations(t, input, Description.input() | nil) :: t
  defdelegate put_annotations(graph, statements, annotations), to: RDF.Star.Graph

  @doc """
  Adds RDF-star annotations to the given set of statements overwriting all existing annotations with the given properties.

  The set of `statements` can be given in any input form (see `add/3`).

  The predicate-objects pairs to be added as annotations can be given as a tuple,
  a list of tuples or a map.
  """
  @spec put_annotation_properties(t, input, Description.input() | nil) :: t
  defdelegate put_annotation_properties(graph, statements, annotations), to: RDF.Star.Graph

  @doc """
  Deletes RDF-star annotations of a given set of statements.

  The `statements` can be given in any input form (see `add/3`).

  If `true` is given as the third argument or is `delete_annotations/2` is used,
  all annotations of the given `statements` are deleted.

  If a single predicate or list of predicates is given only statements with
  these predicates from the annotations of the given `statements` are deleted.
  """
  @spec delete_annotations(
          t,
          input,
          boolean | Statement.coercible_predicate() | [Statement.coercible_predicate()]
        ) :: t
  defdelegate delete_annotations(graph, statements), to: RDF.Star.Graph
  defdelegate delete_annotations(graph, statements, delete), to: RDF.Star.Graph

  @doc """
  Updates the description of the `subject` in `graph` with the given function.

  If `subject` is present in `graph` with `description` as description,
  `fun` is invoked with argument `description` and its result is used as the new
  description of `subject`. If `subject` is not present in `graph`,
  `initial` is inserted as the description of `subject`. If no `initial` value is
  given, the `graph` remains unchanged. If `nil` is returned by `fun`, the
  respective description will be removed from `graph`.

  The initial value and the returned objects by the update function will be tried
  te coerced to proper RDF descriptions before added. If the initial or returned
  description is a `RDF.Description` with another subject, the respective
  statements are added with `subject` as subject.

  ## Examples

      iex> RDF.Graph.new({EX.S, EX.p, EX.O})
      ...> |> RDF.Graph.update(EX.S,
      ...>      fn description -> Description.add(description, {EX.p, EX.O2})
      ...>    end)
      RDF.Graph.new([{EX.S, EX.p, EX.O}, {EX.S, EX.p, EX.O2}])
      iex> RDF.Graph.new({EX.S, EX.p, EX.O})
      ...> |> RDF.Graph.update(EX.S,
      ...>      fn _ -> Description.new(EX.S2, init: {EX.p2, EX.O2})
      ...>    end)
      RDF.Graph.new([{EX.S, EX.p2, EX.O2}])
      iex> RDF.Graph.new()
      ...> |> RDF.Graph.update(EX.S, Description.new(EX.S, init: {EX.p, EX.O}),
      ...>      fn description -> Description.add(description, {EX.p, EX.O2})
      ...>    end)
      RDF.Graph.new([{EX.S, EX.p, EX.O}])

  """
  @spec update(
          t,
          Statement.coercible_subject(),
          Description.input() | nil,
          update_description_fun
        ) :: t
  def update(%__MODULE__{} = graph, subject, initial \\ nil, fun) do
    subject = RDF.coerce_subject(subject)

    case get(graph, subject) do
      nil ->
        if initial do
          add(graph, Description.new(subject, init: initial))
        else
          graph
        end

      description ->
        description
        |> fun.()
        |> case do
          nil ->
            delete_descriptions(graph, subject)

          new_description ->
            graph
            |> delete_descriptions(subject)
            |> add(Description.new(subject, init: new_description))
        end
    end
  end

  @doc """
  Fetches the description of the given subject.

  When the subject can not be found `:error` is returned.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}])
      ...> |> RDF.Graph.fetch(EX.S1)
      {:ok, RDF.Description.new(EX.S1, init: {EX.P1, EX.O1})}
      iex> RDF.Graph.new() |> RDF.Graph.fetch(EX.foo)
      :error

  """
  @impl Access
  @spec fetch(t, Statement.coercible_subject()) :: {:ok, Description.t()} | :error
  def fetch(%__MODULE__{} = graph, subject) do
    Access.fetch(graph.descriptions, RDF.coerce_subject(subject))
  end

  @doc """
  Gets the description of the given subject.

  When the subject can not be found the optionally given default value or `nil` is returned.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}])
      ...> |> RDF.Graph.get(EX.S1)
      RDF.Description.new(EX.S1, init: {EX.P1, EX.O1})
      iex> RDF.Graph.new() |> RDF.Graph.get(EX.Foo)
      nil
      iex> RDF.Graph.new() |> RDF.Graph.get(EX.Foo, :bar)
      :bar

  """
  @spec get(t, Statement.coercible_subject(), Description.t() | nil) :: Description.t() | nil
  def get(%__MODULE__{} = graph, subject, default \\ nil) do
    case fetch(graph, subject) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defdelegate description(graph, subject), to: __MODULE__, as: :get

  @doc """
  All `RDF.Description`s within a `RDF.Graph`.
  """
  @spec descriptions(t) :: [Description.t()]
  def descriptions(%__MODULE__{} = graph) do
    Map.values(graph.descriptions)
  end

  @doc """
  Returns the `RDF.Graph` of all annotations.

  Note: The graph includes only triples where the subject is a quoted triple.
  Triples where only the object is a quoted triple are NOT included.
  """
  @spec annotations(t) :: t
  defdelegate annotations(graph), to: RDF.Star.Graph

  @doc """
  Returns the `RDF.Graph` without all annotations.

  Note: This function excludes only triples where the subject is a quoted triple.
  If you want to exclude also triples where the object is a quoted triple,
  you'll have to use `RDF.Graph.without_quoted_triples/1`.
  """
  @spec without_annotations(t) :: t
  defdelegate without_annotations(graph), to: RDF.Star.Graph

  @doc """
  Returns the `RDF.Graph` without all statements including quoted triples on subject or object position.

  This function is relatively costly, since it requires a full walk-through of all triples.
  In many cases quoted triples are only used on subject position, where you can use
  `RDF.Graph.without_annotations/1`.
  """
  @spec without_quoted_triples(t) :: t
  defdelegate without_quoted_triples(graph), to: RDF.Star.Graph

  @doc """
  Gets and updates the description of the given subject, in a single pass.

  Invokes the passed function on the `RDF.Description` of the given subject;
  this function should return either `{description_to_return, new_description}` or `:pop`.

  If the passed function returns `{description_to_return, new_description}`, the
  return value of `get_and_update` is `{description_to_return, new_graph}` where
  `new_graph` is the input `Graph` updated with `new_description` for
  the given subject.

  If the passed function returns `:pop` the description for the given subject is
  removed and a `{removed_description, new_graph}` tuple gets returned.

  ## Examples

      iex> RDF.Graph.new({EX.S, EX.P, EX.O})
      ...> |> RDF.Graph.get_and_update(EX.S, fn current_description ->
      ...>      {current_description, {EX.P, EX.NEW}}
      ...>    end)
      {RDF.Description.new(EX.S, init: {EX.P, EX.O}), RDF.Graph.new({EX.S, EX.P, EX.NEW})}

  """
  @impl Access
  @spec get_and_update(t, Statement.coercible_subject(), get_and_update_description_fun) ::
          {Description.t(), input}
  def get_and_update(%__MODULE__{} = graph, subject, fun) do
    subject = RDF.coerce_subject(subject)

    case fun.(get(graph, subject)) do
      {old_description, new_description} ->
        {old_description, put(graph, {subject, new_description})}

      :pop ->
        pop(graph, subject)

      other ->
        raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
    end
  end

  @doc """
  Pops an arbitrary triple from a `RDF.Graph`.
  """
  @spec pop(t) :: {Statement.t() | nil, t}
  def pop(graph)

  def pop(%__MODULE__{descriptions: descriptions} = graph)
      when descriptions == %{},
      do: {nil, graph}

  def pop(%__MODULE__{descriptions: descriptions} = graph) do
    # TODO: Find a faster way ...
    [{subject, description}] = Enum.take(descriptions, 1)
    {triple, popped_description} = Description.pop(description)

    popped =
      if Enum.empty?(popped_description),
        do: descriptions |> Map.delete(subject),
        else: descriptions |> Map.put(subject, popped_description)

    {triple, %__MODULE__{graph | descriptions: popped}}
  end

  @doc """
  Pops the description of the given subject.

  When the subject can not be found the optionally given default value or `nil` is returned.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}])
      ...> |> RDF.Graph.pop(EX.S1)
      {RDF.Description.new(EX.S1, init: {EX.P1, EX.O1}), RDF.Graph.new({EX.S2, EX.P2, EX.O2})}
      iex> RDF.Graph.new({EX.S, EX.P, EX.O}) |> RDF.Graph.pop(EX.Missing)
      {nil, RDF.Graph.new({EX.S, EX.P, EX.O})}

  """
  @impl Access
  @spec pop(t, Statement.coercible_subject()) :: {Description.t() | nil, t}
  def pop(%__MODULE__{} = graph, subject) do
    case Access.pop(graph.descriptions, RDF.coerce_subject(subject)) do
      {nil, _} ->
        {nil, graph}

      {description, new_descriptions} ->
        {description, %__MODULE__{graph | descriptions: new_descriptions}}
    end
  end

  @doc """
  The number of subjects within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}])
      ...> |> RDF.Graph.subject_count()
      2

  """
  @spec subject_count(t) :: non_neg_integer
  def subject_count(%__MODULE__{} = graph) do
    Enum.count(graph.descriptions)
  end

  @doc """
  The number of statements within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}])
      ...> |> RDF.Graph.statement_count()
      3

  """
  @spec statement_count(t) :: non_neg_integer
  def statement_count(%__MODULE__{} = graph) do
    Enum.reduce(graph.descriptions, 0, fn {_subject, description}, count ->
      count + Description.count(description)
    end)
  end

  defdelegate triple_count(graph), to: __MODULE__, as: :statement_count

  @doc """
  The set of all subjects used in the statements within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}])
      ...> |> RDF.Graph.subjects()
      MapSet.new([RDF.iri(EX.S1), RDF.iri(EX.S2)])
  """
  def subjects(%__MODULE__{} = graph) do
    graph.descriptions |> Map.keys() |> MapSet.new()
  end

  @doc """
  The set of all properties used in the predicates of the statements within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}])
      ...> |> RDF.Graph.predicates()
      MapSet.new([EX.p1, EX.p2])
  """
  def predicates(%__MODULE__{} = graph) do
    Enum.reduce(graph.descriptions, MapSet.new(), fn {_, description}, acc ->
      description
      |> Description.predicates()
      |> MapSet.union(acc)
    end)
  end

  @doc """
  The set of all resources used in the objects within a `RDF.Graph`.

  Note: This function does collect only IRIs and BlankNodes, not Literals.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S3, EX.p1, EX.O2},
      ...>   {EX.S4, EX.p2, RDF.bnode(:bnode)},
      ...>   {EX.S5, EX.p3, "foo"}])
      ...> |> RDF.Graph.objects()
      MapSet.new([RDF.iri(EX.O1), RDF.iri(EX.O2), RDF.bnode(:bnode)])
  """
  def objects(%__MODULE__{} = graph) do
    Enum.reduce(graph.descriptions, MapSet.new(), fn {_, description}, acc ->
      description
      |> Description.objects()
      |> MapSet.union(acc)
    end)
  end

  @doc """
  The set of all resources used within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p1, EX.O2},
      ...>   {EX.S2, EX.p2, RDF.bnode(:bnode)},
      ...>   {EX.S3, EX.p1, "foo"}])
      ...> |> RDF.Graph.resources()
      MapSet.new([RDF.iri(EX.S1), RDF.iri(EX.S2), RDF.iri(EX.S3),
        RDF.iri(EX.O1), RDF.iri(EX.O2), RDF.bnode(:bnode), EX.p1, EX.p2])
  """
  def resources(graph = %__MODULE__{} = graph) do
    Enum.reduce(graph.descriptions, MapSet.new(), fn {_, description}, acc ->
      description
      |> Description.resources()
      |> MapSet.union(acc)
    end)
    |> MapSet.union(subjects(graph))
  end

  @doc """
  The list of all statements within a `RDF.Graph`.

  ## Examples

        iex> RDF.Graph.new([
        ...>   {EX.S1, EX.p1, EX.O1},
        ...>   {EX.S2, EX.p2, EX.O2},
        ...>   {EX.S1, EX.p2, EX.O3}])
        ...> |> RDF.Graph.triples()
        [{RDF.iri(EX.S1), RDF.iri(EX.p1), RDF.iri(EX.O1)},
         {RDF.iri(EX.S1), RDF.iri(EX.p2), RDF.iri(EX.O3)},
         {RDF.iri(EX.S2), RDF.iri(EX.p2), RDF.iri(EX.O2)}]
  """
  @spec triples(t) :: [Statement.t()]
  def triples(%__MODULE__{} = graph, opts \\ []) do
    if Keyword.get(opts, :filter_star, false) do
      Enum.flat_map(graph.descriptions, fn
        {subject, _} when is_tuple(subject) -> []
        {_, description} -> Description.triples(description, opts)
      end)
    else
      Enum.flat_map(graph.descriptions, fn {_, description} ->
        Description.triples(description, opts)
      end)
    end
  end

  defdelegate statements(graph, opts \\ []), to: __MODULE__, as: :triples

  @doc """
  Checks if the given `input` statements exist within `graph`.
  """
  @spec include?(t, input, keyword) :: boolean
  def include?(graph, input, opts \\ [])

  def include?(%__MODULE__{} = graph, {subject, _, _} = triple, opts),
    do: do_include?(graph, RDF.coerce_subject(subject), triple, opts)

  def include?(graph, {subject, predicate, object, _}, opts),
    do: include?(graph, {subject, predicate, object}, opts)

  def include?(%__MODULE__{} = graph, {subject, predications}, opts),
    do: do_include?(graph, RDF.coerce_subject(subject), predications, opts)

  def include?(%__MODULE__{} = graph, %Description{subject: subject} = description, opts),
    do: do_include?(graph, subject, description, opts)

  def include?(graph, %__MODULE__{} = other_graph, opts) do
    other_graph
    |> descriptions()
    |> Enum.all?(&include?(graph, &1, opts))
  end

  if Version.match?(System.version(), "~> 1.10") do
    def include?(graph, input, opts)
        when is_list(input) or (is_map(input) and not is_struct(input)) do
      Enum.all?(input, &include?(graph, &1, opts))
    end
  else
    def include?(_, %_{}, _), do: raise(ArgumentError, "structs are not allowed as input")

    def include?(graph, input, opts) when is_list(input) or is_map(input) do
      Enum.all?(input, &include?(graph, &1, opts))
    end
  end

  defp do_include?(%__MODULE__{descriptions: descriptions}, subject, input, opts) do
    if description = descriptions[subject] do
      Description.include?(description, input, opts)
    else
      false
    end
  end

  @doc """
  Checks if a `RDF.Graph` contains statements about the given resource.

  ## Examples

        iex> RDF.Graph.new([{EX.S1, EX.p1, EX.O1}]) |> RDF.Graph.describes?(EX.S1)
        true
        iex> RDF.Graph.new([{EX.S1, EX.p1, EX.O1}]) |> RDF.Graph.describes?(EX.S2)
        false
  """
  @spec describes?(t, Statement.coercible_subject()) :: boolean
  def describes?(%__MODULE__{} = graph, subject) do
    Map.has_key?(graph.descriptions, RDF.coerce_subject(subject))
  end

  @doc """
  Creates a graph from another one by limiting its statements to those using one of the given `subjects`.

  If `subjects` contains IRIs that are not used in the `graph`, they're simply ignored.

  The optional `properties` argument allows to limit also properties of the subject descriptions.

  If `nil` is passed as the `subjects`, the subjects will not be limited.
  """
  @spec take(
          t,
          [Statement.coercible_subject()] | Enum.t() | nil,
          [Statement.coercible_predicate()] | Enum.t() | nil
        ) :: t
  def take(graph, subjects, properties \\ nil)

  def take(%__MODULE__{} = graph, nil, nil), do: graph

  def take(%__MODULE__{descriptions: descriptions} = graph, subjects, nil) do
    %__MODULE__{
      graph
      | descriptions: Map.take(descriptions, Enum.map(subjects, &RDF.coerce_subject/1))
    }
  end

  def take(%__MODULE__{} = graph, subjects, properties) do
    graph = take(graph, subjects, nil)

    %__MODULE__{
      graph
      | descriptions:
          Map.new(graph.descriptions, fn {subject, description} ->
            {subject, Description.take(description, properties)}
          end)
    }
  end

  @doc """
  Execute the given `query` against the given `graph`.

  This is just a convenience delegator function to `RDF.Query.execute!/3` with
  the first two arguments swapped so it can be used in a pipeline on a `RDF.Graph`.

  See `RDF.Query.execute/3` and `RDF.Query.execute!/3` for more information and examples.
  """
  def query(graph, query, opts \\ []) do
    RDF.Query.execute!(query, graph, opts)
  end

  @doc """
  Returns a `Stream` for the execution of the given `query` against the given `graph`.

  This is just a convenience delegator function to `RDF.Query.stream!/3` with
  the first two arguments swapped so it can be used in a pipeline on a `RDF.Graph`.

  See `RDF.Query.stream/3` and `RDF.Query.stream!/3` for more information and examples.
  """
  def query_stream(graph, query, opts \\ []) do
    RDF.Query.stream!(query, graph, opts)
  end

  @doc """
  Returns a nested map of the native Elixir values of a `RDF.Graph`.

  When a `:context` option is given with a `RDF.PropertyMap`, predicates will
  be mapped to the terms defined in the `RDF.PropertyMap`, if present.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {~I<http://example.com/S1>, ~I<http://example.com/p>, ~L"Foo"},
      ...>   {~I<http://example.com/S2>, ~I<http://example.com/p>, RDF.XSD.integer(42)}
      ...> ])
      ...> |> RDF.Graph.values()
      %{
        "http://example.com/S1" => %{"http://example.com/p" => ["Foo"]},
        "http://example.com/S2" => %{"http://example.com/p" => [42]}
      }

      iex> RDF.Graph.new([
      ...>   {~I<http://example.com/S1>, ~I<http://example.com/p>, ~L"Foo"},
      ...>   {~I<http://example.com/S2>, ~I<http://example.com/p>, RDF.XSD.integer(42)}
      ...> ])
      ...> |> RDF.Graph.values(context: [p: ~I<http://example.com/p>])
      %{
        "http://example.com/S1" => %{p: ["Foo"]},
        "http://example.com/S2" => %{p: [42]}
      }

  """
  @spec values(t, keyword) :: map
  def values(%__MODULE__{} = graph, opts \\ []) do
    if property_map = PropertyMap.from_opts(opts) do
      map(graph, RDF.Statement.default_property_mapping(property_map))
    else
      map(graph, &RDF.Statement.default_term_mapping/1)
    end
  end

  @doc """
  Returns a nested map of a `RDF.Graph` where each element from its triples is mapped with the given function.

  The function `fun` will receive a tuple `{statement_position, rdf_term}` where
  `statement_position` is one of the atoms `:subject`, `:predicate` or `:object`,
  while `rdf_term` is the RDF term to be mapped. When the given function returns
  `nil` this will be interpreted as an error and will become the overhaul result
  of the `map/2` call.

  Note: RDF-star statements where the subject or object is a triple will be ignored.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {~I<http://example.com/S1>, ~I<http://example.com/p>, ~L"Foo"},
      ...>   {~I<http://example.com/S2>, ~I<http://example.com/p>, RDF.XSD.integer(42)}
      ...> ])
      ...> |> RDF.Graph.map(fn
      ...>      {:predicate, predicate} ->
      ...>        predicate
      ...>        |> to_string()
      ...>        |> String.split("/")
      ...>        |> List.last()
      ...>        |> String.to_atom()
      ...>      {_, term} ->
      ...>        RDF.Term.value(term)
      ...>    end)
      %{
        "http://example.com/S1" => %{p: ["Foo"]},
        "http://example.com/S2" => %{p: [42]}
      }

  """
  @spec map(t, Statement.term_mapping()) :: map
  def map(description, fun)

  def map(%__MODULE__{} = graph, fun) do
    Enum.reduce(graph.descriptions, %{}, fn
      {subject, _}, map when is_tuple(subject) ->
        map

      {subject, description}, map ->
        case Description.map(description, fun) do
          mapped_objects when map_size(mapped_objects) == 0 ->
            map

          mapped_objects ->
            Map.put(
              map,
              fun.({:subject, subject}),
              mapped_objects
            )
        end
    end)
  end

  @doc """
  Checks if two `RDF.Graph`s are equal.

  Two `RDF.Graph`s are considered to be equal if they contain the same triples
  and have the same name. The prefixes of the graph are irrelevant for equality.
  """
  @spec equal?(t | any, t | any) :: boolean
  def equal?(graph1, graph2)

  def equal?(%__MODULE__{} = graph1, %__MODULE__{} = graph2) do
    clear_metadata(graph1) == clear_metadata(graph2)
  end

  def equal?(_, _), do: false

  @doc """
  Returns the prefixes of the given `graph` as a `RDF.PrefixMap`.
  """
  @spec prefixes(t) :: PrefixMap.t() | nil
  def prefixes(%__MODULE__{} = graph), do: graph.prefixes

  @doc """
  Adds `prefixes` to the given `graph`.

  The `prefixes` mappings can be given as any structure convertible to a
  `RDF.PrefixMap`.

  When a prefix with another mapping already exists it will be overwritten with
  the new one. This behaviour can be customized by providing a `conflict_resolver`
  function. See `RDF.PrefixMap.merge/3` for more on that.
  """
  @spec add_prefixes(
          t,
          PrefixMap.t() | map | keyword | nil,
          PrefixMap.conflict_resolver() | nil
        ) :: t
  def add_prefixes(graph, prefixes, conflict_resolver \\ nil)

  def add_prefixes(%__MODULE__{} = graph, nil, _), do: graph

  def add_prefixes(%__MODULE__{prefixes: nil} = graph, prefixes, _) do
    %__MODULE__{graph | prefixes: PrefixMap.new(prefixes)}
  end

  def add_prefixes(%__MODULE__{} = graph, additions, nil) do
    add_prefixes(graph, additions, :overwrite)
  end

  def add_prefixes(%__MODULE__{prefixes: prefixes} = graph, additions, conflict_resolver) do
    %__MODULE__{graph | prefixes: PrefixMap.merge!(prefixes, additions, conflict_resolver)}
  end

  @doc """
  Deletes `prefixes` from the given `graph`.

  The `prefixes` can be a single prefix or a list of prefixes.
  Prefixes not in prefixes of the graph are simply ignored.
  """
  @spec delete_prefixes(t, PrefixMap.t()) :: t
  def delete_prefixes(graph, prefixes)

  def delete_prefixes(%__MODULE__{prefixes: nil} = graph, _), do: graph

  def delete_prefixes(%__MODULE__{} = graph, deletions) do
    %__MODULE__{graph | prefixes: PrefixMap.drop(graph.prefixes, List.wrap(deletions))}
  end

  @doc """
  Clears all prefixes of the given `graph`.
  """
  @spec clear_prefixes(t) :: t
  def clear_prefixes(%__MODULE__{} = graph) do
    %__MODULE__{graph | prefixes: nil}
  end

  @doc """
  Returns the base IRI of the given `graph`.
  """
  @spec base_iri(t) :: IRI.t() | nil
  def base_iri(%__MODULE__{} = graph), do: graph.base_iri

  @doc """
  Sets the base IRI of the given `graph`.

  The `base_iri` can be given as anything accepted by `RDF.IRI.coerce_base/1`.
  """
  @spec set_base_iri(t, IRI.t() | nil) :: t
  def set_base_iri(graph, base_iri)

  def set_base_iri(%__MODULE__{} = graph, nil) do
    %__MODULE__{graph | base_iri: nil}
  end

  def set_base_iri(%__MODULE__{} = graph, base_iri) do
    %__MODULE__{graph | base_iri: IRI.coerce_base(base_iri)}
  end

  @doc """
  Clears the base IRI of the given `graph`.
  """
  @spec clear_base_iri(t) :: t
  def clear_base_iri(%__MODULE__{} = graph) do
    %__MODULE__{graph | base_iri: nil}
  end

  @doc """
  Clears the base IRI and all prefixes of the given `graph`.
  """
  @spec clear_metadata(t) :: t
  def clear_metadata(%__MODULE__{} = graph) do
    graph
    |> clear_base_iri()
    |> clear_prefixes()
  end

  defimpl Enumerable do
    alias RDF.Graph

    def member?(graph, triple), do: {:ok, Graph.include?(graph, triple)}
    def count(graph), do: {:ok, Graph.statement_count(graph)}

    if Version.match?(System.version(), "~> 1.10") do
      def slice(graph) do
        size = Graph.statement_count(graph)
        {:ok, size, &Enumerable.List.slice(Graph.triples(graph), &1, &2, size)}
      end
    else
      def slice(_), do: {:error, __MODULE__}
    end

    def reduce(graph, acc, fun) do
      graph
      |> Graph.triples()
      |> Enumerable.List.reduce(acc, fun)
    end
  end

  defimpl Collectable do
    alias RDF.Graph

    def into(original) do
      collector_fun = fn
        graph, {:cont, list} when is_list(list) ->
          Graph.add(graph, List.to_tuple(list))

        graph, {:cont, elem} ->
          Graph.add(graph, elem)

        graph, :done ->
          graph

        _graph, :halt ->
          :ok
      end

      {original, collector_fun}
    end
  end
end
