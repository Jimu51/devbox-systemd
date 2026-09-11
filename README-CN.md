# systemdbox

一个开箱即用的多语言开发容器镜像（systemd + Python + Node + JDK + code-server）。

| 组件 | 版本 | 备注 |
|---|---|---|
| 基础镜像 | `debian:12-slim` | |
| Init 系统 | `systemd`（PID 1） | 容器以真正的 init 运行 |
| Python | **3.12.14** | 源码编译，预装 `venv` / `pipx` / `poetry` / `pip-tools` |
| Node.js | **22.23.2**（Jod LTS） | `yarn`、`pnpm`、`typescript`、`tsx`、`corepack` |
| JDK | **Temurin 21.0.12.1+1** | `JAVA_HOME=/opt/jdk-21`，仅 JDK |
| Maven | **3.9.9** | 阿里云镜像，`MAVEN_HOME=/opt/maven` |
| code-server | **4.135.0** | 官方 `.deb`，由 `systemd` 管理 |

所有二进制通过 SHA-256 校验，不匹配则构建失败。

---

## 快速开始

### docker compose（推荐）

```bash
# 不设置密码：容器自动生成 16 位随机密码并打印到日志
docker compose up -d
docker logs devbox | grep -A 5 'code-server 密码已就绪'

# 推荐：显式设置明文密码
PASSWORD='你的密码' docker compose up -d

# 也可使用已 hash 的密码（跳过启动时的 hash 计算）
HASHED_PASSWORD='argon2id 哈希值' docker compose up -d
```

打开浏览器访问 <http://localhost:3443>，使用上面日志中打印的密码登录。

### docker run

```bash
docker run -d \
  --name devbox \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 3443:8443 \
  -e PASSWORD='你的密码' \
  devbox:latest
```

### 进入容器

```bash
docker exec -it devbox bash
docker exec -it devbox systemctl list-units
```

---

## 为什么需要 `--privileged` + `/sys/fs/cgroup`？

`systemd` 作为 PID 1 需要写 cgroup 层级（管理子进程、记录 journal）。

| 主机 cgroup 版本 | 推荐参数 |
|---|---|
| cgroup v2（默认） | `--privileged` + `--cgroupns=host` + 挂载 `/sys/fs/cgroup:rw` |
| cgroup v1 | 仅需挂载 `/sys/fs/cgroup:rw` |

`docker-compose.yml` 已通过 `privileged: true` + `cgroup: host` + bind mount 配置好。

---

## 网络模式（两种二选一）

### 模式 A：bridge（默认）

```yaml
ports:
  - "${CODE_SERVER_PORT:-3443}:8443"
```

宿主机 `3443` → 容器 `8443`。可通过 `CODE_SERVER_PORT` 环境变量覆盖宿主机侧端口。

### 模式 B：host（更直接，性能更好）

取消 `docker-compose.yml` 中 `network_mode: host` 的注释，并注释掉 `ports:` 整段：

```yaml
network_mode: host
# ports: ...
```

此时 code-server 直接在宿主机 `8443` 监听（需确保该端口空闲）。

---

## 密码配置

`PASSWORD` 与 `HASHED_PASSWORD` 二选一，都不设置则自动生成。

| 环境变量 | 优先级 | 含义 |
|---|---|---|
| `HASHED_PASSWORD` | 高 | argon2 哈希值，跳过容器内的 hash 计算 |
| `PASSWORD` | 中 | 明文密码，code-server 启动时自动 hash |
| （都不设置） | 低 | 容器自动生成 16 位随机密码，**会打印到 `docker logs`** |

启动时 entrypoint 会在日志中打印：

```
================================================================
  ★ code-server 密码已就绪
================================================================
  来源：auto-generated
  ⚠ 密码为自动生成，仅适合临时使用
  ★ 密码：Awv0y5Ch9d7jJGos
  ★ 访问：http://<host>:3443
================================================================
```

> ⚠️ 自动生成的密码仅适合快速试用；生产或长期使用请通过 `PASSWORD` 显式传入。

---

## 国内镜像源（默认）

构建时已固化国内镜像源，构建速度与运行时依赖下载都快：

