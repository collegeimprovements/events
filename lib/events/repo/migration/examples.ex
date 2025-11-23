defmodule Events.Repo.Migration.Examples do
  @moduledoc """
  Comprehensive examples of using the improved migration DSL.

  This module demonstrates various patterns and best practices for
  creating migrations using the modular architecture.
  """

  @doc """
  Example: Basic user table with authentication fields.
  """
  def user_table_example do
    """
    defmodule MyApp.Repo.Migrations.CreateUsers do
      use Events.Repo.Migration

      def change do
        # Enable required extensions
        enable_citext()

        # Create table with UUIDv7 primary key
        create_table :users do
          # Identity fields
          name_fields(type: :citext, required: true)
          email_field(type: :citext, unique: true)
          phone_field()

          # Authentication
          add :password_hash, :string, null: false
          add :confirmed_at, :utc_datetime
          add :locked_at, :utc_datetime

          # Profile
          url_field(name: :website)
          add :bio, :text
          add :avatar_url, :string

          # Settings
          settings_field(name: :preferences)
          tags_field(name: :interests)

          # Status tracking
          status_field(values: ["pending", "active", "suspended", "deleted"])
          deleted_fields(with_reason: true)

          # Timestamps
          timestamps()
        end

        # Create indexes
        name_indexes(:users, fulltext: true)
        status_indexes(:users, partial: "deleted_at IS NULL")
        deleted_indexes(:users, active_index: true)
      end
    end
    """
  end

  @doc """
  Example: Product catalog with inventory tracking.
  """
  def product_table_example do
    """
    defmodule MyApp.Repo.Migrations.CreateProducts do
      use Events.Repo.Migration

      def change do
        create_table :products do
          # Basic info
          add :sku, :string, null: false
          title_fields(with_translations: true, languages: [:es, :fr])
          add :description, :text
          slug_field()

          # Categorization
          type_fields(primary: :category, secondary: :subcategory)
          tags_field(name: :tags)

          # Pricing
          money_field(:cost)
          money_field(:price)
          percentage_field(:discount)
          money_field(:sale_price)

          # Inventory
          counter_field(:stock_quantity)
          counter_field(:reserved_quantity)
          add :low_stock_threshold, :integer, default: 10

          # Media
          file_fields(:main_image, with_metadata: true)
          add :gallery_urls, {:array, :string}, default: []

          # Metadata
          metadata_field(name: :attributes)
          metadata_field(name: :specifications)

          # Publishing
          status_field(values: ["draft", "review", "published", "discontinued"])
          add :published_at, :utc_datetime
          add :featured, :boolean, default: false

          # Audit
          audit_fields(with_user: true)
          deleted_fields()
          timestamps()
        end

        # Indexes for performance
        create unique_index(:products, [:sku])
        slug_field(:products)  # Creates unique index on slug
        type_indexes(:products)
        status_indexes(:products, partial: "status = 'published'")
        metadata_index(:products, field: :attributes)
        timestamp_indexes(:products, fields: [:published_at], order: :desc)
      end
    end
    """
  end

  @doc """
  Example: Order management with relationships.
  """
  def order_table_example do
    """
    defmodule MyApp.Repo.Migrations.CreateOrders do
      use Events.Repo.Migration

      def change do
        create_table :orders do
          # Order identification
          add :order_number, :string, null: false
          add :external_id, :string

          # Relationships
          add :customer_id, references(:users, type: :binary_id, on_delete: :restrict)
          add :shipping_address_id, references(:addresses, type: :binary_id)
          add :billing_address_id, references(:addresses, type: :binary_id)

          # Order details
          status_field(values: [
            "pending", "confirmed", "processing",
            "shipped", "delivered", "cancelled", "refunded"
          ])

          # Dates
          add :placed_at, :utc_datetime, null: false
          add :confirmed_at, :utc_datetime
          add :shipped_at, :utc_datetime
          add :delivered_at, :utc_datetime
          add :cancelled_at, :utc_datetime

          # Financial
          money_field(:subtotal, required: true)
          money_field(:tax_amount)
          money_field(:shipping_cost)
          money_field(:discount_amount)
          money_field(:total, required: true)

          # Shipping info
          add :shipping_method, :string
          add :tracking_number, :string
          add :estimated_delivery, :date

          # Additional data
          metadata_field(name: :customer_notes)
          metadata_field(name: :internal_notes)
          tags_field(name: :flags)

          # Audit
          audit_fields(with_user: true, with_role: true)
          timestamps()
        end

        # Performance indexes
        create unique_index(:orders, [:order_number])
        create index(:orders, [:customer_id])
        create index(:orders, [:external_id])
        status_indexes(:orders)
        timestamp_indexes(:orders, fields: [:placed_at], order: :desc)

        # Composite indexes for common queries
        create index(:orders, [:customer_id, :status])
        create index(:orders, [:status, :placed_at])
      end
    end
    """
  end

  @doc """
  Example: Blog/CMS with multilingual support.
  """
  def article_table_example do
    """
    defmodule MyApp.Repo.Migrations.CreateArticles do
      use Events.Repo.Migration

      def change do
        enable_citext()

        create_table :articles do
          # Content
          title_fields(
            with_translations: true,
            languages: [:es, :fr, :de, :ja],
            type: :citext
          )
          slug_field()

          # Article body stored separately for each language
          add :content, :text, null: false
          add :content_es, :text
          add :content_fr, :text
          add :content_de, :text
          add :content_ja, :text

          # Summary/excerpt
          add :summary, :text
          add :summary_es, :text
          add :summary_fr, :text

          # Author and metadata
          add :author_id, references(:users, type: :binary_id, on_delete: :restrict)
          type_fields(primary: :category, secondary: :section)
          tags_field()

          # SEO
          add :meta_title, :string
          add :meta_description, :text
          add :meta_keywords, {:array, :string}, default: []
          url_field(name: :canonical_url)

          # Media
          file_fields(:featured_image, with_metadata: true)
          add :video_url, :string
          add :podcast_url, :string

          # Engagement
          counter_field(:view_count)
          counter_field(:like_count)
          counter_field(:share_count)
          counter_field(:comment_count)

          # Publishing
          status_field(values: ["draft", "review", "scheduled", "published", "archived"])
          add :published_at, :utc_datetime
          add :scheduled_for, :utc_datetime
          add :featured, :boolean, default: false
          add :sticky, :boolean, default: false

          # Settings
          settings_field(
            name: :display_settings,
            default: %{
              comments_enabled: true,
              show_author: true,
              show_date: true
            }
          )

          # Audit and soft delete
          audit_fields(with_user: true)
          deleted_fields(with_reason: true)
          timestamps()
        end

        # Content indexes
        title_indexes(:articles, fulltext: true)
        create index(:articles, [:content], using: :gin)

        # Performance indexes
        status_indexes(:articles, partial: "status = 'published' AND deleted_at IS NULL")
        timestamp_indexes(:articles, fields: [:published_at], order: :desc)
        type_indexes(:articles)
        tags_field(:articles)  # Creates GIN index

        # Composite indexes
        create index(:articles, [:author_id, :status, :published_at])
        create index(:articles, [:featured, :published_at], where: "status = 'published'")
      end
    end
    """
  end

  @doc """
  Example: Event management with location tracking.
  """
  def event_table_example do
    """
    defmodule MyApp.Repo.Migrations.CreateEvents do
      use Events.Repo.Migration

      def change do
        create_table :events do
          # Event info
          title_fields(required: true)
          slug_field()
          add :description, :text

          # Scheduling
          add :start_time, :utc_datetime, null: false
          add :end_time, :utc_datetime, null: false
          add :timezone, :string, null: false
          add :all_day, :boolean, default: false
          add :recurring_rule, :string  # iCal RRULE format

          # Location
          add :location_type, :string  # "online", "physical", "hybrid"
          add :venue_name, :string
          address_fields(prefix: :venue)
          geo_fields(prefix: :venue, with_accuracy: true)
          url_field(name: :online_meeting_url)

          # Capacity
          counter_field(:max_attendees)
          counter_field(:registered_count)
          counter_field(:waitlist_count)
          add :registration_deadline, :utc_datetime

          # Organizer
          add :organizer_id, references(:users, type: :binary_id, on_delete: :restrict)
          add :organizer_name, :string
          email_field(name: :organizer_email, required: false)
          phone_field(name: :organizer_phone)

          # Categorization
          type_fields(primary: :event_type, secondary: :audience)
          tags_field(name: :topics)

          # Pricing
          add :is_free, :boolean, default: false
          money_field(:price)
          money_field(:early_bird_price)
          add :early_bird_deadline, :utc_datetime

          # Media
          file_fields(:cover_image, with_metadata: true)
          add :gallery_urls, {:array, :string}, default: []

          # Settings
          settings_field(
            name: :registration_settings,
            default: %{
              requires_approval: false,
              allow_waitlist: true,
              allow_cancellation: true
            }
          )

          # Status
          status_field(values: [
            "draft", "published", "registration_open",
            "sold_out", "ongoing", "completed", "cancelled"
          ])

          # Metadata
          metadata_field(name: :custom_fields)
          metadata_field(name: :sponsor_info)

          # Audit
          audit_fields(with_user: true)
          deleted_fields()
          timestamps()
        end

        # Time-based indexes
        create index(:events, [:start_time])
        create index(:events, [:end_time])
        create index(:events, [:start_time, :end_time])

        # Location indexes
        create index(:events, [:location_type])
        create index(:events, [:venue_latitude, :venue_longitude])

        # Status and filtering
        status_indexes(:events, partial: "status IN ('published', 'registration_open')")
        type_indexes(:events)
        tags_field(:events)

        # Composite indexes for common queries
        create index(:events, [:status, :start_time])
        create index(:events, [:organizer_id, :status])
      end
    end
    """
  end

  @doc """
  Example: Multi-tenant SaaS with organization support.
  """
  def organization_table_example do
    """
    defmodule MyApp.Repo.Migrations.CreateOrganizations do
      use Events.Repo.Migration

      def change do
        enable_citext()

        create_table :organizations do
          # Identity
          add :name, :citext, null: false
          slug_field()
          add :legal_name, :string
          add :tax_id, :string

          # Contact
          email_field(name: :primary_email)
          email_field(name: :billing_email, required: false)
          phone_field(name: :primary_phone)
          phone_field(name: :support_phone, required: false)
          url_field(name: :website)

          # Address
          address_fields(prefix: :billing)
          address_fields(prefix: :shipping)

          # Subscription
          add :plan, :string, null: false, default: "free"
          add :subscription_status, :string, default: "active"
          add :trial_ends_at, :utc_datetime
          add :subscription_ends_at, :utc_datetime

          # Limits
          add :max_users, :integer, default: 5
          add :max_projects, :integer, default: 10
          add :storage_limit_gb, :integer, default: 10
          counter_field(:current_users)
          counter_field(:current_projects)
          counter_field(:storage_used_mb)

          # Branding
          file_fields(:logo, with_metadata: true)
          add :brand_colors, :jsonb, default: "{}"
          settings_field(name: :theme_settings)

          # Features
          add :features, {:array, :string}, default: []
          settings_field(name: :feature_flags)

          # Compliance
          add :accepted_terms_at, :utc_datetime
          add :accepted_privacy_at, :utc_datetime
          add :data_retention_days, :integer, default: 90
          add :gdpr_consent, :boolean, default: false

          # API Access
          add :api_key, :string
          add :api_secret_hash, :string
          add :webhook_url, :string
          counter_field(:api_calls_count)
          add :api_calls_limit, :integer, default: 10000

          # Internal
          metadata_field(name: :internal_notes)
          tags_field(name: :labels)
          status_field(values: [
            "pending", "active", "suspended",
            "cancelled", "expired", "deleted"
          ])

          # Audit
          audit_fields(with_user: true)
          deleted_fields(with_user: true, with_reason: true)
          timestamps()
        end

        # Unique constraints
        create unique_index(:organizations, [:slug])
        create unique_index(:organizations, [:primary_email])
        create unique_index(:organizations, [:api_key])

        # Performance indexes
        status_indexes(:organizations, partial: "status = 'active'")
        create index(:organizations, [:plan, :subscription_status])
        create index(:organizations, [:trial_ends_at])

        # Search indexes
        name_indexes(:organizations, fulltext: true)
        metadata_index(:organizations, field: :internal_notes)
      end
    end
    """
  end
end
