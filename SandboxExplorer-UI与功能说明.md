# SandboxExplorer（沙盒管家）UI 与功能说明

> 版本：1.0（CFBundleShortVersionString 1.0 / Build 1）
> 应用显示名：沙盒管家（`Config/Info.plist`，可由构建参数覆盖）
> Bundle ID：`dev.local.SandboxExplorer`（默认值，可由构建参数覆盖）
> 最低部署：iOS 16.0（仅用于编译；容器访问运行时要求 iOS 26+）
> 技术栈：Objective-C + UIKit（无 Storyboard、纯代码布局）
> 许可证：GPL-3.0-or-later

---

## 1. 项目定位

一个免越狱的 iOS 文件管理工具，解决两件事：

1. **访问本 App 自身沙盒**：任何签名方式下都可读写，无需特殊权限。
2. **访问其它 App 的数据容器**：通过 App Group 容器查询 + `sandbox_extension_consume`
   （`worse_query` 技术）签发沙盒扩展，再用 `fsgetpath` 按 APFS object id 反查容器路径，
   从而在没有系统文件 App 权限的情况下浏览、读取、写入其它 App 的沙盒目录。

整体产品形态参考 WQManager，技术链路参考 worse_query，代码为独立重写实现。

---

## 2. 信息架构与导航

根控制器为 `UITabBarController`，4 个 Tab，每个 Tab 内嵌独立 `UINavigationController`。
根页面使用 InsetGrouped 表格 + 大标题；文件浏览页为 Plain 表格并关闭大标题。

```
SandboxExplorer
├── 沙盒         WQHomeViewController        insetGrouped · 大标题「沙盒管家」
├── 容器         WQContainersViewController  insetGrouped · 大标题「数据容器」
├── 文件         WQBrowserViewController     plain · 根目录 Documents「我的文件」
└── 工具         WQToolsViewController       insetGrouped · 大标题「扩展 / 日志」
        │
        └── 二级页面（push）
            ├── 文件浏览器（任意目录，可无限层级递归下钻）
            ├── 文本 / HEX 查看器
            ├── 文本编辑器（可写回）
            ├── 属性 / xattr 查看器
            ├── 诊断日志查看器
            └── 技术与上游声明
```

Tab 图标（SF Symbols）：

| Tab | 标题 | 图标 |
|---|---|---|
| 0 | 沙盒 | `folder` |
| 1 | 容器 | `square.grid.2x2` |
| 2 | 文件 | `doc.text` |
| 3 | 工具 | `wrench.and.screwdriver` |

---

## 3. 页面 UI 明细

### 3.1 沙盒页（首页）

**结构**：`UITableViewStyleInsetGrouped`，标题「沙盒管家」，右上角系统刷新按钮。
`viewWillAppear` 时重建数据并刷新，因此扩展数量等状态始终为最新。

**表头**（脚注字号、次要文字色、多行）：

> 当前 App 的沙盒目录无需任何扩展即可读写。
> 访问其它 App 的数据容器依赖 worse_query 沙盒扩展技术（需要 iOS 26+ 与可用的 App Group）。
> 运行系统：iOS x.y

**分组 1｜当前 App 沙盒目录**（6 行，两行文本单元格）

| 行标题 | 副标题内容 |
|---|---|
| Home（沙盒根） | `NSHomeDirectory()` |
| Documents | 文档目录绝对路径 |
| Library | 库目录绝对路径 |
| Library/Caches | 缓存目录绝对路径 |
| tmp | 临时目录绝对路径 |
| App Group 容器 | App Group 容器路径；不可用时显示「（未配置 / 描述文件不含该 group）」 |

- 点击任意行 → 底部 ActionSheet（iPhone）/ Popover（iPad）：
  「打开此目录」「复制路径」「查看属性」「取消」。
  对应 push 文件浏览器、写剪贴板、打开只读属性页。
- App Group 不可用时点击 → 弹窗提示需在描述文件中启用 `com.apple.security.application-groups`。
- 分组脚注：点击任一条目可打开目录、复制路径或查看文件属性。

**分组 2｜运行状态**（6 行）

| 行标题 | 值 |
|---|---|
| Bundle ID | 当前应用标识 |
| 签名的 App Groups | 从签名 entitlement 中读出的 group 列表，无则「无」 |
| 生效的 App Group | 第一个容器 URL 可解析的 group，无则「不可用」 |
| 容器访问状态 | 「就绪」/「未就绪 — 容器访问将失败」 |
| 系统支持 | 「支持（iOS 26 / 27）」/「不支持（需要 iOS 26+）」 |
| 已持有的扩展 | 「n 个」 |

