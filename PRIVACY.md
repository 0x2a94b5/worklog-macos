# 隐私说明

[简体中文](PRIVACY.md) | [English](PRIVACY.en.md)

WorkLog 是本地优先的 macOS 应用，不提供账号系统，不连接 WorkLog 自有服务器，也不包含分析、广告或遥测 SDK。

## 本地数据

- 任务、分类、月份和操作时间保存在本机 SQLite 数据库中。
- 数据库备份保存在本机 Application Support 目录中。
- Markdown 导入只读取用户主动选择的文件。
- Markdown 导出只写入用户主动选择的位置。

WorkLog 不会主动上传任务内容、数据库或备份。通过 iCloud Drive、第三方同步工具或用户自行配置的备份服务产生的数据同步，由对应服务和用户设置负责。

## 公开仓库

本仓库不应提交用户数据库、备份、真实工作记录、个人配置、凭据或包含个人信息的截图。仓库中的示例和演示截图均应使用虚构或通用内容。

## 删除数据

卸载 App 不会自动删除 Application Support 中的数据。需要彻底删除时，请先确认不再需要备份，然后删除以下目录：

```text
~/Library/Application Support/WorkLog/
```
