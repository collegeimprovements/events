defmodule OmCrud.OptionsTest do
  use ExUnit.Case, async: true

  alias OmCrud.Options

  describe "valid_opts/1" do
    test "returns valid options for :insert operation" do
      opts = Options.valid_opts(:insert)

      assert is_list(opts)
      assert :changeset in opts
      assert :returning in opts
      assert :repo in opts
    end

    test "returns valid options for :update operation" do
      opts = Options.valid_opts(:update)

      assert is_list(opts)
      assert :changeset in opts
      assert :force in opts
    end

    test "returns valid options for :delete operation" do
      opts = Options.valid_opts(:delete)

      assert is_list(opts)
      assert :stale_error_field in opts
    end

    test "returns valid options for :query operation" do
      opts = Options.valid_opts(:query)

      assert is_list(opts)
      assert :preload in opts
    end
  end

  describe "normalize/1" do
    test "returns keyword list unchanged" do
      opts = [repo: TestRepo, timeout: 5000]

      assert Options.normalize(opts) == opts
    end

    test "handles empty list" do
      assert Options.normalize([]) == []
    end
  end

  describe "repo_opts/1" do
    test "extracts repo-specific options" do
      opts = [repo: TestRepo, timeout: 5000, prefix: "tenant_1", log: :debug]

      repo_opts = Options.repo_opts(opts)

      assert is_list(repo_opts)
    end
  end

  describe "insert_opts/1" do
    test "returns keyword list for insert operations" do
      opts = Options.insert_opts(returning: true, timeout: 5000)

      assert is_list(opts)
    end

    test "works with empty options" do
      opts = Options.insert_opts([])

      assert is_list(opts)
    end
  end

  describe "update_opts/1" do
    test "returns keyword list for update operations" do
      opts = Options.update_opts(force: [:name], timeout: 5000)

      assert is_list(opts)
    end
  end

  describe "delete_opts/1" do
    test "returns keyword list for delete operations" do
      opts = Options.delete_opts(stale_error_field: :lock_version)

      assert is_list(opts)
    end
  end

  describe "query_opts/1" do
    test "returns keyword list for query operations" do
      opts = Options.query_opts(preload: [:account])

      assert is_list(opts)
    end
  end

  describe "insert_all_opts/1" do
    test "returns keyword list for insert_all operations" do
      opts = Options.insert_all_opts(returning: true, on_conflict: :nothing)

      assert is_list(opts)
    end
  end

  describe "update_all_opts/1" do
    test "returns keyword list for update_all operations" do
      opts = Options.update_all_opts(returning: [:id, :name])

      assert is_list(opts)
    end
  end

  describe "delete_all_opts/1" do
    test "returns keyword list for delete_all operations" do
      opts = Options.delete_all_opts(returning: true)

      assert is_list(opts)
    end
  end

  describe "preloads/1" do
    test "extracts preload configuration" do
      opts = [preload: [:account, :user]]

      assert Options.preloads(opts) == [:account, :user]
    end

    test "returns empty list when no preload" do
      opts = [timeout: 5000]

      assert Options.preloads(opts) == []
    end
  end

  describe "timeout/1" do
    test "extracts timeout configuration" do
      opts = [timeout: 30_000]

      assert Options.timeout(opts) == 30_000
    end

    test "returns default timeout when not specified" do
      opts = []

      # Default is 15_000
      assert Options.timeout(opts) == 15_000
    end
  end

  describe "prefix/1" do
    test "extracts prefix configuration" do
      opts = [prefix: "tenant_123"]

      assert Options.prefix(opts) == "tenant_123"
    end

    test "returns nil when no prefix" do
      opts = []

      assert Options.prefix(opts) == nil
    end
  end
end
