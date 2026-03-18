defmodule OmQuery.SearchTest do
  @moduledoc """
  Tests for OmQuery.Search - Full-text search with ranking support.

  Search operates entirely on tokens (no DB needed), making these
  pure unit tests that verify the token operations produced by search.

  Note: The filter_group validation requires at least 2 filters in an OR group,
  so search must be called with at least 2 fields to produce a valid token.
  Single-field search triggers a FilterGroupError.

  ## Covered Functionality

  - Nil/empty term passthrough
  - All search modes: ilike, like, starts_with, ends_with, contains, exact, similarity
  - Field spec formats: atom, {field, mode}, {field, mode, opts}
  - Ranking with search_rank operations
  - Unknown mode error handling
  - Single field edge case (FilterGroupError)
  """

  use ExUnit.Case, async: true

  alias OmQuery.Token

  # Test schema for search operations
  defmodule Product do
    use Ecto.Schema

    schema "products" do
      field :name, :string
      field :description, :string
      field :sku, :string
    end
  end

  # ============================================
  # Nil / Empty Term Handling
  # ============================================

  describe "search/4 - nil/empty term handling" do
    test "nil term returns token unchanged" do
      token = Token.new(Product)

      result = OmQuery.search(token, nil, [:name, :description])

      assert result.operations == []
      assert result == token
    end

    test "empty string returns token unchanged" do
      token = Token.new(Product)

      result = OmQuery.search(token, "", [:name, :description])

      assert result.operations == []
      assert result == token
    end
  end

  # ============================================
  # Default Mode (:ilike)
  # ============================================

  describe "search/4 - default mode (:ilike)" do
    test "two fields adds filter_group with OR and ilike patterns" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description])

      assert [{:filter_group, {:or, filters}}] = result.operations
      assert length(filters) == 2

      [{field1, op1, pattern1, _opts1}, {field2, op2, pattern2, _opts2}] = filters
      assert field1 == :name
      assert op1 == :ilike
      assert pattern1 == "%phone%"
      assert field2 == :description
      assert op2 == :ilike
      assert pattern2 == "%phone%"
    end

    test "multiple fields creates OR group across all fields" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description, :sku])

      assert [{:filter_group, {:or, filters}}] = result.operations
      assert length(filters) == 3

      fields = Enum.map(filters, fn {field, _op, _pattern, _opts} -> field end)
      assert :name in fields
      assert :description in fields
      assert :sku in fields
    end

    test "pattern wraps term in %term%" do
      token = Token.new(Product)

      result = OmQuery.search(token, "test", [:name, :description])

      [{:filter_group, {:or, [{_field, _op, pattern, _opts} | _]}}] = result.operations
      assert pattern == "%test%"
    end

    test "single field raises FilterGroupError (OR group requires 2+ filters)" do
      token = Token.new(Product)

      assert_raise OmQuery.FilterGroupError, fn ->
        OmQuery.search(token, "phone", [:name])
      end
    end
  end

  # ============================================
  # Search Modes
  # ============================================

  describe "search/4 - modes" do
    test ":ilike mode wraps in %term%" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :ilike)

      [{:filter_group, {:or, [{_field, op, pattern, _opts} | _]}}] = result.operations
      assert op == :ilike
      assert pattern == "%phone%"
    end

    test ":like mode wraps in %term%" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :like)

      [{:filter_group, {:or, [{_field, op, pattern, _opts} | _]}}] = result.operations
      assert op == :like
      assert pattern == "%phone%"
    end

    test ":starts_with uses term%" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :starts_with)

      [{:filter_group, {:or, [{_field, op, pattern, _opts} | _]}}] = result.operations
      # starts_with defaults to case-insensitive (ilike)
      assert op == :ilike
      assert pattern == "phone%"
    end

    test ":ends_with uses %term" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :ends_with)

      [{:filter_group, {:or, [{_field, op, pattern, _opts} | _]}}] = result.operations
      assert op == :ilike
      assert pattern == "%phone"
    end

    test ":contains uses %term%" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :contains)

      [{:filter_group, {:or, [{_field, op, pattern, _opts} | _]}}] = result.operations
      assert op == :ilike
      assert pattern == "%phone%"
    end

    test ":exact uses :eq operator without pattern wrapping" do
      token = Token.new(Product)

      result = OmQuery.search(token, "iPhone 15", [:name, :description], mode: :exact)

      [{:filter_group, {:or, filters}}] = result.operations

      Enum.each(filters, fn {_field, op, value, _opts} ->
        assert op == :eq
        assert value == "iPhone 15"
      end)
    end

    test ":similarity mode uses similarity operator with threshold" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :similarity)

      [{:filter_group, {:or, filters}}] = result.operations

      Enum.each(filters, fn {_field, op, term, opts} ->
        assert op == :similarity
        assert term == "phone"
        assert Keyword.get(opts, :threshold) == 0.3
      end)
    end

    test "unknown mode raises SearchModeError" do
      token = Token.new(Product)

      assert_raise OmQuery.SearchModeError, fn ->
        OmQuery.search(token, "phone", [:name, :description], mode: :fuzzy_wuzzy)
      end
    end
  end

  # ============================================
  # Field Specs
  # ============================================

  describe "search/4 - field specs" do
    test "simple atom fields" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description])

      [{:filter_group, {:or, filters}}] = result.operations
      fields = Enum.map(filters, fn {field, _op, _pattern, _opts} -> field end)
      assert fields == [:name, :description]
    end

    test "tuple with mode: {:name, :similarity}" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [{:name, :similarity}, {:description, :similarity}])

      [{:filter_group, {:or, filters}}] = result.operations

      [{field1, op1, _term1, _opts1}, {field2, op2, _term2, _opts2}] = filters
      assert field1 == :name
      assert op1 == :similarity
      assert field2 == :description
      assert op2 == :similarity
    end

    test "tuple with opts: {:name, :ilike, threshold: 0.5}" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [
        {:name, :ilike, threshold: 0.5},
        {:description, :ilike, threshold: 0.5}
      ])

      [{:filter_group, {:or, [{field, op, _pattern, _opts} | _]}}] = result.operations
      assert field == :name
      assert op == :ilike
    end

    test "mixed field specs in single search" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [
        :sku,
        {:name, :similarity},
        {:description, :ilike, threshold: 0.5}
      ])

      [{:filter_group, {:or, filters}}] = result.operations
      assert length(filters) == 3

      [sku_filter, name_filter, desc_filter] = filters

      {sku_field, sku_op, _sku_pattern, _} = sku_filter
      assert sku_field == :sku
      assert sku_op == :ilike

      {name_field, name_op, _name_term, _} = name_filter
      assert name_field == :name
      assert name_op == :similarity

      {desc_field, desc_op, _desc_pattern, _} = desc_filter
      assert desc_field == :description
      assert desc_op == :ilike
    end

    test "per-field mode overrides global mode" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [
        :name,
        {:sku, :exact}
      ], mode: :ilike)

      [{:filter_group, {:or, filters}}] = result.operations

      [{name_field, name_op, name_val, _}, {sku_field, sku_op, sku_val, _}] = filters

      # :name uses the global mode (ilike)
      assert name_field == :name
      assert name_op == :ilike
      assert name_val == "%phone%"

      # :sku uses its own mode (exact)
      assert sku_field == :sku
      assert sku_op == :eq
      assert sku_val == "phone"
    end
  end

  # ============================================
  # Ranking
  # ============================================

  describe "search/4 - ranking" do
    test "rank: true adds search_rank operation" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], rank: true)

      operations = result.operations
      assert length(operations) == 2

      # First operation is the filter_group
      assert {:filter_group, {:or, _filters}} = Enum.at(operations, 0)

      # Second operation is the search_rank
      assert {:search_rank, {fields, term}} = Enum.at(operations, 1)
      assert term == "phone"
      assert is_list(fields)
      assert length(fields) == 2
    end

    test "rank: false (default) does not add ranking" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description])

      operations = result.operations
      assert length(operations) == 1
      assert {:filter_group, _} = Enum.at(operations, 0)

      # No search_rank operation
      rank_ops = Enum.filter(operations, fn
        {:search_rank, _} -> true
        {:search_rank_limited, _} -> true
        _ -> false
      end)

      assert rank_ops == []
    end

    test "rank: true with take limits adds search_rank_limited" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [
        {:name, :ilike, take: 5, rank: 1},
        {:description, :ilike, take: 10, rank: 2}
      ], rank: true)

      operations = result.operations
      assert length(operations) == 2

      assert {:filter_group, _} = Enum.at(operations, 0)
      assert {:search_rank_limited, {_fields, "phone"}} = Enum.at(operations, 1)
    end

    test "ranked fields are sorted by rank value" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [
        {:description, :ilike, rank: 3},
        {:name, :ilike, rank: 1}
      ], rank: true)

      {:search_rank, {sorted_fields, _term}} = Enum.at(result.operations, 1)

      ranks = Enum.map(sorted_fields, fn {_field, _mode, _opts, rank, _take} -> rank end)
      assert ranks == Enum.sort(ranks)
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "search/4 - edge cases" do
    test "search preserves existing token operations" do
      token =
        Token.new(Product)
        |> Token.add_operation!({:filter, {:sku, :not_nil, true, []}})
        |> Token.add_operation!({:order, {:name, :asc, []}})

      result = OmQuery.search(token, "phone", [:name, :description])

      assert length(result.operations) == 3
      assert {:filter, _} = Enum.at(result.operations, 0)
      assert {:order, _} = Enum.at(result.operations, 1)
      assert {:filter_group, _} = Enum.at(result.operations, 2)
    end

    test "search with special characters in term" do
      token = Token.new(Product)

      result = OmQuery.search(token, "100% off!", [:name, :description])

      [{:filter_group, {:or, [{_field, _op, pattern, _opts} | _]}}] = result.operations
      assert pattern == "%100% off!%"
    end

    test "similarity mode includes custom threshold from opts" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :similarity, threshold: 0.7)

      [{:filter_group, {:or, [{_field, :similarity, _term, opts} | _]}}] = result.operations
      assert Keyword.get(opts, :threshold) == 0.7
    end

    test "word_similarity mode is supported" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :word_similarity)

      [{:filter_group, {:or, [{_field, op, _term, _opts} | _]}}] = result.operations
      assert op == :word_similarity
    end

    test "strict_word_similarity mode is supported" do
      token = Token.new(Product)

      result = OmQuery.search(token, "phone", [:name, :description], mode: :strict_word_similarity)

      [{:filter_group, {:or, [{_field, op, _term, _opts} | _]}}] = result.operations
      assert op == :strict_word_similarity
    end

    test "all filters in group use same search term" do
      token = Token.new(Product)

      result = OmQuery.search(token, "laptop", [:name, :description, :sku])

      [{:filter_group, {:or, filters}}] = result.operations

      Enum.each(filters, fn {_field, _op, pattern, _opts} ->
        assert pattern == "%laptop%"
      end)
    end
  end
end
