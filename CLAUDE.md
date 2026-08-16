# CLAUDE.md

## 项目与仓库边界

- 当前目录 `hyb_farm_desktop/` 是 **HYB Farm Desktop** 的独立 Flutter Windows 项目。
- 所有 Git、构建、测试和发布命令必须在当前目录执行；不要在父目录 `F:\My_Project\flutter_hybai_farm` 运行 Git 命令。
- 当前仓库远程：`origin = https://github.com/ldm0715/hyb_farm_desktop.git`
- 目标分支：`main`。
- 不修改父目录的 `.git`、`.gitignore`、提交历史或已跟踪文件。父目录与当前项目是两个不同的 Git 上下文。
- 以后所有的发布（版本号更新、CHANGELOG、tag、push、Release）都在当前目录 `hyb_farm_desktop/` 内进行，一律不在根目录 `F:\My_Project\flutter_hybai_farm` 发布。

## 发布产物

推送版本标签 `vX.Y.Z` 会触发 `.github/workflows/release-windows.yml`，自动执行：

1. 校验 tag 与 `pubspec.yaml` 的版本一致；
2. 从 `CHANGELOG.md` 提取对应 `## [X.Y.Z]` 段落作为 GitHub Release Notes；
3. 执行 `flutter analyze`、`flutter test`、`flutter build windows --release`；
4. 生成并发布以下 Assets：
   - `HYB-Farm-Desktop-X.Y.Z-Setup.exe`
   - `HYB-Farm-Desktop-X.Y.Z-windows-x64-portable.zip`
   - `HYB-Farm-Desktop-X.Y.Z-SHA256.txt`

安装程序脚本位于 `installer/hyb_farm_desktop.iss`。不要手动修改工作流的产物文件名，除非同时更新 README、安装脚本和校验步骤。

## 提交与推送约定

### 普通提交

当用户明确说“提交并推送”或同义表述时，按以下顺序执行，无需逐项询问：

```bash
git status --short
git diff --check
flutter analyze
flutter test
git add -A
git diff --cached --stat
git commit -m "<concise English message>"
git push origin main
```

- `git commit` 前必须先向用户展示暂存变更摘要。
- 提交信息使用简洁英文，例如 `docs: update release guide`、`fix: handle expired login`。
- 推送被远程拒绝时停止并报告；不要使用 `git pull --rebase`、`git push --force`、`git reset --hard` 处理。

### 正式发布

当用户明确说“发布 vX.Y.Z”或“提交并发布 X.Y.Z”时，执行完整发布流程：

1. 读取 `pubspec.yaml`，确认 `version: X.Y.Z`；
2. 确认 `CHANGELOG.md` 有且仅有对应的 `## [X.Y.Z]` 段落；
3. 执行格式检查、静态检查和测试；
4. 暂存后展示变更摘要，创建提交并推送 `main`；
5. 创建带注释标签并推送标签：

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

6. 报告 GitHub Actions 将自动构建并创建/更新该版本 Release。

版本、更新日志或标签任一不一致时必须停止，不允许猜测或自动修正版本号。

## 禁止与确认项

- 未收到明确“提交并推送”或“发布”指令时，不执行 `git commit`、`git push` 或创建 tag。
- 不执行 `git push --force`、`git rebase`、`git reset --hard`。
- 不删除文件或目录；不修改 `.env`、密钥、证书、token、GitHub Secrets 或现有 CI/CD 凭据。
- 不手动上传 `dist/` 下的构建产物；它们应由 GitHub Actions 生成，且已被 `.gitignore` 忽略。
- 不提交 `.env`、`.pfx`、`.p12`、`.pem`、`.key` 等本地秘密和签名材料。

## 常用验证命令

```bash
flutter analyze
flutter test
flutter build windows --release
```

构建 Windows Release 前需关闭正在运行的 `hyb_farm_desktop.exe`，避免 `WebView2Loader.dll` 被锁定。
