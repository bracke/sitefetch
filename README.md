# sitefetch

`sitefetch` is the Ada command-line crate for mirroring a website to a local directory. It is a
thin executable layer over the sibling `sitefetchlib` crate, which contains the reusable crawl,
HTTP, cache, rewrite, robots, and download engine.

The repository split is:

- `sitefetch`: CLI crate. It owns command-line parsing, localized terminal output, summaries, and
  the `sitefetch` executable.
- `sitefetchlib`: reusable library crate at `../sitefetchlib`. It owns the stable Ada API in the
  root `Sitefetch` package.

The CLI starts from one URL, asks `sitefetchlib` to download the document at that address, extract
links and references, follow same-host/subdomain references recursively, and write the fetched files
with local references. Parent-domain traversal can be enabled explicitly.

## Features

- Fetches a website recursively from a starting URL.
- Adds `http://` automatically when the URL has no `http://` or `https://` scheme.
- Saves files into the current directory or a target directory.
- Streams image, movie, PDF, and office-document URLs directly to disk with `Http_Client.Clients.Download_To_File`.
- Uses a bounded worker pool for multiple simultaneous production downloads.
- Reuses pooled HTTP connections within each worker.
- Uses the root response final URL as the main URL after redirects.
- Follows relative URLs and absolute URLs on the same normalized host or dot-boundary subdomains by default.
- Does not download links outside that host-suffix set unless registrable parent-domain traversal is enabled.
- Rewrites same-host and subdomain references to local paths in written documents.
- Ignores unsupported references such as fragments, `mailto:`, `javascript:`, and `data:` URLs.
- Shows marked, colored progress output by default, including warnings for dangerous direct downloads.
- Supports quiet mode for script-friendly operation.
- Supports localized output through an i18n message catalog.
- Supports bounded crawls by page count, depth, bytes written, failure count, retries, request delay, robots.txt policy, and safety mode.

## Usage

```sh
sitefetch [--help] [--version]
sitefetch [--quiet|-q] [--verbose|-v] [--locale LOCALE] [--jsonl] [--json-summary]
          [--max-pages N] [--max-depth N] [--max-bytes N] [--max-failures N]
          [--retries N] [--retry-delay-ms N] [--retry-jitter-ms N]
          [--request-delay-ms N] [--workers N] [--skip-dangerous] [--safe] [--durable-writes]
          [--head MODE] [--robots] [--cache MODE] [--cache-max-stale-ms N]
          [--cache-hash MODE] [--cache-documents-only|--cache-downloads-only]
          [--cache-require-version] [--cache-no-verify-local] [--user-agent UA]
          [--accept-language VALUE] [--accept-encoding VALUE] [--include-parent-domains]
          URL [target]
```

Examples:

```sh
sitefetch example.com
sitefetch https://example.com ./mirror
sitefetch --quiet https://example.com ./mirror
sitefetch --locale de_DE.UTF-8 https://example.com ./mirror
sitefetch --max-pages 250 --max-depth 4 https://example.com ./mirror
sitefetch --skip-dangerous https://example.com ./mirror
```

Arguments:

- `URL`: starting URL to fetch. If no HTTP scheme is present, `http://` is prefixed.
- `target`: optional directory where downloaded files are written. Defaults to the current directory.

Options:

- `--help`, `-h`: show help.
- `--version`: show the program version.
- `--quiet`, `-q`: suppress progress and summary output.
- `--locale LOCALE`, `--locale=LOCALE`: override the detected system locale.
- `--max-pages N`, `--max-pages=N`: stop queueing new pages after N claimed URLs. Use `0` for unlimited.
- `--max-depth N`, `--max-depth=N`: stop following links deeper than N levels from the root. Use `0` for unlimited.
- `--max-bytes N`, `--max-bytes=N`: stop taking or queueing more work after N accumulated
  bytes. Built-in direct downloads are capped before completion with the remaining byte budget;
  injected download callbacks are rejected if they report more bytes than the remaining budget.
  Buffered text documents are counted after they are written. Use `0` for unlimited.