点击任意行 → 将该值复制到剪贴板并弹窗「已复制」。
脚注说明 App Group 必须由描述文件包含，否则容器 URL 为 nil。

**分组 3｜快捷操作**（4 行，带 Disclosure 箭头）

| 行 | 副标题 | 行为 |
|---|---|---|
| 在 Documents 写入示例文件 | 验证沙盒内读写权限 | 写 `sandbox-demo.txt`（含时间、Bundle ID、路径），不存在则创建 |
| 打开我的 Documents | 浏览 / 新建 / 编辑 / 删除文件 | push 文件浏览器 |
| 扫描其它 App 容器 | worse_query + fsgetpath 枚举 | 直接切换到「容器」Tab |
| 清空诊断日志 | 清除本次运行的日志缓冲 | 清空内存日志并提示 |

---

### 3.2 容器页

**结构**：InsetGrouped，标题「数据容器」，右上角按钮文字在「快速扫描」与「停止」间切换。

**表头**：说明 `fsgetpath` 按对象 id 反查路径不受沙盒限制；完整扫描可能数分钟，快速扫描只覆盖前 30 万个 id。

**分组 1｜扫描**（3 行）

| 行 | 副标题 |
|---|---|
| 快速扫描（前 30 万 id） | 通常几十秒内完成 |
| 完整扫描（自动探测上限） | 覆盖设备上所有已安装 App，可能数分钟 |
| 选择父目录 / 手动输入路径 | 也可直接打开任意绝对路径 |

- 分组脚注实时显示「当前父目录：…」。
- 选择父目录会弹出 ActionSheet，候选：
  - `/private/var/mobile/Containers/Data/Application`
  - `/private/var/mobile/Containers/Data/PluginKitPlugin`
  - `/private/var/mobile/Containers/Data/InternalDaemon`
  - `/private/var/mobile/Containers/Shared/AppGroup`
  - iOS 27+ 追加 `/var/containers/Data/System`、`/var/containers/Shared/SystemGroup`
  - 「手动输入绝对路径并打开」→ 输入框弹窗，规范化后打开。

**分组 2｜进度**（仅扫描期间出现，1 行）

主标题：`扫描中… 12.3%`；副标题：`已检查 X / Y 个 id，命中 N 个目录`。
完成或取消后该分组自动隐藏。

**分组 3｜容器（n）**

- 主标题：从 `com.apple.containermanager.identifier` xattr 解析出的 Bundle ID；
  未解析时先显示 UUID 目录名，后台低优先级解析完成后原地刷新该行。
- 副标题：容器绝对路径（最多 2 行）。
- 点击 → 后台签发该路径的沙盒扩展并验证可打开，成功则 push 文件浏览器；
  失败弹窗显示具体错误码文本（如「App Group 不可用」「containermanagerd 拒绝了查询」等）。
- 扫描结果为空时提示可尝试完整扫描、更换父目录，或当前系统版本已封堵。
- 扫描可中途取消，取消后保留上一次结果。

**前置校验**：系统低于 iOS 26 → 弹窗拒绝；App Group 未就绪 → 弹窗提示，但仍允许尝试。
扫描默认在全局队列执行，进度回调切主线程，只刷新进度分组，避免整表重载。

---

### 3.3 文件页（文件浏览器）

**结构**：`UITableViewStylePlain`，关闭大标题，支持下拉刷新。
根实例由「文件」Tab 创建，目录为 `Documents`，标题「我的文件」；
从沙盒页/容器页进入时标题为对应目录名。

**表头**：浅灰背景（`secondarySystemBackground`）+ 11pt 等宽字体两行文本，
第一行显示当前目录绝对路径，第二行「（点击复制路径）」；点击表头复制路径并弹窗。
长路径自动换行，最多 2 行。

**导航按钮**：右上角 `+`，点击弹出创建菜单：

| 菜单项 | 说明 |
|---|---|
| 新建文本文件 | 输入文件名（禁止含 `/`）→ 进入编辑器，保存时创建文件 |
| 新建文件夹 | 输入名称 → `mkdir 0755` |
| 从「文件」App 导入 | `UIDocumentPicker` 导入模式，支持安全作用域资源 |
| 释放全部沙盒扩展 | 释放进程内所有 token 并刷新 |
| 取消 | — |

**列表行**

