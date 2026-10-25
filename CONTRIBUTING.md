# Contributing

Thanks for helping Flutter developers stop losing review cycles. The most
valuable contributions are **new rules backed by a real rejection** and
**corrections to the data tables** (Apple's privacy vocabulary, the SDK →
data-type map, Play's target API deadlines).

## Development

```bash
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
dart run imaji_store_preflight --project test/fixtures/rejected_app
```

CI runs these on the minimum supported SDK (3.8.0) and a pinned current
stable, with `dart format --output=none --set-exit-if-changed .` (on the
pinned stable only) in place of `dart format .`.

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
   and a line to `CHANGELOG.md`. If the rule ships a row marked "planned" in
   the README's "Problems this solves" table, replace the plan issue link
   with the rule id.

## Updating a data table

`lib/src/data/` holds the tables. Every entry cites where it comes from;
keep it that way, and keep entries conservative (only what an SDK collects
by default, only deadlines Google has published).

## Pull requests

Small, focused commits with clear messages. Run the commands above before
pushing.

## AI-assisted contributions

AI tools are fine to use; we just ask you to be open about it.

- Say in the PR description which AI tools you used, if any: none, some or
  most, plus the tool or agent and the model (for example "Claude Code,
  Opus 5.5" or "Copilot, GPT-5"). The pull request template has a box for it.
- Write the PR description and issues yourself, in your own words. Please
  don't paste generated text; short, plain descriptions are welcome.
- Read, run and test every line you submit, and be ready to explain it in
  review.
- Pull requests without the disclosure may be closed.
