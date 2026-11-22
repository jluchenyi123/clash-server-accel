# Clash Server Accelerator

[English](README.md) | **简体中文**

在无桌面的 Linux 服务器上管理 Clash / mihomo 订阅，并让任意命令走代理。

两个命令覆盖绝大多数场景：

- **`clash`** —— 订阅管理器：添加、更新、切换订阅，测试节点，管理服务，
  一键开启全局 TUN 模式。
- **`accel`** —— 命令加速器：只让当前这一条命令走代理，不污染整个 shell。

不需要桌面环境，专为 SSH 管理的服务器、家庭服务器和远程开发机设计。

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20systemd-blue)
![Python](https://img.shields.io/badge/python-3.8%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> 分组名、节点名和订阅内容均来自你的服务商，不属于本仓库的一部分。

## 功能特性

- 粘贴订阅链接即可完成下载、校验、激活和重启服务
- 多订阅配置管理，带一个轻量元数据存储
- 节点延迟测试，支持交互式选择分组和节点
- 两种运行模式：
  - **HTTP 代理** —— 当前 shell 用 `proxy_on`，或单条命令用 `accel`
  - **TUN 模式** —— 全局代理，自动接管 DNS，失败自动回滚
- 替换线上配置前先用 `mihomo -t` 校验
- TUN 模式下局域网和 Tailscale 流量保持直连
- 可选 Web 面板（Clash Dashboard / yacd / Metacubexd）
- 支持从 Clash Verge 导入订阅
- 无 GUI、无 Electron、无需登录桌面

## 工作原理

```text
 订阅链接
        │   clash add / clash update
        │   （curl、伪装客户端 UA、失败后走本地代理重试）
        ▼
 ~/.config/mihomo/profiles/<slug>.yaml      原始 Clash YAML，权限 600
        │
        │   build_runtime()：覆盖端口 / DNS / 规则，
        │   并用 mihomo -t 校验
        ▼
 config.yaml（HTTP 模式）   config-tun.yaml（TUN 模式）
        │
        ▼
 mihomo（systemd）
        ├── 127.0.0.1:7899   HTTP + SOCKS5 混合代理
        └── 127.0.0.1:9090   控制器 / REST API / 可选面板
```

生成出来的 `config.yaml` 和 `config-tun.yaml` 是**派生产物**，不要手工修改。
每次执行 `clash use`、`clash update` 或 `clash tun on` 都会根据当前订阅重新生成。

## 环境要求

- Linux + systemd（Ubuntu / Debian 及类似发行版）
- [mihomo](https://github.com/MetaCubeX/mihomo)（Clash.Meta 内核）
- Python 3.8+ 及 PyYAML
- `curl`
- TUN 模式额外需要：root 权限、`/dev/net/tun`、systemd-resolved、NetworkManager

### 安装 mihomo

从 [MetaCubeX/mihomo Releases](https://github.com/MetaCubeX/mihomo/releases)
下载对应架构的二进制文件：

```bash
sudo install -m 755 mihomo /usr/local/bin/mihomo
mihomo -v
```

> 如果 mihomo 装在别处，请修改 `mihomo.service` 里的 `ExecStart`，
> 或为 `clash` 设置 `MIHOMO_BIN=/path/to/mihomo`。

### 安装 PyYAML

```bash
sudo apt install python3-yaml
```

## 安装

```bash
git clone https://github.com/jluchenyi123/clash-server-accel.git
cd clash-server-accel
./install.sh
```

`install.sh` 是**用户级**安装脚本（不要用 sudo 运行），会安装：

- `clash`、`accel` 到 `~/.local/bin`
- 供桌面启动器使用的 `clash-menu`、`clash-status`
- systemd 用户服务 `~/.config/systemd/user/mihomo.service`
- TUN 安装脚本到 `~/.config/mihomo/install-tun.sh`
- 桌面启动器（如果存在 XDG 桌面目录）
- `~/.bashrc` 中的 `proxy_on` / `proxy_off` / `proxy_status` 函数

如果 `~/.local/bin` 不在 `PATH` 中，重新登录或执行：

```bash
source ~/.bashrc
```

### GeoIP 数据

首次生成配置前，需要把 `Country.mmdb`、`geoip.dat`、`geosite.dat`
放到 `~/.config/mihomo/`。`ASN.mmdb` 为可选文件。

如果本机装了 Clash Verge，`clash` 会自动从它的数据目录复制；否则从
[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat/releases)
下载。

## 快速开始

```bash
clash
```

在菜单中选择 `1`，粘贴订阅链接。也可以直接执行：

```bash
clash add "https://your-subscription-url"
```

订阅激活后，在当前 shell 中启用代理：

```bash
proxy_on          # 开启代理环境变量
proxy_status      # 查看状态
proxy_off         # 关闭
```

或者只让一条命令走代理，不影响 shell：

```bash
accel git clone https://github.com/owner/repo.git
accel npx skills add owner/repo --list
accel pip install -r requirements.txt
accel status
```

## 命令参考

### clash

| 命令 | 说明 |
|---|---|
| `clash` | 交互式菜单 |
| `clash add "<url>"` | 添加订阅，生成配置并激活 |
| `clash add "<url>" --name NAME` | 使用自定义配置名添加 |
| `clash add "<url>" --no-start` | 只生成配置，不重启服务 |
| `clash list` | 列出所有订阅（`*` 表示当前激活） |
| `clash use <name>` | 切换到指定订阅 |
| `clash update [name]` | 更新订阅（默认更新当前激活的） |
| `clash nodes` | 查看节点和当前选择 |
| `clash nodes --test` | 测试延迟并交互式选择节点 |
| `clash status` | 查看服务、节点和连通性状态 |
| `clash start` / `stop` / `restart` | 管理服务 |
| `clash logs [-f]` | 查看或跟踪日志 |
| `clash remove <name>` | 删除订阅（不能删除当前激活的） |
| `clash import-verge [--use NAME]` | 从 Clash Verge 导入订阅 |
| `clash tun on` / `off` / `status` | 全局 TUN 模式 |

支持 Clash YAML 订阅，包括 Base64 编码的 YAML。直连下载失败时会自动改走
本地代理重试。不支持 ss/vmess/trojan 分享链接列表，请先转换为 Clash YAML 订阅。

### accel

| 命令 | 说明 |
|---|---|
| `accel <命令> [参数...]` | 带代理环境变量运行命令 |
| `accel -- <命令>` | 同上（命令名本身是 `status` 等时使用） |
| `accel status` | 查看状态、当前节点、出口 IP 和位置 |
| `accel test` | 连通性测试 |
| `accel restart` | 重启 mihomo |
| `accel help` | 查看帮助 |

命令运行期间，`accel` 会设置：

```text
http_proxy / https_proxy / all_proxy
HTTP_PROXY / HTTPS_PROXY / ALL_PROXY
npm_config_proxy / npm_config_https_proxy
no_proxy（排除局域网、mDNS 和 Tailscale）
```

`accel` 的退出码与被包装的命令一致。如果服务未运行，会先尝试启动服务。

### Shell 辅助函数

`install.sh` 会向 `~/.bashrc` 追加以下函数（如果尚不存在）：

- `proxy_on` —— 在当前 shell 中开启代理环境变量
- `proxy_off` —— 移除代理环境变量
- `proxy_status` —— 查看服务状态并测试连通性

## 端口

默认值：

- `127.0.0.1:7899` —— HTTP + SOCKS5 混合代理
- `127.0.0.1:9090` —— 控制器 / REST API

修改方法：

- 修改 `clash` 中的 `MIXED_PORT` / `CTRL_PORT`
- 设置 `ACCEL_PORT` / `ACCEL_CTRL_PORT` / `ACCEL_HOST`，或直接修改 `accel`
- 如果使用 `proxy_on`，同步修改 `~/.bashrc` 中对应的端口

## TUN 模式

```bash
clash tun on      # 需要 sudo
clash tun off     # 恢复 HTTP 代理模式
```

`clash tun on` 会根据当前订阅生成 `config-tun.yaml`，然后运行
`install-tun.sh`。安装脚本会：

- 创建 TUN 接口并接管系统流量
- 将系统 DNS 指向 mihomo（fake-IP 防污染）
- 保持局域网和 Tailscale 地址直连
- 启动服务前校验配置
- 安装失败或 5 分钟内未确认时自动回滚（防止 SSH 断线后失联）

TUN 模式依赖 NetworkManager 配置 DNS，会写入
`/etc/systemd/system/mihomo-tun.service` 并修改 DNS 设置。
回滚脚本位于 `~/.config/mihomo/rollback-tun.sh`。

## 文件布局

仓库文件：

```text
clash                          # 订阅管理器（Python）
accel                          # 命令加速器（Bash）
start-menu.sh
check-status.sh
clash-accelerator.desktop.in   # 桌面启动器模板
mihomo.service                 # systemd 用户服务
install.sh                     # 用户级安装脚本
install-tun.sh                 # TUN 模式安装脚本
README.md
README.zh-CN.md
LICENSE
.gitignore
```

运行时文件（不提交到仓库）：

```text
~/.config/mihomo/
├── config.yaml              # 当前 HTTP 配置（生成）
├── config-tun.yaml          # 当前 TUN 配置（生成）
├── subscriptions.json       # 订阅元数据（含订阅链接，权限 600）
├── profiles/                # 原始订阅 YAML（权限 600）
├── ui/                      # 可选 Web 面板
├── Country.mmdb
├── geoip.dat
└── geosite.dat
```

## Web 面板

控制器只监听本地地址。从你的电脑建立 SSH 隧道：

```bash
ssh -L 9090:127.0.0.1:9090 user@server
```

然后打开 <http://127.0.0.1:9090/ui/>。

如果本机没有 Clash Verge 的面板资源，可以把
[yacd](https://github.com/haishanh/yacd) 或
[Metacubexd](https://github.com/MetaCubeX/metacubexd) 下载到
`~/.config/mihomo/ui/`。

## 卸载

```bash
clash tun off                       # 仅在安装过 TUN 模式时需要
systemctl --user disable --now mihomo
rm -f ~/.local/bin/{clash,accel,clash-menu,clash-status}
rm -f ~/.config/systemd/user/mihomo.service
```

然后删除 `~/.bashrc` 中 `# >>> clash-server-accel >>>` 与
`# <<< clash-server-accel <<<` 之间的内容。订阅和配置仍保留在
`~/.config/mihomo/`；如需彻底删除，移除该目录即可。

## 常见问题

### `clash: command not found`

```bash
source ~/.bashrc
```

### `gnutls_handshake() failed` / GitHub TLS 错误

直连受到干扰，使用加速器：

```bash
accel git clone https://github.com/owner/repo.git
```

### 订阅下载失败

- 确认链接是 **Clash YAML** 订阅，而不是 ss/vmess 分享链接列表
- 直连失败时工具会改走本地代理重试，因此本地代理需已运行
- 用 `clash logs` 查看日志

### `loc=CN` 或出口 IP 仍是本地运营商

流量没有走代理：

```bash
proxy_on          # 当前 shell
clash status      # 查看服务状态
clash tun on      # 需要全局代理时
```

### TUN 模式导致断网

```bash
clash tun off
# 或者命令行不可用时：
sudo bash ~/.config/mihomo/rollback-tun.sh
```

### 节点很慢

```bash
clash nodes --test
clash nodes
```

### 手动改的 `config.yaml` 被覆盖了

这是预期行为：`config.yaml` 和 `config-tun.yaml` 是生成文件。
请修改订阅或 `clash` 中的生成逻辑，然后执行 `clash use` 重新生成。

## 安全说明

- `subscriptions.json` 和 `profiles/` 包含订阅链接和节点凭据，请保持权限 `600`
- 控制器只监听 `127.0.0.1`
- `allow-lan` 默认为 `false`
- TUN 模式会写入系统服务并修改 DNS，运行 `install-tun.sh` 前请先审阅
- 不要把运行时配置提交到 Git（`.gitignore` 已覆盖）
- 推送到 GitHub 前，确认任何文件中都不含个人订阅链接

## 许可证

MIT —— 见 [LICENSE](LICENSE)。

## 免责声明

本项目用于个人网络管理和学习。请遵守当地法律法规及服务商的使用条款。