| 工具 | 镜像 | 配置文件 |
|---|---|---|
| `apt` | `https://mirrors.tuna.tsinghua.edu.cn/debian` | `/etc/apt/sources.list.d/debian.sources`（deb822 格式） |
| `npm` | `https://registry.npmmirror.com/` | `/etc/npmrc`、`/home/coder/.npmrc` |
| `mvn` | `https://maven.aliyun.com/repository/public` | `/opt/maven/conf/settings.xml`、`/home/coder/.m2/settings.xml` |

> Maven 二进制从华为云镜像下载（国内 CDN），SHA-256 已硬编码校验。

如果需要切换回官方源，编辑相应配置文件即可。

---

## Workspace 默认目录与 trust 设置

- code-server 默认打开 `/home/coder/workspace`（由 systemd 单元 ExecStart 末尾参数控制）
- **关闭了 workspace trust**（命令行 `--disable-workspace-trust` + settings.json），"Add Folder to Workspace" 时不再弹"信任此文件夹"对话框
- HOME 设为 `/home/coder`，使 "Open Folder" 对话框默认从 `/home/coder` 开始浏览

settings.json 关键配置：
```json
{
    "security.workspace.trust.enabled": false,
    "extensions.supportUntrustedWorkspaces": {"*": true},
    "files.dialog.defaultPath": "/home/coder/workspace"
}
```

---

## 关于运行用户

本镜像**故意以 root 运行 code-server**（见 `systemd/code-server.service`）。理由：

- devbox 是个人本地开发容器，能登录 = 已是 root（coder 用户有 `NOPASSWD:ALL`）
- 因此直接以 root 运行简化权限模型，避免每次都要 `sudo`
- 端口 3443 应只暴露给 localhost（不暴露公网）

如果你的使用场景不同，请修改 `systemd/code-server.service` 的 `User=` 与 `Group=` 字段。

---

## 关于 journal 中 "Hostname set to <debain>"

启动时 `journalctl -b` 会看到一次：
```
systemd[1]: Hostname set to <debain>.
```

