# AGENTS.md

## 沟通

- 默认使用中文回复；代码、命令、变量名、路径保持英文。
- 先给结论，再给必要说明；简洁直接。
- 报告 Git 操作时明确说明：检查结果、暂存内容、提交信息、推送/发布结果。

## 工作目录

- 只在当前 `hyb_farm_desktop/` 独立仓库中工作。
- 禁止在父目录 `F:\My_Project\flutter_hybai_farm` 执行 Git 修改、提交、推送或发布操作。
- 远程仓库：`origin` → `https://github.com/ldm0715/hyb_farm_desktop.git`
- 默认分支：`main`。

## 自动化提交与发布触发词

用户使用下列明确指令时，视为授权执行完整流程，不必逐步再次询问：

| 用户意图 | 必须执行的流程 |
| --- | --- |
| “提交并推送” | 检查 → `flutter analyze` → `flutter test` → 暂存 → 展示摘要 → 提交 → 推送 `main`。 |
| “发布 vX.Y.Z” / “提交并发布 X.Y.Z” | 校验版本和更新日志 → 检查与测试 → 暂存 → 展示摘要 → 提交并推送 `main` → 创建并推送 `vX.Y.Z` 标签。 |

提交前必须展示暂存变更摘要；提交信息必须为简洁英文。

## 版本发布规则

- `pubspec.yaml` 中的 `version: X.Y.Z` 是应用版本唯一来源。
- `CHANGELOG.md` 必须包含 `## [X.Y.Z] - YYYY-MM-DD` 对应段落，内容使用中文。
- Git 标签必须为 `vX.Y.Z`，并且与 `pubspec.yaml` 版本完全一致。
- 推送标签后由 `.github/workflows/release-windows.yml` 自动发布，不要手动上传本地构建文件。
- GitHub Release 必须包含：

```text
HYB-Farm-Desktop-X.Y.Z-Setup.exe
HYB-Farm-Desktop-X.Y.Z-windows-x64-portable.zip
HYB-Farm-Desktop-X.Y.Z-SHA256.txt
```

## 发布前检查

```bash
git status --short
git diff --check
flutter analyze
flutter test
```

正式发布还必须确认：

```bash
# 版本一致性示例
pubspec.yaml: version: 0.1.0
CHANGELOG.md: ## [0.1.0] - 2026-08-15
git tag: v0.1.0
```

任何一项不一致、测试失败、工作区存在未经说明的异常改动或远程拒绝推送时，停止并报告原因。

## 红线

以下操作即使用户表达“自动执行”也必须单独确认：

- 删除文件、目录、Git 历史或标签；
- 修改 `.env`、密钥、token、证书、GitHub Secrets 或现有 CI/CD 凭据；
- `git push --force`、`git rebase`、`git reset --hard`；
- 生产部署、`npm publish` 或其他公开发布；
- 在父仓库 `F:\My_Project\flutter_hybai_farm` 中执行任何 Git 写操作。

## 忽略与安全

- 不提交 `/build/`、`/dist/`、`.env`、`.pfx`、`.p12`、`.pem`、`.key`。
- 允许提交 `.github/workflows/release-windows.yml`、`installer/hyb_farm_desktop.iss`、`README.md`、`CHANGELOG.md` 和 `LICENSE`。
- Windows 构建前关闭 `hyb_farm_desktop.exe`，避免 `WebView2Loader.dll` 被占用。
