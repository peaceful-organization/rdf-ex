defmodule RDF.Turtle.Decoder do
  @moduledoc """
  A decoder for Turtle serializations to `RDF.Graph`s.

  As for all decoders of `RDF.Serialization.Format`s, you normally won't use these
  functions directly, but via one of the `read_` functions on the `RDF.Turtle` format
  module or the generic `RDF.Serialization` module.


  ## Options

  - `:base`: allows to specify the base URI to be used against relative URIs
    when no base URI is defined with a `@base` directive within the document

  """

  use RDF.Serialization.Decoder

  import RDF.Serialization.ParseHelper, only: [error_description: 1]

  alias RDF.{Graph, IRI}

  defmodule State do
    defstruct base_iri: nil, namespaces: %{}, bnode_counter: 0

    def add_namespace(%State{namespaces: namespaces} = state, ns, iri) do
      %State{state | namespaces: Map.put(namespaces, ns, iri)}
    end

    def ns(%State{namespaces: namespaces}, prefix) do
      namespaces[prefix]
    end

    def next_bnode(%State{bnode_counter: bnode_counter} = state) do
      {RDF.bnode("b#{bnode_counter}"), %State{state | bnode_counter: bnode_counter + 1}}
    end
  end

  @impl RDF.Serialization.Decoder
  @spec decode(String.t(), keyword) :: {:ok, Graph.t()} | {:error, any}
  def decode(content, opts \\ []) do
    base_iri =
      Keyword.get_lazy(
        opts,
        :base_iri,
        fn -> Keyword.get_lazy(opts, :base, fn -> RDF.default_base_iri() end) end
      )

    with {:ok, tokens, _} <- tokenize(content),
         {:ok, ast} <- parse(tokens) do
      build_graph(ast, base_iri && RDF.iri(base_iri))
    else
      {:error, {error_line, :turtle_lexer, error_descriptor}, _error_line_again} ->
        {:error,
         "Turtle scanner error on line #{error_line}: #{error_description(error_descriptor)}"}

      {:error, {error_line, :turtle_parser, error_descriptor}} ->
        {:error,
         "Turtle parser error on line #{error_line}: #{error_description(error_descriptor)}"}
    end
  end

  def tokenize(content), do: content |> to_charlist |> :turtle_lexer.string()

  def parse([]), do: {:ok, []}
  def parse(tokens), do: tokens |> :turtle_parser.parse()

  defp build_graph(ast, base_iri) do
    {graph, %State{namespaces: namespaces, base_iri: base_iri}} =
      Enum.reduce(ast, {RDF.Graph.new(), %State{base_iri: base_iri}}, fn
        {:triples, triples_ast}, {graph, state} ->
          {statements, state} = triples(triples_ast, state)
          {RDF.Graph.add(graph, statements), state}

        {:directive, directive_ast}, {graph, state} ->
          {graph, directive(directive_ast, state)}
      end)

    {:ok,
     if Enum.empty?(namespaces) do
       graph
     else
       RDF.Graph.add_prefixes(graph, namespaces)
     end
     |> RDF.Graph.set_base_iri(base_iri)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp directive({:prefix, {:prefix_ns, _, ns}, iri}, state) do
    absolute_iri =
      if IRI.absolute?(iri) do
        iri
      else
        iri |> IRI.absolute(state.base_iri) |> to_string()
      end

    State.add_namespace(state, ns, absolute_iri)
  end

  defp directive({:base, iri}, %State{base_iri: base_iri} = state) do
    cond do
      IRI.absolute?(iri) -> %State{state | base_iri: RDF.iri(iri)}
      not is_nil(base_iri) -> %State{state | base_iri: IRI.absolute(iri, base_iri)}
      true -> raise "Could not resolve relative IRI '#{iri}', no base iri provided"
    end
  end

  defp triples({:blankNodePropertyList, _} = ast, state) do
    {_, statements, state} = resolve_node(ast, [], state)
    {statements, state}
  end

  defp triples({subject, predications}, state) do
    {subject, statements, state} = resolve_node(subject, [], state)

    predications(subject, predications, statements, state)
  end

  defp predications(subject, predications, statements, state) do
    Enum.reduce(predications, {statements, state}, fn
      {predicate, objects}, {statements, state} ->
        {predicate, statements, state} = resolve_node(predicate, statements, state)

        Enum.reduce(objects, {statements, state}, fn
          {:annotation, annotation}, {[last_statement | _] = statements, state} ->
            predications(last_statement, annotation, statements, state)

          object, {statements, state} ->
            {object, statements, state} = resolve_node(object, statements, state)
            {[{subject, predicate, object} | statements], state}
        end)
    end)
  end

  defp resolve_node({:prefix_ln, line_number, {prefix, name}}, statements, state) do
    if ns = State.ns(state, prefix) do
      {RDF.iri(ns <> local_name_unescape(name)), statements, state}
    else
      raise "line #{line_number}: undefined prefix #{inspect(prefix)}"
    end
  end

  defp resolve_node({:prefix_ns, line_number, prefix}, statements, state) do
    if ns = State.ns(state, prefix) do
      {RDF.iri(ns), statements, state}
    else
      raise "line #{line_number}: undefined prefix #{inspect(prefix)}"
    end
  end

  defp resolve_node({:relative_iri, relative_iri}, _, %State{base_iri: nil}) do
    raise "Could not resolve relative IRI '#{relative_iri}', no base iri provided"
  end

  defp resolve_node({:relative_iri, relative_iri}, statements, state) do
    {IRI.absolute(relative_iri, state.base_iri), statements, state}
  end

  defp resolve_node({:anon}, statements, state) do
    {node, state} = State.next_bnode(state)
    {node, statements, state}
  end

  defp resolve_node({:blankNodePropertyList, property_list}, statements, state) do
    {subject, state} = State.next_bnode(state)
    {new_statements, state} = triples({subject, property_list}, state)
    {subject, statements ++ new_statements, state}
  end

  defp resolve_node(
         {{:string_literal_quote, _line, value}, {:datatype, datatype}},
         statements,
         state
       ) do
    {datatype, statements, state} = resolve_node(datatype, statements, state)
    {RDF.literal(value, datatype: datatype), statements, state}
  end

  defp resolve_node({:collection, []}, statements, state) do
    {RDF.nil(), statements, state}
  end

  defp resolve_node({:collection, elements}, statements, state) do
    {first_list_node, state} = State.next_bnode(state)
    [first_element | rest_elements] = elements
    {first_element_node, statements, state} = resolve_node(first_element, statements, state)
    first_statement = [{first_list_node, RDF.first(), first_element_node}]

    {last_list_node, statements, state} =
      Enum.reduce(
        rest_elements,
        {first_list_node, statements ++ first_statement, state},
        fn element, {list_node, statements, state} ->
          {element_node, statements, state} = resolve_node(element, statements, state)
          {next_list_node, state} = State.next_bnode(state)

          {next_list_node,
           statements ++
             [
               {list_node, RDF.rest(), next_list_node},
               {next_list_node, RDF.first(), element_node}
             ], state}
        end
      )

    {first_list_node, statements ++ [{last_list_node, RDF.rest(), RDF.nil()}], state}
  end

  defp resolve_node({:quoted_triple, s_node, p_node, o_node}, statements, state) do
    {subject, statements, state} = resolve_node(s_node, statements, state)
    {predicate, statements, state} = resolve_node(p_node, statements, state)
    {object, statements, state} = resolve_node(o_node, statements, state)
    {{subject, predicate, object}, statements, state}
  end

  defp resolve_node(node, statements, state), do: {node, statements, state}

  defp local_name_unescape(string),
    do: Macro.unescape_string(string, &local_name_unescape_map(&1))

  @reserved_characters ~c[~.-!$&'()*+,;=/?#@%_]

  defp local_name_unescape_map(e) when e in @reserved_characters, do: e
  defp local_name_unescape_map(_), do: false
end
