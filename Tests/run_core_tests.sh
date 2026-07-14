#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="$ROOT/build/CoreTests"
mkdir -p "$BUILD_DIR"

xcrun swiftc \
  "$ROOT/Tests/CoreRegressionTests.swift" \
  "$ROOT/WorkLog/Models/WorkItem.swift" \
  "$ROOT/WorkLog/Models/SidebarScope.swift" \
  "$ROOT/WorkLog/Database/SQLiteValue.swift" \
  "$ROOT/WorkLog/Database/SQLiteDatabase.swift" \
  "$ROOT/WorkLog/Database/DatabaseManager.swift" \
  "$ROOT/WorkLog/Database/DatabaseMigrator.swift" \
  "$ROOT/WorkLog/Repositories/WorkItemRepository.swift" \
  "$ROOT/WorkLog/Services/MarkdownParser.swift" \
  "$ROOT/WorkLog/Services/MonthlySummaryFormatter.swift" \
  "$ROOT/WorkLog/Services/ModuleDefaults.swift" \
  "$ROOT/WorkLog/Utilities/DateUtils.swift" \
  -lsqlite3 \
  -o "$BUILD_DIR/CoreRegressionTests"

"$BUILD_DIR/CoreRegressionTests"