- `--max-failures N`, `--max-failures=N`: stop queueing new pages after N failed downloads. Use `0` for unlimited.
- `--retries N`, `--retries=N`: retry each failed production HTTP fetch/download up to N additional times before recording a failure. Default is `0`.
- `--retry-delay-ms N`, `--retry-delay-ms=N`: initial retry delay in milliseconds. Subsequent retries double the delay. Default is `0`.
- `--retry-jitter-ms N`, `--retry-jitter-ms=N`: add deterministic per-URL jitter up to N milliseconds to retry delays. Default is `0`.
- `--request-delay-ms N`, `--request-delay-ms=N`: delay before each production HTTP request. Default is `0`.
- `--robots`, `--respect-robots`: fetch `/robots.txt` for the effective root origin and skip queued linked URLs whose paths match selected `Disallow` prefixes. Default is off.
- `--ignore-robots`: explicitly keep robots.txt disabled.
- `--cache MODE`, `--cache=MODE`: choose cache behavior. Modes are `ignore`, `revalidate`/`incremental`, `refresh`/`force-refresh`, and `offline`/`offline-only`.
- `--incremental`, `--revalidate-cache`: compatibility aliases for `--cache revalidate`.
- `--refresh-cache`: compatibility alias for `--cache refresh`; bypasses local reuse but writes updated files and sidecars.
- `--offline-cache`: compatibility alias for `--cache offline`; never starts network requests and only reuses valid local cache metadata.
- `--no-cache`: compatibility alias for `--cache ignore`.
- `--cache-max-stale-ms N`, `--cache-max-stale-ms=N`: allow cache reuse for N milliseconds after freshness expiry unless response directives require revalidation.
- `--cache-vary-accept-language`, `--cache-vary-accept-encoding`: allow those `Vary` dimensions in addition to the default `User-Agent` comparison. sitefetch persists and compares the corresponding request header values before reusing cache entries.
- `--cache-documents-only`, `--cache-downloads-only`, `--cache-all`: choose which resource classes use cache metadata.
- `--cache-hash MODE`, `--cache-hash=MODE`: choose local integrity metadata: `fnv1a-64`, `sha256`, or `none`/`size-only`.
- `--cache-require-version`: reject sidecars without the current metadata version.
- `--cache-no-verify-local`: trust local cached files without checking persisted size/hash metadata.
- `--user-agent UA`, `--user-agent=UA`: set the production HTTP `User-Agent` header. Default is `sitefetch/0.1`.
- `--accept-language VALUE`, `--accept-language=VALUE`: set the production HTTP `Accept-Language` header.
- `--accept-encoding VALUE`, `--accept-encoding=VALUE`: set the production HTTP `Accept-Encoding` header. Default is `gzip, deflate`. HTTP `Content-Encoding` decompression is performed by httpclient; sitefetchlib uses this value for request policy and cache `Vary: Accept-Encoding` checks.
- `--workers N`, `--workers=N`: run N simultaneous download workers. Default is `8`; maximum is `64`.
- `--skip-dangerous`: skip direct-download URLs with executable, script, macro-document,
  archive, disk-image, or similar risky extensions.
- `--safe`, `--assets-only-safe`: skip dangerous files and direct-download only common passive
  image, audio, video, and font assets.
- `--durable-writes`: use stricter local write durability. sitefetch asks httpclient to fsync
  completed files and best-effort fsync parent directories after atomic renames where supported.

## Library API

Use the sibling `sitefetchlib` crate when embedding the crawler in another Ada application. The
stable production crawler entry point is `Sitefetch.Crawler`; shared records and options live
in the root `Sitefetch` package. URL/content support helpers live in `Sitefetch.URLs` and
`Sitefetch.Content`, while document extraction/rewrite remains exposed through root `Sitefetch`
helpers. See `../sitefetchlib/README.md` for dependency instructions, support levels, and checked
examples.


## Domain Policy

The default crawl boundary is exact normalized host plus dot-boundary subdomains. By default,
`example.com` includes `example.com` and `*.example.com`, but not `badexample.com`,
`example.com.evil.test`, parent hosts, or sibling subdomains. With `--include-parent-domains`,
the registrable parent domain is also considered internal after a redirect or root selection, but
sitefetch will not cross into a public suffix such as `co.uk` or a private suffix such as
`github.io`.

Public-suffix support uses an embedded table for common multi-label and hosted-service suffixes,
with literal IP hosts treated as terminal hosts and unknown names falling back to the last label.
It is not a vendored full PSL snapshot or complete domain-isolation layer. IDNA handling is limited
to the normalized host returned by the URL parser; punycode labels are matched as ordinary normalized
ASCII labels, and the domain policy performs exact and dot-boundary suffix checks after that
normalization.

