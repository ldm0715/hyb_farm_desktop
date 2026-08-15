# HYB Farm Desktop

<div align="center">
  <strong>黑与白农场助手 · Windows 桌面端</strong><br>
  <sub>基于 Flutter 构建的后台托盘农场管理工具</sub>
</div>
<br>

HYB Farm Desktop 是一个面向黑与白农场的 Windows 桌面客户端。它从 [HYB_farm_helper](https://github.com/ldm0715/HYB_farm_helper) 油猴脚本二次开发而来，将浏览器内的农场管理与自动化操作迁移为独立桌面应用。

应用通过内置登录页获取当前账号的登录状态，可在后台驻留系统托盘，集中提供农场、仓库、好友农场和自动化设置等能力。

> 本项目为非官方工具，与游戏或服务的官方运营方无隶属关系。

## 功能

| 模块 | 功能 |
| --- | --- |
| 作物收益排行 | 根据实时回收价格、成熟周期和产量计算作物的单次收益与单位时间收益。 |
| 我的农场 | 查看地块、作物成熟状态、空地和待处理的缺水 / 杂草 / 虫害异常。 |
| 收菜与补种 | 支持一键收获；可在自动收菜后执行自动补种。 |
| 自动务农 | 定时检查农场状态并处理可务农的异常地块。 |
| 我的仓库 | 查看库存、回收价格及收益排行；支持手动种植和回收卖出。 |
| 好友农场 | 查看好友农场状态，访问好友农场并执行偷菜操作。 |
| 托盘控制 | 关闭窗口后继续在系统托盘运行，可从托盘菜单显示窗口和控制自动化。 |
| 账户与安全 | 内置 WebView 登录；登录 Cookie 保存于本机安全存储，并在 HTTP 请求与 WebView 间同步。 |
| 桌面体验 | 支持浅色 / 暗色主题、记住窗口位置，以及鼠标移出后自动隐藏到托盘。 |

## 安装方式

推荐从 [GitHub Releases](https://github.com/ldm0715/hyb_farm_desktop/releases) 下载发布包；无需安装 Flutter 或其他开发环境。

### 方式一：克隆仓库后运行 `dist` 中的安装包

```bash
git clone https://github.com/ldm0715/hyb_farm_desktop.git
cd hyb_farm_desktop
```

进入项目根目录的 `dist` 文件夹，双击运行与系统架构对应的 `HYB-Farm-Desktop-<版本号>-Setup.exe`，并按安装向导完成安装。

> `dist` 是发布产物目录。若克隆的分支未包含该目录，请使用下方的 GitHub Releases 方式下载，或按“本地运行”章节自行构建。

### 方式二：从 GitHub Releases 下载

打开 [GitHub Releases](https://github.com/ldm0715/hyb_farm_desktop/releases)，在最新版本的 **Assets** 中按需下载：

- `HYB-Farm-Desktop-<版本号>-Setup.exe`：安装版，下载后直接运行安装程序。
- `HYB-Farm-Desktop-<版本号>-windows-x64-portable.zip`：便携版，解压后运行其中的 `hyb_farm_desktop.exe`。

首次启动后，请在内置登录页完成黑与白农场账号登录。
## 界面展示

亮色主题：

<img src="./README.assets/image-20260815225427672.png" alt="image-20260815225427672" style="zoom:67%;" />

暗色主题：

<img src="./README.assets/image-20260815225542022.png" alt="image-20260815225542022" style="zoom:67%;" />

## 技术栈

| 部分 | 技术 |
| --- | --- |
| 应用框架 | Flutter / Dart |
| 目标平台 | Flutter Windows |
| 状态管理 | Provider |
| 网络请求 | Dio |
| 登录与 Cookie | `flutter_inappwebview`、`flutter_secure_storage` |
| 窗口与托盘 | `window_manager`、`system_tray`、`screen_retriever` |
| 本地设置与通知 | `shared_preferences`、`flutter_local_notifications` |

## 环境要求

- Windows 10 / 11
- Flutter SDK（当前项目约束：`^3.10.7`）
- 已配置 Flutter Windows desktop 开发环境

可通过以下命令确认 Windows 桌面端已启用：

```bash
flutter config --enable-windows-desktop
flutter devices
```

## 本地运行

```bash
# 获取依赖
flutter pub get

# 调试运行
flutter run -d windows
```

首次启动后，请在内置登录页完成黑与白农场账号登录。登录成功后，应用会加载农场、仓库和好友农场数据。

## 常用命令

```bash
# 静态检查
flutter analyze

# 运行全部测试
flutter test

# 运行单个测试文件
flutter test test/farm_state_test.dart

# 构建 Windows Release
flutter build windows
```

Release 产物默认位于：

```text
build/windows/x64/runner/Release/
```

> 构建前必须关闭正在运行的 `hyb_farm_desktop.exe`。否则 `WebView2Loader.dll` 可能被占用，导致 Windows 构建报错。

## 使用说明

1. 启动应用，在内置登录页完成账号登录。
2. 在**农场**页面查看地块状态、手动收菜或处理异常。
3. 在**仓库**页面查看库存与收益排行，进行种植或回收卖出。
4. 在**好友**页面查看好友农场状态并按需偷菜。
5. 在**设置**页面调整主题、自动收菜、自动补种、自动务农和窗口行为。
6. 关闭窗口后，应用会驻留系统托盘；从托盘菜单可重新打开窗口或调整自动化开关。

## 项目结构

```text
lib/
├── api/          # 农场接口封装与数据模型
├── auth/         # 登录、Cookie 持久化、WebView Cookie 同步
├── core/         # 常量、格式化、连接状态、请求分类、操作协调
├── services/     # 收菜调度、自动务农、补种、回收、通知与日志
├── state/        # 农场、好友、设置和连接状态
├── theme/        # 亮/暗主题与设计令牌
├── tray/         # Windows 系统托盘
└── ui/           # 登录、农场、仓库、好友、设置及通用组件

test/             # 单元测试、Widget 测试与接口夹具
windows/          # Flutter Windows 平台工程
assets/           # 应用图标与本地字体
```

## 接口与登录状态

应用依赖黑与白农场的相关接口，并使用登录账号当前的 Cookie 进行认证。

- 登录失效、网络异常、请求限流或人机验证可能导致数据加载和自动化操作不可用。
- 遇到人机验证时，请在内置登录窗口按页面提示完成验证后重试。
- 自动收菜、补种、务农、回收和偷菜都会直接作用于账号数据；启用前请确认账号和配置无误。

## 上游项目

本项目的功能与接口逻辑参考油猴脚本项目：

- [ldm0715/HYB_farm_helper](https://github.com/ldm0715/HYB_farm_helper)

上游项目运行于浏览器 Tampermonkey 环境；本仓库为 Flutter Windows 桌面端实现。两者功能目标相近，但应用形态、交互方式和代码结构不同。

## 开发约定

```bash
# 修改后至少执行
flutter analyze
flutter test
```

涉及 Windows Release 构建时，请先确认应用进程已经退出。
