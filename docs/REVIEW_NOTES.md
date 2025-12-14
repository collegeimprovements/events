# Code Review Notes

Collected findings to revisit (see file references for details):

1. **Idempotency record state** (`lib/events/infra/idempotency/idempotency.ex:353-443`)  
   `start_processing/1` returns a freshly built `%Record{}` instead of mutating/reloading the loaded struct, so `complete/2`, `fail/2`, etc. operate on a struct with `__meta__.state == :built` and missing key/scope data. Fix by keeping the persisted struct (or reloading) before passing it downstream.

2. **AsyncResult indexed settlement** (`lib/events/types/async_result.ex:395-505`, `1327-1345`)  
   `parallel_map/3` with `indexed: true` reconstructs `{input, result}` pairs using `Enum.at/2`. When `ordered: false`, the original input order diverges, producing mismatched pairs; even when ordered, the repeated `Enum.at/2` makes it O(n²). Consider forcing ordered mode or returning `{input, result}` straight from worker tasks to keep correct associations.

3. **S3 list sorting** (`lib/events/services/s3/client.ex:279-286`)  
   `Enum.sort_by/3` receives the `DateTime` module instead of a comparator function, so listing objects raises `undefined function DateTime/2`. Use `&DateTime.compare/2` (or a tuple sorter) and guard against `nil` timestamps.

4. **S3 presign API** (`lib/events/services/s3/client.ex:167-185`)  
   `presigned_url/5` returns a full URL for `:get` but only the POST URL (without fields) for `:put`, so callers cannot use the returned data to upload. Either expose both URL and form fields for POST or switch to `ReqS3.presign_url/1` for real PUT URLs.

5. **S3 glob pagination** (`lib/events/services/s3/request.ex:641-647`)  
   `expand_glob/3` fetches a single page (`limit: 10_000`) and drops the continuation token, so patterns only see the first chunk of keys. Needs pagination over `next` tokens (or `list_all`) to cover large prefixes.

6. **Skipped idempotency integration tests** (`test/events/idempotency_test.exs:153-208`)  
   All end-to-end tests for `execute/3` are `@tag :skip`, leaving the DB-backed flow untested (and letting bugs like #1 slip through). Re-enable once the sandbox wiring is ready, or guard with `@tag :integration` plus a CI job that runs them.

These notes are for follow-up review/discussion; no fixes have been applied yet.