## Crawl Etiquette

Robots.txt handling is opt-in so local mirroring of known sites keeps existing behavior. With
`--robots`, sitefetch fetches `/robots.txt` from the effective root origin, applies matching
`User-agent` groups for the configured `--user-agent` with `*` fallback, and evaluates `Allow` and
`Disallow` by longest matching path prefix. `Allow` wins ties. The root URL itself is still fetched.

`Crawl-delay` raises the production request delay when it is larger than `--request-delay-ms`.
Same-origin `Sitemap` URLs are queued as crawl documents when they stay inside the configured domain
policy. This is still prefix-based robots matching, not a full public crawl management layer with
per-host concurrency pools or sitemap XML-specific parsing.

`--request-delay-ms N` adds a delay before each production HEAD, GET, or streamed download request.
The existing `--workers N` option is the global production concurrency cap; there is not yet a
separate per-host concurrency limiter for multi-host subdomain crawls.

## Compression Boundary

HTTP `Content-Encoding` decompression is handled by httpclient. sitefetch configures the production
`Accept-Encoding` request header through sitefetchlib, and sitefetchlib records that request value in
cache sidecars for `Vary: Accept-Encoding` reuse checks. sitefetchlib also inflates gzip sitemap
resources such as `sitemap.xml.gz` so their links can be crawled; that is separate from HTTP
transport decompression.

## Incremental Cache Policy

Cache mode is opt-in. `--cache revalidate` and its `--incremental` alias write a small
`.sitefetch_http_cache` sidecar next to files whose responses include `ETag` or
`Last-Modified`. Later runs send `If-None-Match` or `If-Modified-Since` for that local path.
Buffered documents use conditional GET; streamed downloads use a conditional HEAD preflight and
only stream the body when the server does not return `304 Not Modified`.

A 304 response preserves the existing local file and reports zero written bytes for that URL.
For buffered documents, unchanged cached files are read locally so their links can still be
queued during the run. Streamed downloads in incremental mode use a sibling `.sitefetch_part`
file while transferring. If a transfer fails after response headers are available, the partial
file and its cache sidecar are preserved; later incremental runs can resume it with `Range` and
`If-Range`, then atomically install the completed file.

### Cache Sidecars

`.sitefetch_http_cache` files are implementation metadata, not a stable public interchange format.
They are useful for debugging and tests, but normal users should treat them as owned by sitefetch.
Fields you may see include `Cache-Version`, `URL`, `Final-URL`, `ETag`, `Last-Modified`,
`Cache-Control`, `Expires`, `Vary`, `Request-User-Agent`, `Request-Accept-Language`,
`Request-Accept-Encoding`, `Local-Size`, and `Local-Hash`.

When local verification is enabled, sitefetch uses persisted size/hash metadata to reject corrupt or
mismatched files. Sidecar fields may change across versions; `--cache-require-version` rejects old
or unversioned sidecars, and `--cache-no-verify-local` disables local size/hash verification. Do not
hand-edit sidecars except when debugging or constructing tests.

## Cache Diagnostics

Verbose progress, JSONL progress, and final JSON summaries report cache decisions explicitly:

- `cache_reused`: a valid local cache entry was used. No response body bytes are written for that URL.
- `cache_revalidate`: sitefetch is attempting a conditional request using cached validators such as
  `ETag` or `Last-Modified`.
- `cache_rejected`: local cache metadata was checked but could not be reused. Common reasons include
  missing sidecars or files, size/hash mismatches, metadata version mismatches, rejected or changed
  `Vary` request headers, stale entries without validators, `offline cache entry missing`,
  `offline cache entry stale`, `offline cached file unreadable`, and
  `offline partial cache entry unusable`.

JSONL progress includes `cache_decision` values such as `reused`, `revalidate`, or `rejected`, plus
the rejection reason when available. Final JSON summaries include `cache_hits`,
`cache_revalidations`, `cache_rejections`, and `cache_rejection_reasons`. The
`cache_rejection_reasons` field is a JSON object mapping each aggregated `cache_rejected` reason
string to its count, and is `{}` when no cache rejections were reported.