- 图标：目录 `folder.fill`（系统橙色），符号链接 `link`，普通文件 `doc`（次要文字色）。
- 主标题：文件名（最多 2 行）。
- 副标题：`类型或大小 · 权限 · 修改时间 · inode`，例如
  `1.24 KB · -rw-r--r-- · 2026-11-16 13:40:00 · ino 123456`。
- 目录行：Disclosure 箭头，点击进入下一级目录（可无限下钻，返回逐级回退）。
- 文件行：详情按钮（ⓘ），点击弹出文件操作菜单。
- 底部脚注：正常时显示「N 个项目 · 已持有 M 个沙盒扩展」；
  加载失败显示具体 errno 文本；空目录显示「目录为空，或当前尚未获得该目录的访问权限」。

**文件操作菜单**（ActionSheet / Popover，标题为文件名，消息为完整路径）

| 操作 | 行为 |
|---|---|
| 文本查看 | 读取前 256 KB，UTF-8 解码，二进制内容加提示 |
| 十六进制查看 | 读取前 64 KB，显示前 16 KB 的 HEX + ASCII |
| 编辑并写入 | 读取前 2 MB，UTF-8 校验；保存原地覆盖，保持 inode |
| 查看属性 / xattr | 只读页展示路径、类型、大小、inode、设备、权限、链接数、UID/GID、修改/创建时间、容器 Bundle ID、扩展属性列表 |
| 另存到「我的导出」 | 复制到 `Documents/Exports`，提示可在「文件」App 中找到 |
| 分享文件 | 先复制到 Exports，再弹 `UIActivityViewController` |
| 重命名 | 输入新名称（禁止含 `/` 和空名），同目录 `rename` |
| 删除 | 二次确认后删除；目录仅允许删除空目录（非递归） |
| 取消 | — |

所有文件操作遇到 `EPERM/EACCES` 会自动申请父目录（必要时目标自身）的沙盒扩展并重试一次，
上层 UI 无需感知。

**编辑器 / 查看器**（`WQTextViewController`）

- 全屏 `UITextView`，13pt 等宽字体，12pt 内边距，禁用自动大写与自动纠错，
  键盘交互式收起。
- 查看模式：右上角「复制全部」。
- 编辑模式：左上角「取消」、右上角「保存」；监听键盘 frame 变化动态调整
  `contentInset`，避免文字被键盘遮挡。
- 保存成功弹窗后自动返回上一级并刷新目录列表。
- 新建文件时编辑器初始内容为空，保存时走 `O_CREAT|O_EXCL` 创建流程。

---

### 3.4 工具页

**结构**：InsetGrouped，标题「扩展 / 日志」，`viewWillAppear` 时刷新已持有扩展列表。

**分组 1｜手动获取沙盒扩展**（6 行）

| 行 | 说明 |
|---|---|
| 目标路径（点击修改） | 默认 `/private/var/mobile/Containers/Shared/AppGroup/`，弹窗输入并规范化 |
| 句柄状态 | `已持有 handle = n` 或「未持有手动扩展」+ 错误码解释 |
| 消费扩展（自动 flags） | iOS 26 走 alt flags、iOS 27+ 走标准 flags，并自动回退 |
| 消费扩展（alt flags） | `0x0000000800000000` |
| 消费扩展（标准 flags） | `0x0000008000000000` |
| 释放手动扩展 | 调用 `sandbox_extension_release` |

- 成功后弹出 handle 值与目标目录条目数，作为「扩展确实生效」的证据。
- 已持有手动扩展时再次消费会提示先释放。
- 脚注说明：iOS 26 的 AppGroup 路径通常需要 alternative flags，自动模式会依次尝试两种并记住可用的一组。

**分组 2｜当前持有的扩展**（n + 1 行）

- 每个已持有扩展：主标题为路径最后一段，副标题为完整路径；点击复制路径。
- 末行「释放全部扩展」显示总数，点击全部释放。
- 脚注：单进程扩展数量有限，缓存上限 192 个，超出按 LRU 释放。

**分组 3｜诊断日志**（4 行）

| 行 | 行为 |
|---|---|
| 查看完整日志 | 只读页展示内存日志 |
| 复制日志 | 写入剪贴板 |
| 导出 / 分享日志 | 写入 `Documents/Logs/sandboxexplorer-yyyyMMdd-HHmmss.log` 后分享 |
| 清空日志 | 清空缓冲并插入一条「日志已清空」 |

副标题实时显示当前日志缓冲字符数。

**分组 4｜关于 / 许可**（3 行）

