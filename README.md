# Magpie for 飞牛 fnOS

[![build-fpk](https://github.com/SMTM-PH/magpie-fnos/actions/workflows/build-fpk.yml/badge.svg)](https://github.com/SMTM-PH/magpie-fnos/actions/workflows/build-fpk.yml)

把 [yetone/magpie](https://github.com/yetone/magpie)（上游 v0.1.2121）适配为飞牛 fnOS 的 FPK 应用：在 NAS 上以无界面服务运行 Web 管理页和 AI 网关，供局域网内的 Claude Code、Codex、Gemini CLI 等客户端统一使用模型。当前打包版本 `0.1.2121`，包含访问密钥最低 6 位、应用内检查更新指向本仓库 Release 的适配。

仓库：https://github.com/SMTM-PH/magpie-fnos

## 从 Release 下载

在 [Releases](https://github.com/SMTM-PH/magpie-fnos/releases) 下载对应架构的 `.fpk`：

- `magpie_<version>_x86.fpk`：x86_64
- `magpie_<version>_arm.fpk`：ARM64
- `SHA256SUMS.txt`：校验文件

推送 `v*` tag 时 GitHub Actions 会自动构建双架构 FPK 并创建 Release。

## 安装包

| 文件 | 适用设备 |
| --- | --- |
| `dist/magpie_0.1.2121_x86.fpk` | x86_64 飞牛设备 |
| `dist/magpie_0.1.2121_arm.fpk` | ARM64 / aarch64 飞牛设备 |
| `dist/SHA256SUMS.txt` | 校验文件 |

```bash
cd dist && sha256sum -c SHA256SUMS.txt
```

## 功能与端口

- **3430/tcp**：Magpie Web 管理页（飞牛桌面入口，iframe）。
- **3425/tcp**：AI 网关，兼容 OpenAI Chat/Responses、Anthropic Messages 和 Gemini。
- 以专用用户 `magpie_fnos` 运行，不使用 root。
- 数据、密钥和日志保存在应用数据目录，升级/重装不丢失。
- 安装时关闭 magpie 自动更新；应用内「检查」只检查 magpie-fnos 的 Release，并提示到下载页获取新 FPK，不替换自身二进制。

## 安装

1. 飞牛「应用中心」→「手动安装」，选择对应架构的 `.fpk`。
2. 安装向导中设置 **管理页访问密钥**：
   - 至少 6 位，仅支持英文字母和数字；建议 12 位以上；
   - 打开 Magpie 时需要输入一次，浏览器会记住 400 天；
   - 旧版本已设置的密钥（可含 `- . _ ~`）升级后继续有效。
3. 安装完成后打开 Magpie 桌面图标，输入上一步的密钥。
4. 在「供应商」页添加模型服务商。

> 通过 SSH 用 `appcenter-cli install-fpk` 安装时不会出现向导，程序会自动生成随机密钥。查看密钥：
>
> ```bash
> sudo cat /vol*/@appdata/magpie/web.key
> ```

## 忘记 / 重置访问密钥

```bash
# 停止应用（应用中心停止，或）
sudo /var/apps/magpie/cmd/main stop

# 查看现有密钥
sudo cat /vol*/@appdata/magpie/web.key

# 重置：写入一个符合规则的新密钥（字母+数字，至少 6 位），或删除后让程序重新生成
sudo sh -c "printf '%s\n' 'YourNewKey123456' > /vol*/@appdata/magpie/web.key"
sudo chmod 600 /vol*/@appdata/magpie/web.key

# 启动
sudo /var/apps/magpie/cmd/main start
```

## 让局域网内的 Agent 使用

先打开 Magpie 的「网关」页，创建一个**网关密钥**（Gateway key）。其他机器访问 3425 时必须携带该密钥，否则返回 401。

```bash
# OpenAI 兼容
export OPENAI_BASE_URL=http://<NAS-IP>:3425/v1
export OPENAI_API_KEY=<网关密钥>

# Anthropic 兼容
export ANTHROPIC_BASE_URL=http://<NAS-IP>:3425
export ANTHROPIC_API_KEY=<网关密钥>

# Gemini 兼容
export GOOGLE_GEMINI_BASE_URL=http://<NAS-IP>:3425
export GEMINI_API_KEY=<网关密钥>
```

```bash
curl http://<NAS-IP>:3425/v1/models \
  -H "Authorization: Bearer <网关密钥>"
```

> 网关显示给客户端的地址默认取 NAS 的默认路由 IPv4 地址。如果 NAS 使用域名、反向代理或多网卡，可在应用数据目录写入 `public-url` 后重启：
>
> ```bash
> echo 'https://magpie.example.com' | sudo tee /vol*/@appdata/magpie/public-url
> ```

## 目录与日志

应用数据目录：`/vol*/@appdata/magpie`（即 `TRIM_PKGVAR`）

| 路径 | 内容 |
| --- | --- |
| `web.key` | 管理页访问密钥（600） |
| `config/magpie/settings.json` | magpie 设置（含已关闭自更新） |
| `config/magpie/` | 供应商、网关密钥等配置 |
| `home/`、`cache/`、`data/`、`state/` | 订阅登录态、插件缓存等 |
| `logs/magpie.log` | 服务日志（5 MB 轮转） |
| `logs/lifecycle.log` | 安装/升级/自更新关闭记录 |
| `run/magpie.pid` | 进程 PID |
| `public-url` | 可选，覆盖网关对外显示的地址 |

## 服务管理

- 应用中心可直接启动、停止、查看状态。
- 命令行：

```bash
sudo /var/apps/magpie/cmd/main start
sudo /var/apps/magpie/cmd/main stop
sudo /var/apps/magpie/cmd/main status   # 0=运行，3=未运行
```

端口声明：`manifest` 的 `service_port` 与桌面入口为 3430；`Magpie.sc` 同时声明 3430/tcp 和 3425/tcp。

## 插件与 HTTPS 证书

- 包内已带 Mozilla CA 根证书（`app/certs/cacert.pem`），启动时合并为 `run/ca-bundle.pem`，并设置 `SSL_CERT_FILE`、`NODE_EXTRA_CA_CERTS`、`CURL_CA_BUNDLE`、`REQUESTS_CA_BUNDLE`。因此即使飞牛系统没有安装 `ca-certificates`，插件市场、Bun 下载和 npm 安装也能正常使用 HTTPS。
- 首次安装插件会自动下载 Bun（约 1.4.2）到应用缓存，需要能访问 GitHub / npm。
- 国内网络可在插件页右上角打开 **国内镜像** 开关（npmmirror / jsDelivr），失败时会回退官方地址。
- 如需信任公司代理或自签 CA，把 PEM 证书放到 `/vol*/@appdata/magpie/ca-cert.pem` 后重启应用；它会与内置根证书合并。
- 插件页的 GitHub 列表偶尔提示读取超时，可直接点“重试”，或用 npm 包名在底部输入框安装。

## 安全建议

- 访问密钥最低 6 位是按需求放宽的；6 位字母+数字对内网使用足够，但如果 3430 端口可能暴露给不可信网络，请改用 12 位以上。
- 管理页入口默认仅管理员可见，并有访问密钥保护；该页面可以查看和修改模型 API Key，请勿泄露密钥。
- 3425 网关从其他机器访问时必须使用网关密钥，但仍建议只开放在局域网内。
- 服务使用 HTTP。不要把 3425/3430 直接暴露到公网；远程使用请走 VPN，或在前置反向代理上配置 TLS。
- 应用内更新检查已改为只提示 FPK 下载页，不会自替换；实际升级请通过应用中心安装新 FPK。

## 重新构建

依赖：Go 1.26+、Git、Docker（用于官方 Linux fnpack 1.2.3）、Bash（Windows 下用 Git Bash）。

```bash
git clone https://github.com/SMTM-PH/magpie-fnos.git
cd magpie-fnos
VERSION=0.1.2121 UPSTREAM_TAG=v0.1.2121 ./build-fpk.sh
```

首次构建会自动克隆上游 `yetone/magpie` 的 `v0.1.2121` tag 到 `magpie/`（已加入 `.gitignore`），并依次应用 `patches/fnos-web-key.patch`（访问密钥最少 6 位）和 `patches/fnos-update.patch`（检查更新指向 FPK Release）。脚本会：

1. 获取上游源码并应用 fnOS 补丁（已存在且已打补丁则跳过）；
2. 用 `CGO_ENABLED=0` 交叉编译 `linux/amd64`、`linux/arm64`（`nogui` 版本，无 GTK/WebView 依赖）；
3. 组装 `manifest`、`config`、`cmd`、`wizard`、`ui`、内置 CA 与图标；
4. 在 Debian 容器中用官方 `fnpack 1.2.3` 打包，保留可执行权限；
5. 重新封包补入 fnpack 会丢弃的包根 `Magpie.sc`；
6. 输出 `dist/*.fpk` 和 `SHA256SUMS.txt`。

升级上游或只更新打包版本：

```bash
# 上游新版本
VERSION=0.1.2122 UPSTREAM_TAG=v0.1.2122 ./build-fpk.sh

# 上游不变，仅重新打包（版本号必须提高，飞牛才会按升级处理）
VERSION=0.1.2122 UPSTREAM_TAG=v0.1.2121 ./build-fpk.sh
```

### 自动构建与发布

GitHub Actions 工作流 [`.github/workflows/build-fpk.yml`](.github/workflows/build-fpk.yml)：

- 推送 `v*` tag：自动构建 x86/ARM FPK，并创建同名 GitHub Release、上传 FPK 与校验文件；上游源码 tag 从 `.github/upstream-tag` 读取。
- 手动 `workflow_dispatch`：填写 `version` 和 `upstream_tag`，只生成 Actions Artifacts。
- 上游升级时，同时更新 `.github/upstream-tag` 为新的上游 tag。

```bash
git tag v0.1.2122
git push origin v0.1.2122
```

## 应用内检查更新

「设置 → 关于 → 检查」现在查询本仓库 Release 里的 `update-feed.json`：

- 有新 FPK：显示版本和更新说明，点「下载」打开 GitHub Release 页面；
- 不会下载或替换 magpie 二进制，也不会改变应用中心里的版本；
- 自动检查仍然关闭，只在你点击「检查」时查询；
- 需要 NAS 能访问 GitHub。不能访问时，可以写入镜像后的 feed 地址并重启：

```bash
APP_DATA=$(ls -d /vol*/@appdata/magpie | head -1)
echo 'https://your-mirror.example/magpie-fnos/update-feed.json' \
  | sudo tee "$APP_DATA/update-feed-url"
sudo /var/apps/magpie/cmd/main stop
sudo /var/apps/magpie/cmd/main start
```

## 更新 NAS 上的应用

从 Release 下载新 FPK，在飞牛应用中心「手动安装」即可升级，应用数据保留。更新检查只负责提示，不会自动安装 FPK。

## 目录结构

```text
magpie/                上游源码
fnos/                  FPK 工程（manifest、cmd、config、wizard、ui）
scripts/docker-fnpack.sh
build-fpk.sh
tools/                 fnpack 1.2.3
dist/                  生成的 FPK
```

## 已验证范围

已在 Debian 12 容器中按飞牛目录布局模拟验证（专用用户、`TRIM_*` 环境、安装/升级/卸载脚本）：

- FPK 由官方 fnpack 1.2.3 构建；包结构、文件权限、图标尺寸、JSON 配置正确。
- 安装向导密钥、无向导随机密钥、密钥保留、重置。
- 启动、重复启动、状态、停止、再次启动；`status` 停止时返回 3。
- 管理页无密钥 401、带密钥 303 并写入 Cookie；真实浏览器登录成功，iframe 内自动登录成功。
- 网关无密钥 401；创建网关密钥后 `/v1/models` 返回 200。
- 6 位密钥 `abc123` 安装、启动、登录成功；5 位密钥和含 `-` 的新密钥在安装阶段被拒绝；旧版含 `- . _ ~` 的密钥升级后仍可登录。
- 应用内检查更新：本地 feed 返回 `9.9.9` 时，接口返回 `state=available`、`stuck=fnos`，未下载二进制；界面显示“Magpie 以飞牛 FPK 安装…”提示，点击打开 Release 页。
- 默认 GitHub feed（`releases/latest/download/update-feed.json?lang=zh`）可访问；v0.1.2121 检查返回 `state=latest`。
- 在**没有 `ca-certificates`** 的 Debian 12 容器中，使用包内 CA 成功安装 `@magpie-community/opencode-zen-free-auth`（自动下载 Bun 1.4.2，发现 8 个模型），插件页显示“已安装 · 1”。
- 插件安装需要能访问 GitHub/npm；本次 0.1.2121 构建容器的 GitHub 下载受限，未复测插件下载（包内 CA 与镜像逻辑未变）。
- 自定义 `ca-cert.pem` 会与内置根证书合并；移除后恢复。
- 卸载默认保留数据；选择删除时仅清理 `/vol*/@appdata/magpie`。
- x86_64 与 aarch64 二进制均为静态链接。

**尚未在真实飞牛设备上安装验证**。飞牛各版本对安装向导、端口转发（`Magpie.sc`）和 iframe 的策略可能不同，请先在测试环境安装并确认；如有差异，以 `logs/lifecycle.log` 和 `logs/magpie.log` 为准。

## 上游与许可

- 上游：https://github.com/yetone/magpie （MIT）
- 本适配包仅做构建与 fnOS 打包适配，未修改上游业务代码。
- 图标来自上游 `internal/gui/icon*.png`。

## 官方参考

- Manifest：https://developer.fnnas.com/docs/core-concepts/manifest/
- 应用框架：https://developer.fnnas.com/docs/core-concepts/framework/
- 应用入口：https://developer.fnnas.com/docs/core-concepts/app-entry/
- fnpack：https://developer.fnnas.com/docs/cli/fnpack/