A final JSON summary has this compact machine-readable shape for diagnostics consumers:

```json
{
  "type": "summary",
  "success": true,
  "attempted": 12,
  "written": 10,
  "skipped_external": 1,
  "skipped_unsupported": 0,
  "skipped_limit": 0,
  "bytes_written": 48192,
  "failed": 0,
  "retries": 1,
  "cache_hits": 3,
  "cache_revalidations": 2,
  "cache_rejections": 2,
  "cache_rejection_reasons": {
    "offline cache entry stale": 1,
    "Vary Accept-Encoding mismatch": 1
  },
  "robots_allowed": 8,
  "robots_disallowed": 1,
  "robots_loaded": 1,
  "robots_failed": 0,
  "redirects": 1,
  "redirect_hops": 2,
  "elapsed_seconds": 0.42,
  "failed_url": "",
  "failed_reason": "",
  "failed_download_count": 0,
  "failed_downloads": []
}
```

JSON output compatibility notes:

- `--jsonl` emits zero or more `progress` records followed by one final `summary` record.
- `--json-summary` emits only the final `summary` record.
- Existing field names and JSON value types are intended to stay stable before a breaking release.
- New fields may be added; consumers should ignore unknown fields.
- `cache_rejection_reasons` object keys are free-form diagnostic reason strings, not enum values.

Top-level final summary fields are:

| Field | Meaning |
| --- | --- |
| `type` | Always `summary` for the final summary record. |
| `success` | Whether the crawl completed without recorded failure. |
| `attempted`, `written`, `bytes_written`, `failed` | Core crawl totals from sitefetchlib statistics. |
| `skipped_external`, `skipped_unsupported`, `skipped_limit` | Skip counters for out-of-scope, unsupported, and limit-blocked URLs. |
| `retries` | Number of retry progress events observed during the run. |
| `cache_hits`, `cache_revalidations`, `cache_rejections` | Cache decision counters observed during the run. |
| `cache_rejection_reasons` | Object mapping cache rejection reason text to counts. |
| `robots_allowed`, `robots_disallowed`, `robots_loaded`, `robots_failed` | Robots.txt decision and fetch counters. |
| `redirects`, `redirect_hops` | Redirect event count and total redirect hops reported by progress diagnostics. |
| `elapsed_seconds` | Wall-clock runtime in seconds. |
| `failed_url`, `failed_reason` | Last top-level failed URL and reason, or empty strings. |
| `failed_download_count`, `failed_downloads` | Count and list of failed download records. |

## Retry Policy

Production HTTP fetches and streamed downloads can retry transient `httpclient` failures before a
URL is recorded as failed. Retries are disabled by default. `--retries N` configures additional
attempts after the initial try, and `--retry-delay-ms N` applies exponential backoff starting with
that delay. Injected testing callbacks are not retried, so deterministic tests and custom adapters
keep explicit control over failure behavior.

## Download Scheduling

Production fetches download the root document first so redirects can establish the main URL.
Discovered internal references are then processed by a bounded worker pool with multiple simultaneous
GET requests. The pending queue prioritizes page-like HTML documents first, text-like support files
next, passive media and font assets after that, and larger binary assets last. URLs with raster
image, audio, video, archive, font, ebook, executable, PDF, office-document, or other binary
asset extensions are streamed straight to their local file path with
`Http_Client.Clients.Download_To_File`; SVG is kept parseable so embedded references can be
rewritten. For production HTTP crawls, page-like candidates are probed with HEAD first by
default; a final URL with a direct-download extension or a passive binary Content-Type is
streamed instead of buffered. Passive binary types include `application/octet-stream`,
`application/pdf`, raster images, audio/video, and fonts, including downloads with no extension.
Missing `Content-Type` remains parseable for compatibility. If the probe fails or does not
provide useful headers, sitefetch falls back to the extension-based decision and ordinary GET
path. Use `--head=ambiguous` to probe only extensionless non-directory paths, or `--head=off` to
disable HEAD preflights.
Other documents are buffered in memory up to sitefetch's 128 MiB response and decoded-body limit.
Streamed downloads keep bounded chunked file-copy memory use without a configured file-size cap.
Query-string variants are written with a short hash suffix in the local filename so transformed
image URLs do not overwrite each other. In default mode, dangerous direct-download extensions are
still downloaded but progress output marks them with a warning. Use `--skip-dangerous` to skip risky
extensions, or `--safe` to restrict direct downloads to common passive image, media, and font assets.
When an in-memory response declares passive binary content, it is written without link extraction
or reference rewriting. Each worker owns an initialized
`httpclient` client with connection pooling
enabled and HTTP/2 preferred while still allowing supported fallback. Reuse remains subject to HTTP
response framing, server `Connection` headers, origin compatibility, TLS/proxy settings, and the
pooling policy in `httpclient`. Failed linked downloads are reported and counted, but they do not
stop remaining queued downloads from being attempted. Summary `attempted` counts fetches or
downloads that actually start, not links that were only discovered or skipped by limits.
`max-bytes` is an accumulated written-byte threshold: a write that crosses the threshold is counted,
and workers then stop taking additional queued work.

