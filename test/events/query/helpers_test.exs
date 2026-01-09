defmodule Events.Core.OmQuery.HelpersTest do
  use Events.TestCase, async: true

  import OmQuery.Helpers
  alias OmQuery, as: Query

  describe "Date helpers" do
    test "today/0 returns current date" do
      assert %Date{} = today()
      assert today() == Date.utc_today()
    end

    test "yesterday/0 returns yesterday" do
      assert yesterday() == Date.add(Date.utc_today(), -1)
    end

    test "tomorrow/0 returns tomorrow" do
      assert tomorrow() == Date.add(Date.utc_today(), 1)
    end

    test "last_n_days/1 returns N days ago" do
      assert last_n_days(7) == Date.add(Date.utc_today(), -7)
      assert last_n_days(30) == Date.add(Date.utc_today(), -30)
      assert last_n_days(0) == Date.utc_today()
    end

    test "last_week/0 returns 7 days ago" do
      assert last_week() == last_n_days(7)
    end

    test "last_month/0 returns 30 days ago" do
      assert last_month() == last_n_days(30)
    end

    test "last_quarter/0 returns 90 days ago" do
      assert last_quarter() == last_n_days(90)
    end

    test "last_year/0 returns 365 days ago" do
      assert last_year() == last_n_days(365)
    end
  end

  describe "DateTime helpers" do
    test "now/0 returns current DateTime in UTC" do
      assert %DateTime{} = now()
      # Should be very close to current time (within 1 second)
      diff = DateTime.diff(DateTime.utc_now(), now(), :second)
      assert abs(diff) <= 1
    end

    test "minutes_ago/1 returns DateTime N minutes ago" do
      result = minutes_ago(30)
      assert %DateTime{} = result
      diff = DateTime.diff(DateTime.utc_now(), result, :second)
      # ~30 minutes (with 1 sec tolerance)
      assert diff >= 1799 and diff <= 1801
    end

    test "hours_ago/1 returns DateTime N hours ago" do
      result = hours_ago(2)
      assert %DateTime{} = result
      diff = DateTime.diff(DateTime.utc_now(), result, :second)
      # ~2 hours
      assert diff >= 7199 and diff <= 7201
    end

    test "days_ago/1 returns DateTime N days ago" do
      result = days_ago(7)
      assert %DateTime{} = result
      diff = DateTime.diff(DateTime.utc_now(), result, :second)
      # ~7 days
      assert diff >= 604_799 and diff <= 604_801
    end

    test "weeks_ago/1 returns DateTime N weeks ago" do
      result = weeks_ago(2)
      assert %DateTime{} = result
      diff = DateTime.diff(DateTime.utc_now(), result, :second)
      # ~14 days
      assert diff >= 1_209_599 and diff <= 1_209_601
    end
  end

  describe "Time period helpers" do
    test "start_of_day/1 returns midnight" do
      date = ~D[2024-01-15]
      result = start_of_day(date)
      assert result == ~U[2024-01-15 00:00:00Z]
    end

    test "end_of_day/1 returns last microsecond" do
      date = ~D[2024-01-15]
      result = end_of_day(date)
      assert result == ~U[2024-01-15 23:59:59.999999Z]
    end

    test "start_of_week/0 returns Monday at midnight" do
      result = start_of_week()
      assert %DateTime{} = result
      # Result should be on a Monday (day_of_week == 1)
      date = DateTime.to_date(result)
      assert Date.day_of_week(date) == 1
      assert result.hour == 0 and result.minute == 0 and result.second == 0
    end

    test "start_of_month/0 returns first day at midnight" do
      result = start_of_month()
      assert %DateTime{} = result
      assert result.day == 1
      assert result.hour == 0 and result.minute == 0 and result.second == 0
    end

    test "start_of_year/0 returns Jan 1st at midnight" do
      result = start_of_year()
      assert %DateTime{} = result
      assert result.month == 1
      assert result.day == 1
      assert result.hour == 0 and result.minute == 0 and result.second == 0
    end
  end

  describe "dynamic_filters/3" do
    test "applies filters based on mapping" do
      mapping = %{
        status: {:eq, :status},
        min_age: {:gte, :age},
        search: {:ilike, :name}
      }

      params = %{status: "active", min_age: 18}

      token =
        OmQuery.new(User)
        |> dynamic_filters(params, mapping)

      assert length(token.operations) == 2

      assert [{:filter, {:status, :eq, "active", []}}, {:filter, {:age, :gte, 18, []}}] =
               token.operations
    end

    test "skips nil filter values" do
      mapping = %{
        status: {:eq, :status},
        min_age: {:gte, :age}
      }

      params = %{status: "active", min_age: nil}

      token =
        OmQuery.new(User)
        |> dynamic_filters(params, mapping)

      assert length(token.operations) == 1
      assert [{:filter, {:status, :eq, "active", []}}] = token.operations
    end

    test "handles empty params" do
      mapping = %{status: {:eq, :status}}
      params = %{}

      token =
        OmQuery.new(User)
        |> dynamic_filters(params, mapping)

      assert token.operations == []
    end
  end

  describe "ensure_limit/2" do
    test "adds limit if query has none" do
      token =
        OmQuery.new(User)
        |> ensure_limit(20)

      assert [{:limit, 20}] = token.operations
    end

    test "does not add limit if already present" do
      token =
        OmQuery.new(User)
        |> OmQuery.limit(50)
        |> ensure_limit(20)

      assert [{:limit, 50}] = token.operations
    end

    test "does not add limit if paginate is present" do
      token =
        OmQuery.new(User)
        |> OmQuery.paginate(:cursor, limit: 25)
        |> ensure_limit(20)

      # Should only have paginate operation, no additional limit
      assert length(token.operations) == 1
      assert [{:paginate, {:cursor, opts}}] = token.operations
      assert opts[:limit] == 25
    end
  end

  describe "sort_by/2" do
    test "handles nil sort string" do
      token =
        OmQuery.new(User)
        |> sort_by(nil)

      assert token.operations == []
    end

    test "parses single ascending field" do
      token =
        OmQuery.new(User)
        |> sort_by("name")

      assert [{:order, {:name, :asc, []}}] = token.operations
    end

    test "parses single descending field with minus" do
      token =
        OmQuery.new(User)
        |> sort_by("-created_at")

      assert [{:order, {:created_at, :desc, []}}] = token.operations
    end

    test "parses single ascending field with plus" do
      token =
        OmQuery.new(User)
        |> sort_by("+name")

      assert [{:order, {:name, :asc, []}}] = token.operations
    end

    test "parses multiple fields" do
      token =
        OmQuery.new(User)
        |> sort_by("name,-created_at,+id")

      assert length(token.operations) == 3

      assert [
               {:order, {:name, :asc, []}},
               {:order, {:created_at, :desc, []}},
               {:order, {:id, :asc, []}}
             ] = token.operations
    end

    test "handles whitespace" do
      token =
        OmQuery.new(User)
        |> sort_by(" name , -created_at , id ")

      assert length(token.operations) == 3
    end

    test "handles invalid atoms gracefully" do
      # Should not raise, just skip invalid fields
      token =
        OmQuery.new(User)
        |> sort_by("nonexistent_field_12345")

      # Should have no operations since the atom doesn't exist
      assert token.operations == []
    end
  end

  describe "safe_sort_by/2" do
    test "returns {:ok, token} for valid fields" do
      assert {:ok, token} = safe_sort_by(OmQuery.new(User), "name")
      assert [{:order, {:name, :asc, []}}] = token.operations
    end

    test "returns {:ok, token} with empty operations for invalid atoms" do
      # Note: sort_by handles invalid atoms by returning the token unchanged
      # safe_sort_by wraps this in {:ok, token}, but operations will be empty
      assert {:ok, token} = safe_sort_by(OmQuery.new(User), "nonexistent_field_999")
      assert token.operations == []
    end
  end

  describe "paginate_from_params/2" do
    test "applies cursor pagination with cursor param" do
      params = %{"limit" => "25", "cursor" => "abc123"}

      token =
        OmQuery.new(User)
        |> paginate_from_params(params)

      assert [{:paginate, {:cursor, opts}}] = token.operations
      assert opts[:limit] == 25
      assert opts[:after] == "abc123"
    end

    test "applies offset pagination with offset param" do
      params = %{"limit" => "50", "offset" => "100"}

      token =
        OmQuery.new(User)
        |> paginate_from_params(params)

      assert [{:paginate, {:offset, opts}}] = token.operations
      assert opts[:limit] == 50
      assert opts[:offset] == 100
    end

    test "uses cursor pagination by default" do
      params = %{"limit" => "30"}

      token =
        OmQuery.new(User)
        |> paginate_from_params(params)

      assert [{:paginate, {:cursor, opts}}] = token.operations
      assert opts[:limit] == 30
    end

    test "uses default limit if not provided" do
      params = %{}

      token =
        OmQuery.new(User)
        |> paginate_from_params(params)

      assert [{:paginate, {:cursor, opts}}] = token.operations
      # default
      assert opts[:limit] == 20
    end

    test "parses string integers" do
      params = %{"limit" => "42", "offset" => "84"}

      token =
        OmQuery.new(User)
        |> paginate_from_params(params)

      assert [{:paginate, {:offset, opts}}] = token.operations
      assert opts[:limit] == 42
      assert opts[:offset] == 84
    end

    test "handles invalid integers gracefully" do
      params = %{"limit" => "invalid", "offset" => "bad"}

      token =
        OmQuery.new(User)
        |> paginate_from_params(params)

      # When offset is present, uses offset pagination with fallback values
      assert [{:paginate, {:offset, opts}}] = token.operations
      # invalid "invalid" falls back to default 20
      assert opts[:limit] == 20
      # invalid "bad" falls back to 0
      assert opts[:offset] == 0
    end
  end

  describe "integration with DSL" do
    import OmQuery.DSL

    test "date helpers work in DSL" do
      token =
        query User do
          filter(:created_at, :gte, last_week())
          filter(:updated_at, :gte, hours_ago(24))
        end

      assert length(token.operations) == 2
      # Verify the values are Date and DateTime respectively
      [{:filter, {_, _, date_value, _}}, {:filter, {_, _, datetime_value, _}}] = token.operations
      assert %Date{} = date_value
      assert %DateTime{} = datetime_value
    end

    test "query helpers work in pipeline" do
      token =
        query User do
          filter(:status, :eq, "active")
        end
        |> sort_by("-created_at")
        |> ensure_limit(50)

      assert length(token.operations) == 3
    end
  end
end
