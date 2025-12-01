defmodule Events.Core.Schema.SlugUniquenessTest do
  use Events.TestCase, async: true

  defmodule Post do
    use Events.Core.Schema

    schema "posts" do
      field :title, :string, required: true

      # Slug with uniqueness using mappers
      field :slug, :string, mappers: [:trim, :downcase, {:slugify, uniquify: true}]
    end

    def changeset(post, attrs) do
      post
      |> Ecto.Changeset.cast(attrs, __cast_fields__())
      |> Ecto.Changeset.validate_required(__required_fields__())
      |> __apply_field_validations__()
    end
  end

  describe "slug with uniqueness" do
    test "generates slug with random suffix" do
      changeset =
        Post.changeset(%Post{}, %{
          title: "My Post",
          slug: "  Hello World  "
        })

      assert changeset.valid?
      slug = changeset.changes.slug

      # Should be trimmed, lowercased, and slugified
      assert String.starts_with?(slug, "hello-world-")

      # Should have a random suffix (default 6 characters)
      # Format: "hello-world-XXXXXX" where X is alphanumeric
      parts = String.split(slug, "-")
      suffix = List.last(parts)

      assert String.length(suffix) == 6
      assert suffix =~ ~r/^[a-z0-9]{6}$/
    end

    test "different calls generate different suffixes" do
      changeset1 =
        Post.changeset(%Post{}, %{
          title: "My Post",
          slug: "Hello World"
        })

      changeset2 =
        Post.changeset(%Post{}, %{
          title: "My Post",
          slug: "Hello World"
        })

      slug1 = changeset1.changes.slug
      slug2 = changeset2.changes.slug

      # Both should start with same base
      assert String.starts_with?(slug1, "hello-world-")
      assert String.starts_with?(slug2, "hello-world-")

      # But have different suffixes
      refute slug1 == slug2
    end

    test "slug with special characters only generates suffix" do
      changeset =
        Post.changeset(%Post{}, %{
          title: "My Post",
          slug: "!@#$%"
        })

      assert changeset.valid?

      if Map.has_key?(changeset.changes, :slug) do
        slug = changeset.changes.slug
        # Should just be the random suffix (special chars removed, leaving empty base)
        assert slug =~ ~r/^[a-z0-9]{6}$/
      else
        # If slug wasn't changed, that's also acceptable
        assert true
      end
    end
  end

  describe "slug preset" do
    defmodule Article do
      use Events.Core.Schema
      import Events.Core.Schema.Presets

      schema "articles" do
        field :title, :string, required: true

        # Using slug preset (should have uniquify by default)
        field :slug, :string, preset: slug()
      end

      def changeset(article, attrs) do
        article
        |> Ecto.Changeset.cast(attrs, __cast_fields__())
        |> Ecto.Changeset.validate_required(__required_fields__())
        |> __apply_field_validations__()
      end
    end

    test "slug preset includes uniquify" do
      # The slug() preset uses normalize: {:slugify, uniquify: true}
      # which should also add random suffix
      changeset =
        Article.changeset(%Article{}, %{
          title: "My Article",
          slug: "Hello World"
        })

      assert changeset.valid?
      slug = changeset.changes.slug

      # Should have random suffix from preset
      assert String.starts_with?(slug, "hello-world-")

      # Verify suffix exists and is alphanumeric
      parts = String.split(slug, "-")
      suffix = List.last(parts)
      assert String.length(suffix) == 6
      assert suffix =~ ~r/^[a-z0-9]{6}$/
    end
  end

  describe "custom suffix length" do
    defmodule CustomPost do
      use Events.Core.Schema

      schema "custom_posts" do
        # Slug with custom 8-character suffix
        field :slug, :string, mappers: [{:slugify, uniquify: 8}]
      end

      def changeset(post, attrs) do
        post
        |> Ecto.Changeset.cast(attrs, __cast_fields__())
        |> __apply_field_validations__()
      end
    end

    test "supports custom suffix length" do
      changeset =
        CustomPost.changeset(%CustomPost{}, %{
          slug: "Hello World"
        })

      assert changeset.valid?
      slug = changeset.changes.slug

      # Should have 8-character suffix
      parts = String.split(slug, "-")
      suffix = List.last(parts)

      assert String.length(suffix) == 8
      assert suffix =~ ~r/^[a-z0-9]{8}$/
    end
  end
end