**这是 Debian 12 base image 的已知问题**（详见 [Debian Bug #853731](https://bugs.debian.org/853731)），
image 里 `/etc/hostname` 写了上游构建时的容器 ID 前缀或 `debain`（typo），systemd 启动早期读到后就用这个值调用 `sethostname()`。

**实际并不影响使用**：
- `/proc/sys/kernel/hostname`、`/etc/hostname`、`uname -n`、`hostnamectl` 都正确显示 `devbox`
- 1 秒后 systemd-hostnamed 启动后会被 D-Bus 调用修正（看到 `Hostname set to <devbox> (static)`）

我们已在 entrypoint.sh 中显式重新同步内核与 `/etc/hostname` 为 `devbox`，但 Docker daemon 在容器创建那一刻也会改写一次，因此这条历史日志始终存在。如果你想消除，可在容器内执行：
```bash
hostnamectl set-hostname devbox
```

---

## 文件位置

| 路径 | 作用 |
|---|---|
| `/etc/code-server/config.yaml` | code-server 配置（监听地址、鉴权模式） |
| `/etc/code-server/code-server.env` | 由 entrypoint 生成，systemd 通过 `EnvironmentFile=` 读取 |
| `/etc/systemd/system/code-server.service` | systemd 单元 |
| `/etc/systemd/system/code-server.service.d/override.conf` | 单元覆盖（重启策略等） |
| `/root/.local/share/code-server` | 用户数据、设置、扩展 |
| `./home/`（宿主机） | 持久化目录（coder 用户数据） |
| `./workspace/`（宿主机） | 工作区挂载点 |

---

## 重启策略

- systemd：`Restart=on-failure`，`RestartSec=5`
- docker：`restart: unless-stopped`（compose）/ `--restart unless-stopped`（cli）

两者并存，进程崩溃时由 systemd 拉起，容器停止时由 docker 拉起。

---

## 镜像验证

```bash
CONTAINER=devbox ./scripts/verify.sh
```

依次检查：组件版本、`systemctl is-system-running`、code-server 状态、`/healthz` 端点。

---

## 构建

```bash
# 默认：精简模式（移除 code-server 内置 Copilot、Mermaid 等扩展）
docker build -t devbox:latest .

# 完整模式（保留所有内置扩展，~880 MB）
docker build -t devbox:full --build-arg SLIM_CODE_SERVER=false .

# 自定义组件版本
docker build -t devbox:py3.12.14-node22.23.2-jdk21.0.12.1-cs4.135.0 \
  --build-arg PYTHON_VERSION=3.12.14 \
  --build-arg NODE_VERSION=22.23.2 \
  --build-arg JDK_VERSION=21.0.12.1 \
  --build-arg JDK_BUILD=1 \
  --build-arg CODE_SERVER_VERSION=4.135.0 .
```

### 固定版本（构建参数）

```
PYTHON_VERSION=3.12.14    SHA256: 5c8462af5790baf43a321a1559dbe0db06d1be4300fb85fb53c40060668e548a
NODE_VERSION=22.23.2       SHA256: d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
JDK_VERSION=21.0.12.1      SHA256: ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
JDK_BUILD=1
CODE_SERVER_VERSION=4.135.0 SHA256: f87d0d49c6c0a59d41214c9510f506e4123991f2d27b41f6d56f3f5c96458d3e
```

### Slim 模式（默认）

`SLIM_CODE_SERVER=true` 默认开启，会移除以下内置扩展：

| 扩展 | 节省 |
|---|---|
| GitHub Copilot | ~360 MB |
| Mermaid Markdown Features | ~63 MB |

如需这些功能，可在 code-server 内手动安装。

最终镜像大小：**~475 MB**（精简模式）/ **~880 MB**（完整模式）。

> 之前版本 466 MB，新增 Maven 3.9.9 增加约 9 MB。

### 多阶段构建

- `builder` 阶段：仅用于编译 Python（含 gcc / `*-dev` 头文件）
- `runtime` 阶段：从 builder 复制已编译的 Python，不包含编译器

这样 `gcc`、`g++`、`*-dev` 包（约 300 MB）不会进入最终镜像。

---

## 目录结构

```
.
├── Dockerfile               # 多阶段构建
├── docker-compose.yml       # 编排（端口 3443 → 8443）
├── .dockerignore
├── .gitignore
├── systemd/
│   ├── code-server.service  # systemd 单元（以 root 运行，HOME=/home/coder）
│   ├── override.conf        # 单元覆盖
│   └── mask-units.sh        # 屏蔽不适用的 systemd 单元
├── config/
│   ├── code-server-config.yaml       # code-server 全局配置模板
│   ├── code-server-settings.json     # code-server 用户 settings.json 模板
│   └── maven-settings.xml            # Maven 阿里云镜像配置模板
├── scripts/
│   ├── entrypoint.sh        # 密码处理 + hostname 同步 + coder 配置初始化 + exec systemd
│   └── verify.sh            # 构建后冒烟测试
├── home/                    # coder 用户数据持久化（运行时自动创建，git 忽略）
├── workspace/               # 默认工作区（运行时自动创建，git 忽略）
├── README.md                # 英文文档
└── README-CN.md             # 中文文档（本文件）
```

---

## 常用命令

```bash
# 进入容器
docker exec -it devbox bash

# 查看 systemd 状态
docker exec -it devbox systemctl list-units

# 查看 code-server 状态
docker exec -it devbox systemctl status code-server

# 查看日志
docker exec -it devbox journalctl -u code-server -f

# 重启 code-server
docker exec -it devbox systemctl restart code-server
```

---

## 镜像仓库

```
crpi-itfr2l0fn5lzqol6.cn-chengdu.personal.cr.aliyuncs.com/giwu/devbox:latest
```

## 部署到其他机器（简化版）

```bash
# 在目标机器上
mkdir -p /opt/systemdbox && cd /opt/systemdbox
# 把项目文件（除 home/ workspace/）scp / git clone 过来
docker compose up -d
```

## 更新日志

- **v1.1.0**
  - APT 软件源切换到清华源（`mirrors.tuna.tsinghua.edu.cn`）
  - npm 默认淘宝源（`registry.npmmirror.com`）
  - 新增 Maven 3.9.9，仓库走阿里云镜像（`maven.aliyun.com`）
  - code-server 关闭 workspace trust，HOME 改为 `/home/coder`，默认打开 `/home/coder/workspace`
  - 修复 `/etc/hostname` 内容异常导致的 "Hostname set to <debain>" 警告（Debian Bug #853731）
- **v1.1.1**
  - `files.dialog.defaultPath: /`，File dialog 一展开就在根目录，可直接 Add Folder 到任意路径
- **v1.1.2**
  - 修复 `sudo: unable to resolve host devbox` 警告（注入 `devbox.localdomain` 到 `/etc/hosts`）

---

## License

仅供个人学习使用。