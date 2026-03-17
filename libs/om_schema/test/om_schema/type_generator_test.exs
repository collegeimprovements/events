defmodule OmSchema.TypeGeneratorTest do
  @moduledoc """
  Tests for OmSchema.TypeGenerator - Elixir typespec generation from Ecto types.

  Validates that Ecto types are correctly mapped to Elixir types and that
  typespec AST generation works correctly for various field configurations.
  """

  use ExUnit.Case, async: true

  alias OmSchema.TypeGenerator

  # ============================================
  # Ecto to Elixir Type Mapping
  # ============================================

  describe "ecto_to_elixir_type/2 for string types" do
    test "maps :string to String.t()" do
      assert {:remote, String, :t} = TypeGenerator.ecto_to_elixir_type(:string)
    end

    test "maps :citext to String.t()" do
      assert {:remote, String, :t} = TypeGenerator.ecto_to_elixir_type(:citext)
    end

    test "maps Ecto.UUID to String.t()" do
      assert {:remote, String, :t} = TypeGenerator.ecto_to_elixir_type(Ecto.UUID)
    end
  end

  describe "ecto_to_elixir_type/2 for numeric types" do
    test "maps :integer to integer()" do
      assert {:type, :integer} = TypeGenerator.ecto_to_elixir_type(:integer)
    end

    test "maps :float to float()" do
      assert {:type, :float} = TypeGenerator.ecto_to_elixir_type(:float)
    end

    test "maps :decimal to Decimal.t()" do
      assert {:remote, Decimal, :t} = TypeGenerator.ecto_to_elixir_type(:decimal)
    end

    test "maps :id to integer()" do
      assert {:type, :integer} = TypeGenerator.ecto_to_elixir_type(:id)
    end
  end

  describe "ecto_to_elixir_type/2 for boolean and binary types" do
    test "maps :boolean to boolean()" do
      assert {:type, :boolean} = TypeGenerator.ecto_to_elixir_type(:boolean)
    end

    test "maps :binary to binary()" do
      assert {:type, :binary} = TypeGenerator.ecto_to_elixir_type(:binary)
    end

    test "maps :binary_id to binary()" do
      assert {:type, :binary} = TypeGenerator.ecto_to_elixir_type(:binary_id)
    end
  end

  describe "ecto_to_elixir_type/2 for date/time types" do
    test "maps :date to Date.t()" do
      assert {:remote, Date, :t} = TypeGenerator.ecto_to_elixir_type(:date)
    end

    test "maps :time to Time.t()" do
      assert {:remote, Time, :t} = TypeGenerator.ecto_to_elixir_type(:time)
    end

    test "maps :time_usec to Time.t()" do
      assert {:remote, Time, :t} = TypeGenerator.ecto_to_elixir_type(:time_usec)
    end

    test "maps :naive_datetime to NaiveDateTime.t()" do
      assert {:remote, NaiveDateTime, :t} = TypeGenerator.ecto_to_elixir_type(:naive_datetime)
    end

    test "maps :naive_datetime_usec to NaiveDateTime.t()" do
      assert {:remote, NaiveDateTime, :t} = TypeGenerator.ecto_to_elixir_type(:naive_datetime_usec)
    end

    test "maps :utc_datetime to DateTime.t()" do
      assert {:remote, DateTime, :t} = TypeGenerator.ecto_to_elixir_type(:utc_datetime)
    end

    test "maps :utc_datetime_usec to DateTime.t()" do
      assert {:remote, DateTime, :t} = TypeGenerator.ecto_to_elixir_type(:utc_datetime_usec)
    end
  end

  describe "ecto_to_elixir_type/2 for map types" do
    test "maps :map to map()" do
      assert {:type, :map} = TypeGenerator.ecto_to_elixir_type(:map)
    end

    test "maps {:map, :string} to map_of atom => String.t()" do
      assert {:map_of, {:type, :atom}, {:remote, String, :t}} =
               TypeGenerator.ecto_to_elixir_type({:map, :string})
    end

    test "maps {:map, :integer} to map_of atom => integer()" do
      assert {:map_of, {:type, :atom}, {:type, :integer}} =
               TypeGenerator.ecto_to_elixir_type({:map, :integer})
    end
  end

  describe "ecto_to_elixir_type/2 for array types" do
    test "maps {:array, :string} to [String.t()]" do
      assert {:list, {:remote, String, :t}} =
               TypeGenerator.ecto_to_elixir_type({:array, :string})
    end

    test "maps {:array, :integer} to [integer()]" do
      assert {:list, {:type, :integer}} = TypeGenerator.ecto_to_elixir_type({:array, :integer})
    end

    test "maps nested arrays" do
      assert {:list, {:list, {:type, :integer}}} =
               TypeGenerator.ecto_to_elixir_type({:array, {:array, :integer}})
    end
  end

  describe "ecto_to_elixir_type/2 for Ecto.Enum" do
    test "without values returns atom()" do
      assert {:type, :atom} = TypeGenerator.ecto_to_elixir_type(Ecto.Enum)
    end

    test "with values returns union of literals" do
      assert {:union, [{:literal, :active}, {:literal, :inactive}]} =
               TypeGenerator.ecto_to_elixir_type(Ecto.Enum, values: [:active, :inactive])
    end
  end

  describe "ecto_to_elixir_type/2 for special types" do
    test "maps :any to any()" do
      assert {:type, :any} = TypeGenerator.ecto_to_elixir_type(:any)
    end

    test "handles parameterized types" do
      assert {:remote, String, :t} =
               TypeGenerator.ecto_to_elixir_type({:parameterized, :string, %{}})
    end

    test "unknown types fallback to any()" do
      assert {:type, :any} = TypeGenerator.ecto_to_elixir_type(:unknown_type)
    end
  end

  # ============================================
  # Type to AST Conversion
  # ============================================

  describe "type_to_ast/2" do
    test "converts simple type to AST" do
      ast = TypeGenerator.type_to_ast({:type, :integer})
      assert {:integer, [], []} = ast
    end

    test "converts remote type to AST" do
      ast = TypeGenerator.type_to_ast({:remote, String, :t})
      assert {{:., [], [{:__aliases__, [alias: false], [String]}, :t]}, [no_parens: true], []} = ast
    end

    test "handles nullable option" do
      ast = TypeGenerator.type_to_ast({:type, :integer}, nullable: true)
      assert {:|, [], [{:integer, [], []}, nil]} = ast
    end

    test "converts list type to AST" do
      ast = TypeGenerator.type_to_ast({:list, {:type, :integer}})
      assert [{:integer, [], []}] = ast
    end

    test "converts union type to AST" do
      ast = TypeGenerator.type_to_ast({:union, [{:literal, :a}, {:literal, :b}]})
      assert {:|, [], [:a, :b]} = ast
    end

    test "converts literal type to AST" do
      ast = TypeGenerator.type_to_ast({:literal, :active})
      assert :active = ast
    end
  end

  # ============================================
  # Full Type Generation
  # ============================================

  describe "generate_type_ast/2" do
    test "generates struct type AST for simple fields" do
      validations = [
        {:name, :string, [required: true]},
        {:age, :integer, [required: false]}
      ]

      ast = TypeGenerator.generate_type_ast(validations)

      # Should be a struct
      assert {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], fields}]} = ast

      # Should have id, name, and age fields
      field_names = Keyword.keys(fields)
      assert :id in field_names
      assert :name in field_names
      assert :age in field_names
    end

    test "handles required fields as non-nullable" do
      validations = [{:email, :string, [required: true]}]

      ast = TypeGenerator.generate_type_ast(validations)
      {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], fields}]} = ast

      # email should NOT be nullable
      email_type = Keyword.get(fields, :email)

      # Not a union with nil
      refute match?({:|, [], [_, nil]}, email_type)
    end

    test "handles optional fields as nullable" do
      validations = [{:nickname, :string, [required: false]}]

      ast = TypeGenerator.generate_type_ast(validations)
      {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], fields}]} = ast

      # nickname should be nullable
      nickname_type = Keyword.get(fields, :nickname)
      assert {:|, [], [_, nil]} = nickname_type
    end

    test "excludes id when include_id: false" do
      validations = [{:name, :string, [required: true]}]

      ast = TypeGenerator.generate_type_ast(validations, include_id: false)
      {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], fields}]} = ast

      field_names = Keyword.keys(fields)
      refute :id in field_names
    end

    test "handles Ecto.Enum with values" do
      validations = [{:status, Ecto.Enum, [required: true, values: [:active, :inactive]]}]

      ast = TypeGenerator.generate_type_ast(validations, include_id: false)
      {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], fields}]} = ast

      status_type = Keyword.get(fields, :status)
      # Should be a union of :active | :inactive
      assert {:|, [], [:active, :inactive]} = status_type
    end
  end

  # ============================================
  # String Generation
  # ============================================

  describe "to_typespec_string/2" do
    test "generates readable typespec string" do
      validations = [
        {:name, :string, [required: true]},
        {:count, :integer, [required: false]}
      ]

      result = TypeGenerator.to_typespec_string(validations, include_id: false)

      assert result =~ "@type t()"
      assert result =~ "name:"
      assert result =~ "count:"
    end
  end

  # ============================================
  # Type Definition Generation
  # ============================================

  describe "generate_type_definition/2" do
    test "generates valid quoted code" do
      validations = [{:name, :string, [required: true]}]

      quoted = TypeGenerator.generate_type_definition(validations, include_id: false)

      # Should be a valid quote block with @type
      assert {:@, _, [{:type, _, _}]} = quoted
    end
  end
end
