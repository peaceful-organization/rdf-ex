defmodule RDF.Literal.Datatype.RegistryTest do
  use RDF.Test.Case

  alias RDF.TestDatatypes.Age
  alias RDF.Literal.Datatype
  alias RDF.NS

  @unsupported_xsd_datatypes ~w[
      ENTITIES
      IDREF
      language
      Name
      normalizedString
      dayTimeDuration
      QName
      gYear
      NMTOKENS
      gDay
      NOTATION
      ID
      duration
      hexBinary
      ENTITY
      yearMonthDuration
      IDREFS
      base64Binary
      token
      NCName
      NMTOKEN
      gYearMonth
      gMonth
      gMonthDay
    ]
    |> Enum.map(fn xsd_datatype_name -> RDF.iri(NS.XSD.__base_iri__ <> xsd_datatype_name) end)

  @supported_xsd_datatypes RDF.NS.XSD.__iris__() -- @unsupported_xsd_datatypes


  describe "get/1" do
    test "core datatypes" do
      Enum.each(Datatype.Registry.core_datatypes(), fn datatype ->
        assert datatype == Datatype.Registry.get(datatype.id)
        assert datatype == Datatype.Registry.get(to_string(datatype.id))
      end)
    end

    test "supported datatypes from the XSD namespace" do
      Enum.each(@supported_xsd_datatypes, fn xsd_datatype_iri ->
        assert xsd_datatype = Datatype.Registry.get(xsd_datatype_iri)
        assert xsd_datatype.id == xsd_datatype_iri
      end)
    end

    test "unsupported datatypes from the XSD namespace" do
      Enum.each(@unsupported_xsd_datatypes, fn xsd_datatype_iri ->
        refute Datatype.Registry.get(xsd_datatype_iri)
        refute Datatype.Registry.get(to_string(xsd_datatype_iri))
      end)
    end

    test "with IRI of custom datatype" do
      assert Age == Datatype.Registry.get(Age.id)
    end

    test "with namespace terms" do
      assert Age == Datatype.Registry.get(EX.Age)
    end
  end
end
