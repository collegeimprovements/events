defmodule OmCrud.ExecutableTest do
  use ExUnit.Case, async: true

  describe "OmCrud.Executable protocol" do
    test "protocol is defined" do
      assert Code.ensure_loaded?(OmCrud.Executable)
    end

    test "has execute/2 callback" do
      # Protocol functions are defined
      assert function_exported?(OmCrud.Executable, :execute, 1)
      assert function_exported?(OmCrud.Executable, :execute, 2)
    end
  end

  describe "OmCrud.Validatable protocol" do
    test "protocol is defined" do
      assert Code.ensure_loaded?(OmCrud.Validatable)
    end

    test "has validate/1 callback" do
      assert function_exported?(OmCrud.Validatable, :validate, 1)
    end
  end

  describe "OmCrud.Debuggable protocol" do
    test "protocol is defined" do
      assert Code.ensure_loaded?(OmCrud.Debuggable)
    end

    test "has to_debug/1 callback" do
      assert function_exported?(OmCrud.Debuggable, :to_debug, 1)
    end
  end
end