## Output

The final summary includes attempted, written, skipped, failed, and elapsed-time counts. When downloads fail, it also
lists every failed URL with its reported reason when available.

Normal output is marked and colored by semantic role:

- `[*]`: informational fetch/start/count messages.
- `[+]`: successful writes and completion messages.
- `[-]`: skipped external references.
- `[.]`: muted messages such as ignored or already visited references.
- `[!]`: errors and failed fetches.
- `[=]`: headers such as help/version output.

Set `NO_COLOR` in the environment to disable ANSI colors while keeping the markers:

```sh
NO_COLOR=1 sitefetch https://example.com ./mirror
```

## Localization

`sitefetch` reads user-facing messages from `share/sitefetch/messages.catalog` using the `i18n` Ada library.

Locale selection order:

1. `--locale LOCALE` or `--locale=LOCALE`
2. `LC_ALL`
3. `LC_MESSAGES`
4. `LANG`
5. English fallback

Locale values such as `de_DE.UTF-8` are normalized for lookup. CLDR 48 Modern language
identifiers are accepted and render through deterministic fallback: exact locale, then parent
subtags such as `zh-hant`, then base language, then English. The catalog keeps the existing
reviewed translations intact and adds generated provisional translations for the remaining CLDR
Modern language IDs, marked with `meta.provisional = "true"`. Parent-locale and English fallback
still apply when a key is missing.

## Build

`sitefetch` is an Alire binary crate. The project file is `sitefetch.gpr`, and the executable name
is `sitefetch`.

Use Alire GNAT 15 only. The development, release, and tests manifests pin
`gnat_native = "=15.2.1"`. Confirm with:

```sh
alr exec -- gnatls --version
```

Do not run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, or `gprbuild`
in this workspace. Use `alr exec -- ...` for compiler, prover, and builder
commands so PATH cannot select a different GNAT installation.

Local path dependencies are pinned in `alire.toml` for this sibling checkout:

- `sitefetchlib` at `../sitefetchlib`
- `i18n` at `../i18n`
- `terminal_styles` at `../terminal_styles`
- `project_tools` at `../project_tools`

These pins are development workspace metadata, not release dependency metadata. Before publishing or tagging a release archive, verify that public dependency declarations resolve from the intended Alire index or release source archive and that local `[[pins]]` entries are removed from the release manifest, or are kept only in an explicitly documented maintainer workspace overlay. Use `sitefetch.alire.release.toml` as the pin-free publish-manifest template for the CLI crate. The shipped `bin/check_sitefetch` tool audits that the committed development pins, release template, and this release-handling note stay in sync.

To prepare pin-free publish manifests in a staging directory without modifying the checkout manifests:

```sh
./bin/check_sitefetch --prepare-release-manifests /tmp/sitefetch-release
./bin/check_sitefetch --prepare-release-source /tmp/sitefetch-release
./bin/check_sitefetch --prepare-release-build /tmp/sitefetch-release
./bin/check_sitefetch --validate-release-manifests /tmp/sitefetch-release
./bin/check_sitefetch --validate-release-source /tmp/sitefetch-release
./bin/check_sitefetch --validate-release-build-workspace /tmp/sitefetch-release
./bin/check_sitefetch --validate-release-build /tmp/sitefetch-release
./bin/check_sitefetch --quiet --validate-release-source /tmp/sitefetch-release
```

