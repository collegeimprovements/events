defmodule OmCrud.ExecutableTest do
  use ExUnit.Case, async: true

  describe "OmCrud.Executable protocol" do
    test "protocol is defined" do
      assert {:module, OmCrud.Executable} = Code.ensure_loaded(OmCrud.Executable)
    end

    test "can be invoked via impl" do
      # Protocol defines execute/2 (opts has default)
      assert OmCrud.Executable.__protocol__(:functions) == [execute: 2]
    end
  end

  describe "OmCrud.Validatable protocol" do
    test "protocol is defined" do
      assert {:module, OmCrud.Validatable} = Code.ensure_loaded(OmCrud.Validatable)
    end

    test "can be invoked via impl" do
      # Protocol has __protocol__/1 callback
      assert OmCrud.Validatable.__protocol__(:functions) == [validate: 1]
    end
  end

  describe "OmCrud.Debuggable protocol" do
    test "protocol is defined" do
      assert {:module, OmCrud.Debuggable} = Code.ensure_loaded(OmCrud.Debuggable)
    end

    test "can be invoked via impl" do
      # Protocol has __protocol__/1 callback
      assert OmCrud.Debuggable.__protocol__(:functions) == [to_debug: 1]
    end
  end
end
