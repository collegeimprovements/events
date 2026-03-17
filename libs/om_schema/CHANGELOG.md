# Changelog

All notable changes to OmSchema will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### TypeSpec Auto-Generation
- `OmSchema.TypeGenerator` module for generating Elixir typespecs from schema definitions
- `MySchema.__typespec_ast__/0` - Returns the typespec AST for introspection
- `MySchema.typespec_string/0` - Returns human-readable typespec string
- Automatic type mapping from Ecto types to Elixir types
- Support for required vs nullable fields in typespec generation

#### OpenAPI Schema Generation
- `OmSchema.OpenAPI` module for generating OpenAPI 3.x schemas
- `to_schema/2` - Generate OpenAPI schema from OmSchema module
- `to_components/2` - Generate components for multiple schemas
- `to_paths/2` - Generate API paths for CRUD operations
- `to_document/2` - Generate complete OpenAPI document
- Support for both OpenAPI 3.0 (`nullable: true`) and 3.1 (`type: ["string", "null"]`) styles
- Automatic mapping of field constraints to OpenAPI properties (minLength, maxLength, pattern, enum, etc.)

#### Composable Custom Validators
- `OmSchema.CustomValidators` module with extensible validator system
- Support for validator formats: `{Module, :fun, args}`, `{Module, :fun}`, `&fun/1`, `&fun/2`
- Built-in validators:
  - `validate_luhn/2` - Credit card number validation
  - `validate_no_html/2` - Reject HTML/script tags
  - `validate_json/2` - Valid JSON string validation
  - `validate_not_disposable_email/2` - Block disposable email domains
  - `validate_phone_format/2` - Phone number format validation
  - `validate_url/2` - URL format validation
  - `validate_semantic_version/2` - SemVer format validation
- Field option: `validators: [{Mod, :fun}, ...]`

#### Embedded Schema Validation Propagation
- `embeds_one/3` and `embeds_many/3` macros with `propagate_validations: true` option
- `OmSchema.Embedded.cast_embed_with_validation/3` for manual validation
- `OmSchema.Embedded.validate_embeds/2` for recursive validation
- `MySchema.embedded_schemas/0` introspection function
- Automatic use of embedded schema's `base_changeset/2` for validation

#### I18n Support
- `OmSchema.I18n` module for internationalization
- Support for `{:i18n, "key"}` and `{:i18n, "key", bindings}` message formats
- Configuration: `config :om_schema, translator: MyApp.Gettext`
- `I18n.translate/2` - Translate i18n tuples
- `I18n.translate_errors/2` - Translate all errors in changeset
- `I18n.i18n/2` - Convenience function to create i18n tuples
- Lazy translation at error retrieval time
- Support for Gettext and custom translator modules

#### Sensitive Field Protection
- `OmSchema.Sensitive` module for automatic protocol implementations
- Field option: `sensitive: true` marks fields for redaction
- Auto-generated `Inspect` protocol implementation (redacts sensitive values)
- Auto-generated `Jason.Encoder` protocol implementation (excludes sensitive fields)
- Helper functions:
  - `Sensitive.redact/1` - Redact struct fields
  - `Sensitive.to_safe_map/1` - Convert to map excluding sensitive fields
  - `Sensitive.to_redacted_map/1` - Convert to map with redacted markers
- Configuration options: `@om_derive_inspect`, `@om_derive_jason`

#### Runtime Schema Diffing
- `OmSchema.SchemaDiff` module for comparing schemas to database
- `diff/2` - Compare single schema to database table
- `diff_all/2` - Compare multiple schemas
- `in_sync?/2` - Check if schemas match database
- `format/2` - Human-readable diff output
- `generate_migration/2` - Generate migration code to sync schema with DB
- Diff types detected:
  - Missing columns (in DB or schema)
  - Type mismatches
  - Nullable mismatches
  - Constraint differences

### Changed

- `OmSchema.Helpers.Messages` now supports i18n tuples alongside strings
- Field validation pipeline now calls custom validators after type validations
- `OmSchema.Introspection` updated to delegate to OpenAPI module

### Fixed

- Ecto.Enum values now correctly captured in validation opts for introspection
- Field defaults now properly propagated to validation options

## [1.0.0] - Initial Release

### Core Features

#### Enhanced Field Macro
- Declarative field validation with options like `required`, `min`, `max`, `format`, etc.
- Automatic changeset generation via `base_changeset/2`
- Field introspection via `field_validations/0`

#### Validation Presets
- `email()` - Email validation with format and length constraints
- `username()` - Alphanumeric 3-30 characters
- `password()` - Minimum 8 characters
- `slug()` - URL-safe lowercase with hyphens
- `phone()` - Phone number validation
- `url()` - URL format validation
- And more...

#### Field Group Macros
- `type_fields/1` - Type classification (type, subtype, kind, category, variant)
- `status_fields/1` - Status enum with required values option
- `audit_fields/1` - Created/updated by tracking (URM, user, IP, session)
- `timestamps/1` - Configurable timestamp fields
- `metadata_field/1` - JSONB metadata field
- `soft_delete_field/1` - Soft delete with deleted_at

#### Database Validation
- `OmSchema.DatabaseValidator` for runtime schema-to-DB validation
- `OmSchema.DatabaseValidator.PgIntrospection` for PostgreSQL introspection
- Column, constraint, index, and foreign key validation

#### Constraint DSL
- `constraints do ... end` block for complex constraints
- `unique/2` - Unique constraints (single or composite)
- `foreign_key/2` - Foreign key constraints with options
- `check/1`, `check/2` - Check constraints
- `index/2` - Non-unique indexes
- `exclude/2` - Exclusion constraints (PostgreSQL)

#### Introspection Functions
- `field_validations/0` - All field validation metadata
- `cast_fields/0` - Fields with `cast: true`
- `required_fields/0` - Fields with `required: true`
- `sensitive_fields/0` - Fields with `sensitive: true`
- `immutable_fields/0` - Fields with `immutable: true`
- `constraints/0` - All constraint metadata
- `indexes/0` - All index metadata

[Unreleased]: https://github.com/your-org/om_schema/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/your-org/om_schema/releases/tag/v1.0.0
