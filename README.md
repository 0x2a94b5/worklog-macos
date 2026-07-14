# WorkLog

[简体中文](README.md) | [English](README.en.md)

[![CI](https://github.com/0x2a94b5/worklog-macos/actions/workflows/ci.yml/badge.svg)](https://github.com/0x2a94b5/worklog-macos/actions/workflows/ci.yml)

WorkLog 是一个使用 SwiftUI、AppKit 和系统 SQLite 开发的原生 macOS 月度工作清单 App，最低支持 macOS 12。

它面向习惯按月份记录工作内容的用户，强调原生交互、本地数据和长期低资源占用。

![WorkLog 主界面](Docs/Screenshots/worklog-main.png)

## 当前功能

- 按月份、分类及“未完成 / 已完成”筛选任务
- 主任务与子任务关联、折叠及同级拖动排序
- 单击选中、双击编辑标题和分类
- 键盘方向键浏览父子任务，空格切换完成状态，Return 编辑
- 全局搜索并定位到任务
- 自动创建当前月份
- Markdown 追加导入，不覆盖已有数据
- 导出标准 Markdown `.md` 文件，不包含分类、备注和时间等内部字段
- SQLite 本地持久化、版本迁移、事务保护、跨天滚动备份和故障恢复
- 永久删除后可使用 `Command-Z` 恢复当前会话中的任务
- 月度复盘生成与复制

## Markdown 格式

```markdown
2026-07
---
[x]已完成任务
[ ]未完成任务
4. 主任务
   - [ ] 子任务
```

导入时，缺少的状态默认为“未完成”，缺少的分类使用“未分类”，备注为空，创建和更新时间使用导入时的当前时间。导入只追加到目标月份；如需修改已有任务，请在清单中双击编辑。

## 构建

### 环境要求

- macOS 12 或更高版本
- Xcode 14.2 或更高版本

### 获取源码

```bash
git clone https://github.com/0x2a94b5/worklog-macos.git
cd worklog-macos
```

### Xcode

打开 `WorkLog.xcodeproj`，选择 `WorkLog` Scheme 和 `My Mac` 运行。

### 命令行

```bash
xcodebuild \
  -project WorkLog.xcodeproj \
  -scheme WorkLog \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

本地 Debug App：

```text
build/DerivedData/Build/Products/Debug/WorkLog.app
```

核心回归测试：

```bash
zsh Tests/run_core_tests.sh
```

构建后的启动冒烟测试：

```bash
zsh Tests/run_app_smoke_test.sh
```

关键输入 UI 交互测试：

```bash
zsh Tests/run_ui_interaction_test.sh
```

UI 测试使用独立临时数据库，不读取或修改正式数据；执行它的终端需要具有 macOS“辅助功能”权限。

正式分发应使用 Developer ID 签名、Hardened Runtime 和 Apple 公证；本地 `CODE_SIGNING_ALLOWED=NO` 构建仅用于开发验证。

## 数据与备份

数据库位置：

```text
~/Library/Application Support/WorkLog/worklog.sqlite
```

数据库备份位置：

```text
~/Library/Application Support/WorkLog/Backups/Database/
```

App 每天生成一份完整 SQLite 备份并保留最近 14 份。长期保持运行时，会在跨天、系统唤醒或应用重新激活时后台检查备份；数据库升级前额外备份，菜单“工作项 > 备份数据库”可手动备份。数据库无法打开时，App 会提供经过完整性校验的备份恢复界面，并在替换前保留故障文件。Markdown 导出是便于阅读和交换的文本副本，不代替完整数据库备份。

WorkLog 不使用网络服务，任务内容、分类和备份均保存在本机。

详细的数据处理说明见[隐私说明](PRIVACY.md)。公开仓库只包含通用示例和演示截图，不包含用户数据库、备份或真实工作记录。

## 代码结构

```text
WorkLog/
├── App/              App 生命周期与菜单
├── Models/           月份、任务和状态模型
├── Database/         SQLite 封装、迁移和备份
├── Repositories/     数据访问与事务
├── Services/         Markdown 解析、月度复盘与默认分类
├── ViewModels/       页面状态和业务操作
├── Views/            SwiftUI 界面
└── Utilities/        日期工具
```

## 参与贡献

请阅读[中文贡献指南](CONTRIBUTING.md)或 [English contributing guide](CONTRIBUTING.en.md)。提交前至少运行核心回归测试和 Debug 构建。

## 许可证

本项目基于 [MIT License](LICENSE) 发布。