- 技术与上游声明：只读页，含版本、worse_query / WQManager / KAMUI / WQFiles 归属、GPL 说明与风险提示。
- `github.com/forcequitOS/worse_query`、`github.com/hseons/WQManager`：点击跳浏览器。
- 脚注：分发衍生作品须保留声明并继续使用 GPL-3.0-or-later。

---

## 4. UI 设计规范

| 维度 | 实现 |
|---|---|
| 布局方式 | 纯代码 Auto Layout，无 Storyboard / XIB；列表用 `UITableViewController` |
| 列表样式 | 根页面 InsetGrouped；文件浏览 Plain |
| 大标题 | 全部 Tab 根导航开启；文件浏览器显式关闭 |
| 字体 | 正文用系统动态字体（`preferredFontForTextStyle:`）；路径与编辑器用等宽字体（表头 11pt、编辑器 13pt） |
| 颜色 | 全部使用语义色，自动适配浅色/深色模式：`systemBackground`、`secondarySystemBackground`、`secondaryLabelColor`、`systemBlue`（强调色）；目录图标用 `systemOrangeColor` |
| 图标 | SF Symbols（`folder.fill`、`doc`、`link`、`square.grid.2x2`、`doc.text`、`wrench.and.screwdriver`） |
| 行高 | 自适应高度，估算行高 52 / 56 / 58 / 62 |
| 弹窗 | 统一 `UIAlertController`：错误/结果用 Alert，多操作用 ActionSheet；iPad 自动绑定 `popoverPresentationController` 的 sourceView / sourceRect，避免崩溃 |
| 提示工具 | 统一封装 `WQPresentAlert`、`WQCopyToPasteboard`、`WQInputAlert`、`WQAccentColor`（`Sources/AppDelegate.m`） |
| 刷新 | 首页 `viewWillAppear` 重建；容器页手动按钮/进度刷新；文件页下拉刷新 + 返回自动刷新 |
| 线程 | 文件 I/O、扩展签发、容器扫描全部后台队列执行，UI 更新回到主线程 |

---

## 5. 功能清单（按模块）

### 5.1 自身沙盒信息

- 展示 Home / Documents / Library / Caches / tmp / App Group 容器绝对路径。
- 一键复制、直接进入、查看属性。
- 展示 Bundle ID、签名的 App Groups、生效 group、容器访问就绪状态、系统支持、已持有扩展数。
- 写入示例文件验证读写链路。

### 5.2 容器枚举

- 两种扫描强度：快速（前 30 万 id）/ 完整（探针文件取最新 inode + 10 万安全余量）。
- 可切换父目录、手动输入任意绝对路径。
- 实时进度（已检查 / 总数 / 命中数），可随时停止，停止后保留旧结果。
- 并行工作线程数取 `min(8, max(2, CPU 核数))`，按 32768 个 id 分块抢锁，
  只保留直接子目录（路径中前缀后不含额外 `/`）。
- 通过 xattr 解析容器对应 Bundle ID，异步补全并局部刷新。
- 点击容器自动申请扩展后进入文件浏览。

### 5.3 文件管理

- 目录浏览：名称、类型、大小、权限、修改时间、inode、符号链接标记；目录优先、名称不区分大小写排序。
- 读取：文本预览（256 KB）、HEX（64 KB）、属性 + xattr。
- 写入：原地 `O_WRONLY|O_TRUNC` 覆盖，保持 inode / 属主 / xattr；新建文件 `O_CREAT|O_EXCL`。
- 目录/文件创建、重命名、删除（目录非递归）、导出、系统分享、从文件 App 导入、释放全部扩展。
- 所有操作在 `EPERM/EACCES` 时自动补扩展并重试。

### 5.4 沙盒扩展控制台

- 手动指定路径，按自动 / alt / 标准三种策略消费扩展。
- 显示 handle、错误码含义、目标目录可列条目数。
- 列出当前持有的全部扩展路径，支持单个复制与全部释放。
- 采用 192 上限的 LRU 缓存，越界自动释放最久未用 token；记录偏好的 flags 组合。

### 5.5 诊断与合规

- 带毫秒时间戳的内存日志，超过 512 KB 自动裁剪到约 384 KB 并保留整行。
- 日志查看 / 复制 / 导出分享 / 清空。
- App 内 GPL 与上游声明页，页脚提示容器读写会直接改动目标 App 数据。

---

## 6. 代码分层

