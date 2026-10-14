# Contributing

Thanks for helping Flutter developers stop losing review cycles. The most
valuable contributions are **new rules backed by a real rejection** and
**corrections to the data tables** (Apple's privacy vocabulary, the SDK →
data-type map, Play's target API deadlines).

## Development

```bash
dart pub get
dart format .
dart analyze          # must report "No issues found!"
dart test
dart run imaji_store_preflight --project test/fixtures/rejected_app
```

CI runs exactly these on the minimum supported SDK and on the latest stable.

## Adding a rule

1. **Start from evidence.** Open an issue describing the rejection or silent
   failure: the App Review guideline or ITMS code, the reviewer's wording
   (anonymised), or the platform behaviour, plus the public Apple/Google
   documentation that explains it. A rule without a documented source will
   not be merged.
2. **Write the rule** in `lib/src/rules/` by extending `Rule`:
   - `id`: kebab-case, stable forever (users reference it in config).
   - `title`: one line, phrased as the property that should hold.
   - `why`: which rejection or silent failure it prevents, in terms a
     developer who has never seen it can follow.
   - `fix`: what to change, concretely.
   - `docs`: `https://` links to the public documentation it is built on.
   - `check(context)`: yield findings via `finding(message, path:, line:)`.
     Read files only through `context.project` — it parses each file once,
     records unreadable ones, and gives you line numbers.
   - Options: list keys in `optionKeys` and validate them in
     `validateOptions`; read them from `context.options`.
   Prefer false negatives over false positives: a lint people ignore protects
   nobody. Use `Severity.warning` for heuristics.
3. **Register it** in `lib/src/rules/all_rules.dart`.
4. **Test it** in `test/rules/` with at least one passing and one failing
   synthetic fixture (see `test/support/fixtures.dart`). Fixtures must be
   invented: no real app names, bundle ids, hostnames or people.
5. **Document it**: add a row to the README rule table (a test enforces this)
   and a line to `CHANGELOG.md`.

## Updating a data table

`lib/src/data/` holds the tables. Every entry cites where it comes from;
keep it that way, and keep entries conservative (only what an SDK collects
by default, only deadlines Google has published).

## Pull requests

Small, focused commits with clear messages. Run the commands above before
pushing.
