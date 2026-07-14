# Contributing

[简体中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

Thank you for contributing to WorkLog. Keep changes focused and preserve native macOS interaction and low resource usage where possible.

## Local Development

1. Open `WorkLog.xcodeproj` with Xcode 14.2 or later.
2. Select the `WorkLog` scheme and `My Mac`.
3. Before submitting a change, run:

```bash
zsh Tests/run_core_tests.sh

xcodebuild \
  -project WorkLog.xcodeproj \
  -scheme WorkLog \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

zsh Tests/run_app_smoke_test.sh
zsh Tests/run_ui_interaction_test.sh
```

The UI interaction test uses an isolated temporary database. The terminal running it needs macOS Accessibility permission.

## Submission Requirements

- Do not commit `build/`, DerivedData, local databases, backups, or personal configuration.
- Examples, test fixtures, and screenshots must use fictional or generic content. Do not include personal information, real work records, or credentials.
- Add a versioned migration in `DatabaseMigrator` for every database schema change.
- Update `README.md`, `README.en.md`, and `CHANGELOG.md` when user-visible behavior changes.
- Pull requests should describe the affected area, verification performed, compatibility risks, and rollback approach.