```
UI 层
  SceneDelegate.m            TabBar + 4 个导航栈
  HomeViewController.m       沙盒信息与快捷操作
  ContainersViewController.m 扫描控制、进度、容器列表
  BrowserViewController.m    目录浏览、文件操作菜单、导入导出
  EditorViewController.m     文本查看 / 编辑（WQTextViewController）
  ToolsViewController.m      扩展控制台、日志、关于

文件系统层
  WQFileOps.m    POSIX 读写/创建/删除/重命名/复制/属性/格式化，自动补扩展重试
  WQPathLeak.m   fsgetpath 枚举、inode 探针、容器 xattr、默认父目录

桥接层
  WQBridge.m     App Group 探测、Caches 交换、container_query_*、token 消费、
                 LRU 缓存、错误码

基础层
  WQLog.m        日志缓冲、环境路径、系统版本、路径规范化
  WQKit.h        文件系统与桥接接口
  WQUI.h         UI 类与共享弹窗辅助函数声明
```

**沙盒扩展核心流程**

1. 从签名 entitlement 取第一个可用 App Group；
2. 将 App Group 容器的 `Library/Caches` 重命名为备份，再建立指向目标路径的符号链接；
3. `flock` 串行化查询，调用 `container_query_create → set_class(7) → set_group_identifiers
   → operation_set_part(3) → operation_set_flags`，取单结果并 `container_copy_sandbox_token`；
4. `sandbox_extension_consume` 得到 handle，随后恢复 Caches；
5. 校验目标可打开（EPERM 消失），记录可用的 flags 组合；
6. 崩溃后下次启动自动恢复原 Caches，且不递归删除任何内容。

---

## 7. 权限、兼容性与已知限制

| 项目 | 说明 |
|---|---|
| 自身沙盒 | 完全可用，不依赖 App Group 或特殊签名 |
| 其它 App 容器 | 需 iOS 26.0–26.7.2 / 27.2 + 描述文件包含 App Group；更高版本可能被封堵 |
| App Group | 需付费 Apple Developer 账号在 App ID 中启用；免费 7 天签名不支持 |
| 安装方式 | adhoc 可直接用于 TrollStore / 越狱；普通设备需 Sideloadly 等重签；signed 产物可直接安装 |
| 删除 | 目录只允许删空目录，避免误删整棵容器树 |
| 编辑 | 只接受 UTF-8 文本，单文件上限 2 MB，超出拒绝保存以防截断 |
| 预览 | 文本 256 KB、HEX 显示 16 KB、属性 xattr 名称缓冲 4 KB |
| 扫描耗时 | 完整扫描取决于设备 inode 量级，可能数分钟，可随时取消 |
| 符号链接 | 读写打开均带 `O_NOFOLLOW`，避免跟随链接误写 |
| 日志 | 仅内存保存，不自动落盘；退出即丢失 |

---

## 8. 构建与交付配置

- 构建环境：GitHub Actions `macos-26` runner（Xcode 26.6 / iOS 26 SDK，可选 Xcode 27），
  60 分钟超时，Windows 本地无需 Xcode。
- 工作流 `.github/workflows/build-ipa.yml`：静态校验 → 选择 Xcode → 改写三个标识 → 构建打包 → 上传产物。
- 三种签名模式：
  - `adhoc`（默认）：xcodebuild 不签名后本地 ad-hoc 重签并把 App Group 写进 entitlements；
  - `unsigned`：仅产出未签名 IPA，需自行重签；
  - `signed`：CI 导入 p12 + 描述文件做正式签名，产物可直接安装。
- 可配置项：`bundle_id`、`app_group`、`display_name`、`sign_mode`、`xcode_path`；
  本地对应 `Config/Project.xcconfig`、`Config/Info.plist`、`Config/SandboxExplorer.entitlements`。
- 构建后校验：`codesign -d --entitlements :-` 反读签名，确认 App Group 字符串存在，否则构建失败。
- 产物：IPA、entitlements plist、实际嵌入的 entitlements、`build-report.txt`、`xcodebuild.log`。

---

## 9. 快速使用路径

1. 安装后打开「沙盒」：确认「系统支持」与「容器访问状态」为就绪（否则仅自身沙盒功能可用）。
2. 在「沙盒 → 在 Documents 写入示例文件」验证读写。
3. 进入「容器 → 快速扫描」，等待进度完成后点击目标 App 容器。
4. 在文件浏览器中查看、编辑、导出文件；必要时用「释放全部沙盒扩展」回收内核配额。
5. 出现异常时到「工具 → 诊断日志」查看或导出日志。
