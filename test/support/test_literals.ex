defmodule RDF.TestLiterals do

  alias RDF.{Literal}
  alias RDF.NS.XSD

  def value(:empty),      do: [""]
  def value(:plain),      do: ["Hello"]
  def value(:empty_lang), do: ["", [language: "en"]]
  def value(:plain_lang), do: ["Hello", [language: "en"]]
  def value(:string),     do: ["String", [datatype: XSD.string]]
  def value(:true),       do: [true]
  def value(:false),      do: [false]
  def value(:int),        do: [123]
  def value(:long),       do: [9223372036854775807]
  def value(:double),     do: [3.1415]
  def value(:date),       do: [~D[2017-04-13]]
  def value(:datetime),   do: [~N[2017-04-14 15:32:07]]
  def value(:time),       do: [~T[01:02:03]]
  def value(selector) do
    raise "unexpected literal: :#{selector}"
  end

  def values(:all_simple),
    do: Enum.map(~W(empty plain string)a, &value/1)
  def values(:all_plain_lang),
    do: Enum.map(~W[empty_lang plain_lang]a, &value/1)
  def values(:all_native),
    do: Enum.map(~W[false true int long double time date datetime]a, &value/1)
  def values(:all_plain),
    do: values(~W[all_simple all_plain_lang]a)
  def values(:all),
    do: values(~W[all_native all_plain]a)
  def values(selectors) when is_list(selectors) do
    Enum.reduce selectors, [], fn(selector, values) ->
      values ++ values(selector)
    end
  end

  def literal(selector),
    do: apply(Literal, :new, value(selector))

  def literals(selectors),
    do: Enum.map values(selectors), fn value -> apply(Literal, :new, value) end

end
