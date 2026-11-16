# SandboxExplorer · 沙盒管家

一个**独立重写**的 iOS 应用：用 `forcequitOS/worse_query` 的沙盒扩展技术，配合
`hseons/WQManager` 的产品形态，实现「获取当前 App 沙盒目录 + 访问/读取/写入其它
App 数据容器」。整个工程由 **GitHub Actions 在 macOS runner 上构建出 IPA**，
Windows 上无需 Xcode 即可得到成品。

> 本工程不含上游任何源码文件，核心链路按原理重新实现，许可证为
> **GPL-3.0-or-later**（见 `LICENSE` 与 `THIRD_PARTY_NOTICES.md`）。

---

## 1. 功能

| 页面 | 能力 |
|---|---|
| **沙盒** | 显示本 App 的 `Home / Documents / Library / Caches / tmp / App Group 容器` 绝对路径，可复制、直接打开、查看属性；显示 Bundle ID、签名的 App Groups、生效 group、系统版本、已持有扩展数；一键写入示例文件验证读写 |
| **容器** | 用 `fsgetpath` 枚举 `/private/var/mobile/Containers/Data/Application` 等父目录下的 UUID 容器（快速 / 完整扫描、进度与取消、可换父目录、可手动输入绝对路径）；读取 `com.apple.containermanager.identifier` xattr 显示 Bundle ID；点击后自动申请 sandbox extension 并进入文件浏览器 |
| **文件** | 任意目录浏览（目录/文件/链接、大小、权限、mtime、inode）；UTF-8 文本查看、十六进制查看、**编辑并原地写入（保持 inode）**、属性与 xattr 查看、新建文件/文件夹、重命名、删除、另存到 `Documents/Exports`、分享、从「文件」App 导入、释放全部扩展 |
| **工具** | 手动输入路径 → 消费/释放 sandbox extension（自动 / alt / 标准 flags），实时查看 handle 与错误码；查看已持有的扩展列表；诊断日志的查看/复制/导出/清空；GPL 与上游声明 |

**自身沙盒读写不需要任何特殊权限，装上就能用。** 其它 App 数据容器的读写才依赖
worse_query 技术（iOS 26+ 与可用 App Group）。

---

## 2. 技术原理

```
1) App Group 探测
   SecTaskCopyValueForEntitlement("com.apple.security.application-groups")
   → containerURLForSecurityApplicationGroupIdentifier: 取第一个可用 group

2) 交换点（WQBridge.m，相对上游 PoC 的改进）
   Library/Caches ──rename──> .sandboxexplorer-caches-original
   Library/Caches <──symlink── 目标路径
   flock(.sandboxexplorer-query.lock) 保证查询串行
   （崩溃后下次启动会自动恢复原 Caches，绝不递归删除原有内容）

3) 签发扩展
   dlopen("/usr/lib/system/libsystem_containermanager.dylib")
   container_query_create → set_class(7) → set_group_identifiers(group)
   → operation_set_part(3) → operation_set_flags(0x0000000800000000 / 0x0000008000000000)
   → container_query_get_single_result → container_copy_sandbox_token
   → sandbox_extension_consume → 得到 handle
   恢复 Caches；验证 open(target) 不再返回 EPERM；成功的一组 flags 会被记住

4) 容器枚举（WQPathLeak.m）
   在本 App tmp 建探针文件取当前最大 APFS object id（+ 10 万安全余量）
   并行 fsgetpath(buffer, fsid, id) 逐 id 反查路径，前缀匹配出直接子目录
   getxattr(path, "com.apple.containermanager.identifier") → Bundle ID

5) 文件操作（WQFileOps.m）
   普通 POSIX/NSFileManager 调用；遇到 EPERM/EACCES 自动 WQGrant(父目录) 后重试
   handle 用 192 上限的 LRU 缓存，避免触到内核单进程扩展数量限制
```

与上游 PoC 的差异：`rename` 保留 Caches 原内容 + 崩溃恢复、`flock` 串行、
双 flags 自动回退、token 有效性校验、LRU 缓存、非递归删除、纯 ObjC/UIKit
传统 `pbxproj`（objectVersion 56，Xcode 26.6 / 27 均可构建，不依赖 Xcode 27
的 JSON 工程格式）。

---

## 3. 用 GitHub 构建 IPA（Windows 推荐）

