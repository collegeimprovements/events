# Changelog

All notable changes to OmMigration will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Full Up/Down Migration Support**: Complete support for reversible migrations
  - Pipeline API: `alter_table/2`, `drop_table/2`, `drop_index/3`, `drop_constraint/3`, `rename_table/2`, `rename_column/2`
  - DSL Macros: `alter`, `add`, `remove`, `modify`, `drop_table`, `drop_index`, `drop_constraint`, `rename_table`, `rename_column`
  - Token helpers: `Token.remove_field/2`, `Token.modify_field/4`
  - TokenValidator support for all new token types
  - 37 new tests for up/down operations

- **New FieldBuilders**: Extended field builder library with 6 new modules
  - `Identity` - Email, username, phone, and name fields with unique indexes
  - `Authentication` - Password, OAuth, and magic link authentication fields
  - `Profile` - Bio, avatar, location, and social fields
  - `Money` - Decimal currency fields with configurable precision/scale
  - `Metadata` - JSONB metadata fields with GIN indexes
  - `Tags` - String array fields with GIN indexes

- **TokenValidator Integration**: Executor now validates tokens before execution
  - Validates token type, name, fields, primary keys, indexes, foreign keys, constraints
  - Automatic validation on `Executor.execute/2` (can skip with `skip_validation: true`)
  - Provides clear error messages for invalid tokens

- **Comprehensive Test Coverage**: Added tests for previously untested modules
  - `TokenValidator` - 30+ validation tests
  - `DSL` - Token construction equivalents
  - `Helpers` - Pure utility function tests
  - `FieldBuilders` - Extended to 63 tests covering all builders

### Changed

- **FieldBuilder.merge_config/2**: Now correctly handles user-passed `:fields` option
  - User can pass `fields: [:field1, :field2]` directly for explicit field lists
  - `:only`/`:except` filtering still works for filtering default fields
  - Enables Money FieldBuilder pattern of specifying field names directly

### Deprecated

- **PipelineExtended**: Marked as deprecated in favor of FieldBuilders
  - `add_authentication_fields/3` -> Use `Authentication.add/2`
  - `add_profile_fields/2` -> Use `Profile.add/2`
  - `add_address_fields/2` -> Use `Profile.add(token, only: [:location])`
  - Functions unique to PipelineExtended will be migrated in future release

## [1.0.0] - 2024-01-01

### Added

- **Token-Based Architecture**: Central data structure for migration composition
  - `Token` struct holds table name, fields, indexes, constraints
  - Immutable operations for building migration specifications
  - `Token.new/2`, `Token.add_field/4`, `Token.add_index/4`, `Token.add_constraint/4`

- **DSL Macros**: Declarative migration syntax
  - `create_table/2` - Create tables with pipeline composition
  - `alter_table/2` - Modify existing tables
  - `drop_table/2` - Remove tables with options
  - `create_index/3`, `drop_index/2` - Index management
  - `rename_table/2`, `rename_column/4` - Renaming operations

- **DSLEnhanced**: Extended DSL with field helpers
  - `field/3` - Standard field definition
  - `uuid_primary_key/1` - UUID primary key with sensible defaults
  - `belongs_to/3` - Foreign key references
  - `timestamps/1` - inserted_at/updated_at fields
  - `soft_delete/1` - deleted_at field for soft deletion
  - `status/2`, `metadata/1`, `tags/1` - Common field patterns

- **FieldBuilders**: Reusable field composition modules
  - `Timestamps` - inserted_at, updated_at, deleted_at
  - `AuditFields` - User tracking, IP, session, change history
  - `SoftDelete` - Soft deletion with optional tracking
  - `StatusFields` - Status/substatus classification
  - `TypeFields` - Type/subtype classification

- **Pipeline Composition**: Fluent API for building migrations
  - `Pipeline` - Basic table operations
  - `PipelineExtended` - Common field patterns

- **Executor**: Migration execution engine
  - Translates tokens to Ecto.Migration calls
  - Handles create, alter, drop, index, rename operations
  - Support for timestamps, foreign keys, constraints

- **Helpers**: Utility functions for migrations
  - `index_name/2`, `unique_index_name/2` - Consistent index naming
  - `constraint_name/2`, `fk_constraint_name/2` - Constraint naming
  - `validate_field_options/2` - Option validation
  - `merge_with_defaults/2` - Config merging

- **Behaviours**: Standardized interfaces
  - `FieldBuilder` - Contract for field builder modules
  - `default_config/0`, `build/2`, `indexes/1` callbacks

- **TokenValidator**: Comprehensive token validation
  - Validates structure before execution
  - Catches common errors early
  - Clear error messages for debugging

### Technical Details

- Zero runtime dependencies (compile-time only)
- 100% test coverage on critical paths
- Composable, functional design
- Compatible with Ecto.Migration