The manifest preparation command writes `sitefetch/alire.toml`, `sitefetchlib/alire.toml`, and `httpclient/alire.toml` under the target directory from the checked release templates. The source preparation command copies the staged source tree for those crates, skips generated/local state directories such as `alire/`, `config/`, `bin/`, `obj/`, and `lib/`, overlays the pin-free release manifests, and runs source validation. The build preparation command also stages local build-only dependency crates (`zlib`, `regexp`, `i18n`, `terminal_styles`, and `project_tools`) and writes `alire.build.toml` overlays with local pins. Published `alire.toml` files remain pin-free; build validation temporarily activates the build overlays and restores the pin-free manifests afterwards. The manifest validation command checks an existing staged directory for that layout, rejects local pins, and verifies the expected release dependencies. The source validation command additionally requires each staged crate to include its expected `.gpr` file, `src/`, `README.md`, and `LICENSE`. The build workspace validation command verifies the staged dependency crates and build-only overlays without running Alire builds. The build validation command runs `alr build` in the staged `httpclient`, `sitefetchlib`, and `sitefetch` crates after structural validation, then runs `alr exec -- gnatprove -P sitefetch.gpr --level=0 --mode=check` in the staged `sitefetch` crate. The default `./bin/check_sitefetch` release readiness path also runs the local GNATprove check, CLI tests, sibling release checkers for `sitefetchlib`, `i18n`, and `terminal_styles`, and the `project_tools` build, GNATprove, test, and public API smoke checks. Add `--quiet` before a release validation subcommand when only the exit status matters.

See `../sitefetchlib/README.md` for library-specific build and dependency details. See `docs/SPARK.md` for the currently proved `sitefetch` surface and the GNATprove release command.

Typical build command, when the Ada toolchain and dependencies are available:

```sh
alr build
```

## Generated Build Outputs

This split treats Alire workspace state and build products as generated local output. The `alire/`,
`config/`, `bin/`, `obj/`, and `lib/` directories are ignored for the CLI, library, test, smoke,
and example crates. `alr build` recreates these directories as needed, including
`bin/check_sitefetch` itself. The default `./bin/check_sitefetch` run rebuilds the CLI crate and
CLI tests; release-staging validation subcommands may also create build output in staged dependency
crates.

It is safe to remove those generated directories when stale binder, object, or library output makes
recursive searches noisy. After cleanup, run `alr build` from this crate to recreate the CLI tools,
then run `./bin/check_sitefetch` for CLI validation. Run the library crate's own checks from
`../sitefetchlib` when validating library tests, examples, and public API smoke coverage. For source
audits, prefer scanning `src/`, test source directories, docs, and example source files instead of
unrestricted recursive searches over build output directories.

## Tests

The CLI test suite lives in `tests`. Library tests, public API smoke tests, and examples live under
`../sitefetchlib`; see `../sitefetchlib/README.md` for their details.

Recommended CLI validation command, when the Ada toolchain and dependencies are available:

```sh
alr build
./bin/check_sitefetch
```

This builds the CLI crate, runs `alr exec -- gnatprove -P sitefetch.gpr --level=0 --mode=check`, builds and runs the CLI tests, then runs sibling release checks for `sitefetchlib`, `i18n`, `terminal_styles`, and `project_tools`.
For a targeted CLI test run:

```sh
cd tests
alr build
./bin/tests
```

## Project Layout

```text
sitefetch/                   CLI crate, this directory
  src/                       CLI, app, progress, and message Ada sources
  share/sitefetch/messages.catalog
                             localized CLI message catalog
  tests/                     CLI AUnit test subcrate
  sitefetch.gpr              CLI GNAT project file
  alire.toml                 CLI Alire crate metadata

../sitefetchlib/             reusable library crate
  src/sitefetch.ads          stable root records and shared types
  src/sitefetch.adb          root helper wrappers
  src/sitefetch-urls.ads     public URL/local-path helper implementation owner
  src/sitefetch-content.ads  public content/MIME helper implementation owner
  src/sitefetch-*.ads        crawler, helper, testing, and internal child packages
  tests/                     library AUnit test subcrate
  sitefetchlib.gpr           library GNAT project file
  alire.toml                 library Alire crate metadata
```

## License

`sitefetch` is licensed as declared in `alire.toml`:

```text
MIT OR Apache-2.0 WITH LLVM-exception
```