**为什么必须走 GitHub**：Windows 没有 Xcode，无法编译 iOS 应用。GitHub 提供 macOS
云主机构建机（免费），把工程 push 上去后 `.github/workflows/build-ipa.yml` 会自动
编译、打包 IPA 并作为 artifact 上传。你只需要解决「怎么把代码推上去」这一步的身份认证。

工程根目录：`C:\Users\Administrator\Desktop\trae测试\构建ipa\SandboxExplorer\`

### 3.1 三种认证方式，任选一种

#### 方式 1（最省事，强烈推荐）：GitHub CLI 浏览器登录，完全不用手动造 token

```powershell
winget install --id GitHub.cli          # 装完后重开一个 PowerShell 窗口
gh auth login --scopes "repo,workflow"
```

交互过程：选 `GitHub.com` → `HTTPS` → `Login with a web browser` →
终端显示一次性码（如 `ABCD-1234`）→ 复制 → 自动打开的浏览器里粘贴并点授权 → 回到终端回车。

若后续 push 提示缺 workflow 权限，补一次：

```powershell
gh auth refresh -h github.com -s workflow
```

脚本会自动执行 `gh auth token` 取凭据，**不需要把任何 token 贴到命令行或对话里**。

#### 方式 2：手动创建 classic PAT（`ghp_` 开头的字符串）

1. 浏览器登录 https://github.com ，右上角头像 → **Settings**。
2. 左侧栏拉到最底 → **Developer settings**。
3. **Personal access tokens** → **Tokens (classic)**。
4. **Generate new token** → **Generate new token (classic)**
   （也可直达 https://github.com/settings/tokens/new ，可能要求再输一次密码/2FA）。
5. **Note** 填 `SandboxExplorer-Build`；**Expiration** 选 `30 days`（够用，别选 No expiration）。
6. 勾选**且只勾**这两项：
   - ✅ `repo`（第一组整项，Full control of private repositories）
   - ✅ `workflow`（单独一行，允许创建/更新 `.github/workflows/*.yml`）
7. 点 **Generate token** → **立刻复制 `ghp_` 开头的整串字符**（页面刷新后不再显示）。

> `workflow` 不能漏：本工程的构建脚本本身就是一个 workflow 文件。缺它时 push 会报
> `refusing to allow a Personal Access Token to create or update workflow .github/workflows/build-ipa.yml without workflow scope`。
>
> fine-grained PAT 也可以，但创建仓库需要额外给 `Administration: read/write`，
> 且容易出现权限缺失，新手建议直接用 classic PAT。

#### 方式 3：完全不用 token，网页建仓 + Git 凭据管理器（浏览器登录）

本机 PortableGit 自带 `git-credential-manager.exe`，`git push` 会弹出 GitHub 登录窗。

1. 打开 https://github.com/new ，仓库名 `SandboxExplorer`，选 **Public**，
   **不要**勾选 Add README / .gitignore / license（保持全空）。
2. 本地执行（把 `<you>` 换成你的用户名）：

```powershell
cd "C:\Users\Administrator\Desktop\trae测试\构建ipa\SandboxExplorer"
git remote add origin https://github.com/<you>/SandboxExplorer.git
git push -u origin main
```

3. 弹窗里选浏览器登录并授权。
4. 打开 `https://github.com/<you>/SandboxExplorer/actions` 看构建，
   跑完后进那次 run → 页面底部 **Artifacts** → 下载 `SandboxExplorer-IPA-*`，
   解压出里面的 `.ipa`。

缺点：不能自动下载产物、不能从命令行改 Bundle ID 等参数。

### 3.2 建议把仓库设为 Public

本工程是 GPL-3.0-or-later，源码本来就要公开。公开仓库的 GitHub Actions **免费且不受
macOS 分钟倍率限制**；私有仓库的免费账号每月只有约 `$12` 计算额度，
macOS runner 按约 `$0.062/分钟` 扣（约 190 分钟），用尽后需要绑定支付方式。
一键脚本加 `-Public` 即建公开仓库（不加默认私有）。

### 3.3 一键构建命令

按上面选好认证后，在 **PowerShell** 执行：

```powershell
cd "C:\Users\Administrator\Desktop\trae测试\构建ipa\SandboxExplorer"
python Scripts\verify_project.py        # 本地静态校验，无需 Xcode

# 方式 1（gh CLI 已登录）—— 什么都不用设：
.\Scripts\push_to_github.ps1 -Repo SandboxExplorer -Public

# 方式 2（用了 PAT）—— 先设环境变量再跑：
$env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxxxxxxxxxx"
.\Scripts\push_to_github.ps1 -Repo SandboxExplorer -Public
```

`$env:GITHUB_TOKEN` 只在当前 PowerShell 窗口有效，关掉窗口即失效，不会写进文件。
Python 版跨平台等价命令：

```bash
python Scripts/github_build.py --repo SandboxExplorer --public --sign-mode adhoc
```

脚本会自动：建仓 → 提交 → push 到 `main` → 等 Actions 跑完 → 下载并解压 IPA 到：

```
C:\Users\Administrator\Desktop\trae测试\构建ipa\SandboxExplorer\dist\
    SandboxExplorer-adhoc.ipa            <- App Group 已写进二进制签名
    SandboxExplorer-unsigned.ipa         <- 干净未签名版，备用
    SandboxExplorer.entitlements.plist
    SandboxExplorer.embedded-entitlements.plist   <- codesign 实际写入的内容
    build-report.txt
    xcodebuild.log
    github-artifact.zip
```

构建一般 5–15 分钟。想看实时日志：仓库 **Actions → Build SandboxExplorer IPA**。
想改配置再构建：**Actions → Build SandboxExplorer IPA → Run workflow**，
页面可直接填 `bundle_id / app_group / display_name / sign_mode / xcode_path`。
`-NoWait` 只推送不等待，`-TimeoutMinutes 60` 可延长等待。

### 3.4 常见报错

| 现象 | 原因 / 处理 |
|---|---|
| `Bad credentials` / `401` | token 复制不全或已过期，重新生成；`gh` 用户执行 `gh auth login` |
| `refusing to allow ... without workflow scope` | 缺 `workflow` scope：classic PAT 重勾；或 `gh auth refresh -h github.com -s workflow` |
| `Resource not accessible by integration` / `403` | fine-grained PAT 少给了 Administration / Actions 权限，改用 classic PAT |
| `Repository creation failed (422)` | 仓库名已存在，脚本会直接复用；换个 `-Repo` 名字也可 |
| 推送成功但没有 Actions 运行 | 私有仓库需 **Settings → Actions → General** 允许 workflow；或 `workflow` scope 缺失导致 yml 未上传 |
| `No space` / macOS 排队久 | 公开仓库优先；macOS runner 高峰期可能排队，等几分钟即可 |

### 3.5 本地 macOS 构建（需要 Xcode 26+）

```bash
bash Scripts/configure.sh \
  --bundle-id com.yourname.sandbox \
  --app-group group.com.yourname.sandbox \
  --display-name "沙盒管家"
bash Scripts/build_ipa.sh
```

或直接用 Xcode 打开 `SandboxExplorer.xcodeproj` → 选择真机 → Run。

---

## 4. 可配置项

| 位置 | 参数 | 默认值 | 说明 |
|---|---|---|---|
| `workflow_dispatch` | `bundle_id` | `dev.local.SandboxExplorer` | 必须与描述文件的 App ID 匹配 |
| `workflow_dispatch` | `app_group` | `group.dev.local.SandboxExplorer` | **必须在描述文件中启用** |
| `workflow_dispatch` | `display_name` | `沙盒管家` | 主屏幕名称 |
| `workflow_dispatch` | `sign_mode` | `adhoc` | `adhoc` / `unsigned` / `signed` |
| `workflow_dispatch` | `xcode_path` | 空 | 指定 `/Applications/Xcode_27.2.app` 之类的路径 |
| `Config/Project.xcconfig` | 三个标识 | 同上 | `configure.sh` 会统一改写它、entitlements 与 Info.plist |

### 4.1 能不能「构建时直接写入」，不用重签时手动合并？

**能，而且默认就是这么做的。** 先说清机制：entitlement 不是 `.app` 里的一个文件，
而是 **Mach-O 代码签名的一部分**。没有签名的二进制没有承载它的位置，所以
把 plist 塞进 `.app` 资源目录也不会被 iOS 认可 —— 必须 `codesign`。
因此工程提供三档，按「要不要证书」区分：

| `sign_mode` | 构建时做了什么 | 产物 | 装到手机还要做什么 |
|---|---|---|---|
| **`adhoc`（默认）** | `xcodebuild` 不签名 → 复制一份 `.app` → `codesign --force --sign - --entitlements Config/SandboxExplorer.entitlements`。**零证书、零 Secrets**，App Group 直接写进二进制 | `SandboxExplorer-adhoc.ipa` **+** `SandboxExplorer-unsigned.ipa` | 普通非越狱 iOS：仍需 Sideloadly / AltStore 重签一次，但**不用再手动合并 XML**（工具会继承已存在的 entitlements）；TrollStore / 越狱设备可直接装 ad-hoc 版 |
| **`signed`** | 用你自己的 p12 + 描述文件在 CI 里做真正的 Apple Development 签名 | `SandboxExplorer-signed.ipa` | **什么都不用做，直接安装**。这是真正的「一步到位」 |
| `unsigned` | 完全不签名 | `SandboxExplorer-unsigned.ipa` | 重签并把 `dist/SandboxExplorer.entitlements.plist` 喂给工具 |

`build_ipa.sh` 会用 `codesign -d --entitlements :-` **反向读回**签名内容，
确认 `app_group` 字符串真的在里面，读不到就直接让构建失败；
`dist/SandboxExplorer.embedded-entitlements.plist` 就是读回的原始内容。

> ⚠️ **写入 ≠ 生效**：App Group 必须由 Apple 在描述文件里授权。ad-hoc 可以写进任意
> entitlement，但普通 iOS 上 AMFI 仍会以描述文件为准；没有授权时
> `containerURLForSecurityApplicationGroupIdentifier:` 返回 nil、容器访问返回 `-1`。
> 自身沙盒的浏览 / 读取 / 写入不依赖它，任何情况下都可用。

### 4.2 一键直接产出可安装 IPA（`sign_mode=signed`）

前提：付费 Apple Developer 账号，且 App ID 已启用 **App Groups** 并包含
`group.dev.local.SandboxExplorer`（或你自定义的 group）。

1. 准备两个文件：从钥匙串导出的 `ios_dev.p12`（含私钥），以及在
   https://developer.apple.com/account/resources/profiles 下载的开发/Ad Hoc
   `.mobileprovision`（设备 UDID 要在里面）。
2. 一条命令生成并写入 GitHub Secrets：

```powershell
cd "C:\Users\Administrator\Desktop\trae测试\构建ipa\SandboxExplorer"
.\Scripts\setup_signing_secrets.ps1 `
    -P12Path "C:\certs\ios_dev.p12" -P12Password "证书密码" `
    -ProvisionPath "C:\certs\SandboxExplorer.mobileprovision" `
    -TeamId "ABCDE12345" -Repo "hoko20/SandboxExplorer" -SetSecrets
```

脚本会先**检查描述文件里是否真的包含该 App Group**（不含就直接报错，避免产出
「看起来签好了但功能全废」的 IPA），校验 Team ID，把 5 个 Secret 写入仓库：

| Secret | 内容 |
|---|---|
| `IOS_P12_BASE64` | `.p12` 的 base64 |
| `IOS_P12_PASSWORD` | 证书密码 |
| `IOS_PROVISION_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `IOS_TEAM_ID` | Team ID |
| `KEYCHAIN_PASSWORD` | 脚本自动生成的随机串 |

不加 `-SetSecrets` 时只把 base64 写到 `Scripts/.secrets/*.txt`（已被 `.gitignore`
排除），供你在 **Settings → Secrets and variables → Actions** 手动粘贴。

3. 到 **Actions → Build SandboxExplorer IPA → Run workflow**，选 `sign_mode = signed`
   并确认 `bundle_id` / `app_group` 与描述文件完全一致。CI 会建临时钥匙串、
   导入证书、安装描述文件、`CODE_SIGN_STYLE=Manual` 构建，产出
   `SandboxExplorer-signed.ipa`，**无需重签**。

> 免费 Apple ID 的 7 天个人签名**无法在 GitHub Actions 里自动完成**：runner 是每次
> 全新的机器，Xcode 账号登录要走交互式 2FA，且免费账号不允许 App Groups。
> 免费账号只能走本地 Sideloadly / AltStore，或直接装 `adhoc` 版 + TrollStore。

---

## 5. 签名与侧载（决定功能能否用，务必读）

- 默认产物是 **`adhoc`**：entitlements 已在构建时写进二进制，重签工具会继承，
  **不需要手动合并 XML**。若仍想显式指定，Sideloadly 的
  *Advanced options → Entitlements* 里选 `dist/SandboxExplorer.entitlements.plist`
  即可；该文件内容为：

  ```xml
  <key>com.apple.security.application-groups</key>
  <array><string>group.dev.local.SandboxExplorer</string></array>
  ```

- `unsigned` IPA **不能直接安装**，需要用 Sideloadly / AltStore / iOS App Signer /
  爱思助手等用自己的证书重签，并把上面的 plist 喂给工具。
- `signed` IPA 由 CI 用真实证书签好，直接安装，无需任何重签。

- **App Group 需要付费 Apple Developer 账号**。免费账号的 7 天签名不支持
  App Groups，`containerURLForSecurityApplicationGroupIdentifier:` 会返回 nil，
  `WQQueryRaw` 直接返回 `-1`，容器访问全部失效（但本 App 自身沙盒的浏览、
  读取、写入仍然完全可用）。
- 描述文件（Development 或 Ad Hoc）的 App ID 必须勾选 **App Groups** capability
  并包含与你填写的 `app_group` **完全一致**的 group id；否则 token 签不出来。
- 重签工具如果会自己生成 entitlements，记得把上面的 group 合并进去，并同步
  修改 `WQAppGroupIdentifier`（Info.plist）与 `APP_GROUP_ID`（xcconfig），
  三者保持一致。

---

## 6. 运行要求与限制

- 容器访问技术适用范围（按上游 README）：**iOS 26.0 – 26.7.2 / 27.2**。
  更高版本可能被 Apple 封堵。
- `IPHONEOS_DEPLOYMENT_TARGET = 16.0` 只是为了让工程能在各种 iOS 26 SDK 上
  顺利编译；运行时容器功能仍要求 iOS 26+。
- 必须在**真机**上验证：模拟器沙盒基本不生效，不能作为技术有效性证据。
- 删除操作**不递归**（`rmdir` 只允许删空目录），避免误删整个容器子树。
- 写入采用 `open(O_WRONLY|O_TRUNC)` 原地覆盖，保持 inode / 属主 / xattr 不变。
- 容器枚举是 id 暴力反查，完整扫描在 Id 数百万的设备上可能要数分钟，
  支持随时取消。
- 大文件编辑只载入前 2 MB 并会拒绝保存以防截断；大文件请用「另存到我的导出」。

---

## 7. 目录结构

```
SandboxExplorer/
├── .github/workflows/build-ipa.yml        GitHub Actions：选 Xcode → 配置 → 构建 → 打 IPA → 上传
├── Config/
│   ├── Project.xcconfig                  Bundle ID / App Group / 显示名 / 部署目标
│   ├── Info.plist                        SceneDelegate、文件共享、WQAppGroupIdentifier
│   ├── SandboxExplorer.entitlements      App Group entitlement（configure.sh 生成）
│   └── SandboxExplorer.entitlements.template
├── Scripts/
│   ├── configure.sh                      统一改写三个标识
│   ├── build_ipa.sh                      xcodebuild + (ad-hoc/正式)签名 + 打包 + 校验 + 报告
│   ├── setup_signing_secrets.ps1         把 p12/描述文件一键写成 GitHub Secrets
│   ├── verify_project.py                 Windows 本机可跑的工程静态校验
│   ├── github_build.py                   建仓/推送/轮询/下载 IPA 一键脚本
│   └── push_to_github.ps1                PowerShell 薄封装
├── SandboxExplorer.xcodeproj/            传统 pbxproj + 共享 scheme
├── Sources/
│   ├── WQKit.h / WQUI.h                 接口声明
│   ├── WQLog.m / WQBridge.m             日志、环境路径、worse_query 桥接
│   ├── WQPathLeak.m                     fsgetpath 容器枚举 + xattr
│   ├── WQFileOps.m                      读写/创建/删除/复制/属性/格式化
│   ├── main.m / AppDelegate.m / SceneDelegate.m
│   └── Home/Containers/Browser/Editor/Tools ViewController.m
├── LICENSE                              GPL-3.0 全文
└── THIRD_PARTY_NOTICES.md                上游声明
```

---

## 8. 许可

GPL-3.0-or-later。分发 IPA 时必须同时提供完整对应源码、保留 `LICENSE`、
`THIRD_PARTY_NOTICES.md` 以及 App 内「工具 → 技术与上游声明」页面。

本项目与 Apple 无关；主路径利用的是 stock iOS 上的 App Group 容器查询行为，
`adhoc` 产物也可在 TrollStore / 越狱环境直接安装。对其它 App 数据的写入会
直接改动目标 App 的内容，操作前请自行确认目标路径。
