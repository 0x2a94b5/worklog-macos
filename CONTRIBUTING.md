# 参与贡献

[简体中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

感谢你参与改进 WorkLog。提交变更前请先确认改动范围清晰，并尽量保持原生 macOS 交互和低资源占用。

## 本地开发

1. 使用 Xcode 14.2 或更高版本打开 `WorkLog.xcodeproj`。
2. 选择 `WorkLog` Scheme 和 `My Mac` 运行。
3. 提交前执行：

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

UI 交互测试使用隔离临时数据库，执行终端需要具有 macOS“辅助功能”权限。

## 提交要求

- 不要提交 `build/`、DerivedData、本地数据库、备份或个人配置。
- 示例、测试夹具和截图必须使用虚构或通用内容，不得包含个人信息、真实工作记录或凭据。
- 数据库结构变更必须通过 `DatabaseMigrator` 增加版本迁移。
- 用户可见行为变更应同步更新 `README.md` 和 `CHANGELOG.md`。
- Pull Request 应说明影响范围、验证方式和潜在兼容性风险。
