defmodule OmS3.DurationTest do
  use ExUnit.Case, async: true

  alias OmS3.Duration

  describe "to_seconds/1" do
    test "returns integer seconds unchanged" do
      assert Duration.to_seconds(60) == 60
      assert Duration.to_seconds(3600) == 3600
    end

    test "converts second tuples" do
      assert Duration.to_seconds({30, :second}) == 30
      assert Duration.to_seconds({30, :seconds}) == 30
    end

    test "converts minute tuples" do
      assert Duration.to_seconds({5, :minute}) == 300
      assert Duration.to_seconds({5, :minutes}) == 300
    end

    test "converts hour tuples" do
      assert Duration.to_seconds({1, :hour}) == 3600
      assert Duration.to_seconds({2, :hours}) == 7200
    end

    test "converts day tuples" do
      assert Duration.to_seconds({1, :day}) == 86_400
      assert Duration.to_seconds({7, :days}) == 604_800
    end

    test "converts week tuples" do
      assert Duration.to_seconds({1, :week}) == 604_800
      assert Duration.to_seconds({2, :weeks}) == 1_209_600
    end

    test "converts month tuples" do
      assert Duration.to_seconds({1, :month}) == 2_592_000
      assert Duration.to_seconds({3, :months}) == 7_776_000
    end

    test "converts year tuples" do
      assert Duration.to_seconds({1, :year}) == 31_536_000
      assert Duration.to_seconds({2, :years}) == 63_072_000
    end
  end

  describe "to_ms/1" do
    test "returns integer ms unchanged" do
      assert Duration.to_ms(1000) == 1000
      assert Duration.to_ms(60_000) == 60_000
    end

    test "converts duration tuples to milliseconds" do
      assert Duration.to_ms({5, :minutes}) == 300_000
      assert Duration.to_ms({1, :hour}) == 3_600_000
    end
  end

  describe "format/1" do
    test "formats zero seconds" do
      assert Duration.format(0) == "0 seconds"
    end

    test "formats singular units" do
      assert Duration.format(1) == "1 second"
      assert Duration.format(60) == "1 minute"
      assert Duration.format(3600) == "1 hour"
    end

    test "formats plural units" do
      assert Duration.format(5) == "5 seconds"
      assert Duration.format(120) == "2 minutes"
      assert Duration.format(7200) == "2 hours"
    end

    test "formats compound durations" do
      assert Duration.format(3661) == "1 hour, 1 minute, 1 second"
      assert Duration.format(7325) == "2 hours, 2 minutes, 5 seconds"
    end

    test "omits zero components" do
      assert Duration.format(3660) == "1 hour, 1 minute"
      assert Duration.format(3601) == "1 hour, 1 second"
    end
  end
end
