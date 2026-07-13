# Privacy Notice

[简体中文](PRIVACY.md) | [English](PRIVACY.en.md)

WorkLog is a local-first macOS application. It has no account system, does not connect to a WorkLog-operated server, and includes no analytics, advertising, or telemetry SDKs.

## Local Data

- Tasks, categories, months, and operation timestamps are stored in a local SQLite database.
- Database backups are stored in the local Application Support directory.
- Markdown import reads only files explicitly selected by the user.
- Markdown export writes only to a location explicitly selected by the user.

WorkLog does not upload task content, databases, or backups. Data synchronized through iCloud Drive, third-party synchronization tools, or user-configured backup services is governed by those services and the user's settings.

## Public Repository

User databases, backups, real work records, personal configuration, credentials, and screenshots containing personal information must not be committed to this repository. Examples and demonstration screenshots must use fictional or generic content.

## Data Removal

Uninstalling the app does not automatically remove data from Application Support. To remove all local WorkLog data, first confirm that the backups are no longer needed, then delete:

```text
~/Library/Application Support/WorkLog/
```
