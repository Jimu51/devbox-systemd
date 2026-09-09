# devbox

A Docker image that ships a full multi-language developer workstation:

| Component | Version | Notes |
|---|---|---|
| Base | `debian:12-slim` | |
| Init | `systemd` (PID 1) | run as actual init system |
| Python | **3.12.14** | built from source, `venv` / `pipx` / `poetry` / `pip-tools` preinstalled |
| Node.js | **22.23.2** (Jod LTS) | `yarn`, `pnpm`, `typescript`, `tsx`, `corepack` enabled |
| JDK | **Temurin 21.0.12.1+1** | `JAVA_HOME=/opt/jdk-21`, JDK only |
| code-server | **4.135.0** | official `.deb`, managed by `systemd` |

All binaries are pinned by SHA-256; `Dockerfile` rebuilds fail loudly on mismatch.

---

## Quick start

### docker run

```bash
docker run -d \
  --name devbox \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 3443:8443 \
  -e PASSWORD='changeme' \
  devbox:latest
```

Open <http://localhost:3443> and log in with the password above.

### docker compose

```bash
PASSWORD='changeme' docker compose up -d
```

### access shell

```bash
docker exec -it devbox bash
docker exec -it devbox systemctl list-units
```

---

## Why `--privileged` + `/sys/fs/cgroup`?

`systemd` needs to write to the cgroup hierarchy (to track PID 1, spawn
units, run `journald`). On cgroup-v2 hosts:

* `--privileged` (or `--cap-add SYS_ADMIN --security-opt seccomp=unconfined`)
* `--cgroupns=host` — share the host cgroup namespace so systemd can manage
  its slice
* bind-mount `/sys/fs/cgroup` read-write

On cgroup-v1 hosts only the bind-mount is strictly required; the flags above
remain harmless.

---

## Configuration

### Environment variables

| Variable | Effect |
|---|---|
| `PASSWORD` | plain-text password for code-server (hashed on container start) |
| `HASHED_PASSWORD` | pre-computed argon2 hash (skips hashing) |
| `SUDO_PASSWORD` / `HASHED_SUDO_PASSWORD` | sudo password inside the IDE |
| `TZ` | timezone, defaults to `UTC` |

The entrypoint writes these into `/etc/code-server/code-server.env`, which
the systemd unit sources via `EnvironmentFile=`.

### Files

| Path | Purpose |
|---|---|
| `/etc/code-server/config.yaml` | code-server config (bind addr, auth mode) |
| `/etc/code-server/code-server.env` | generated runtime env |
| `/etc/systemd/system/code-server.service` | systemd unit |
| `/etc/systemd/system/code-server.service.d/override.conf` | restart policy |
| `/home/coder/workspace` | default workspace mount point |

### Restart policy

* systemd: `Restart=on-failure`, `RestartSec=5`
* docker: `restart: unless-stopped` (compose) / `--restart unless-stopped` (cli)

---

## Verify the image

```bash
./scripts/verify.sh             # CONTAINER=devbox ./scripts/verify.sh
```

Checks installed versions, `systemctl is-system-running`, code-server
service status, and the `/healthz` endpoint.

---

## Build

```bash
docker build -t devbox:latest .
# 完整版（含 code-server 内置 Copilot、Mermaid 等扩展）
docker build -t devbox:full --build-arg SLIM_CODE_SERVER=false .
# 自定义组件版本：
docker build -t devbox:py3.12.14-node22.23.2-jdk21.0.12.1-cs4.135.0 \
  --build-arg PYTHON_VERSION=3.12.14 \
  --build-arg NODE_VERSION=22.23.2 \
  --build-arg JDK_VERSION=21.0.12.1 \
  --build-arg JDK_BUILD=1 \
  --build-arg CODE_SERVER_VERSION=4.135.0 .
```

### Slim 模式（默认）

`SLIM_CODE_SERVER=true` 默认开启。镜像会移除以下内置扩展：

| 扩展 | 节省 |
|---|---|
| GitHub Copilot | ~360 MB |
| Mermaid Markdown Features | ~63 MB |

如需这些功能，可在 code-server 内手动安装。

最终镜像大小：**~460 MB**（精简模式）/ **~880 MB**（完整模式）。

---

## Layout

```
.
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── systemd/
│   ├── code-server.service
│   ├── override.conf
│   └── mask-units.sh
├── scripts/
│   ├── entrypoint.sh        # env propagation, then exec systemd
│   └── verify.sh            # post-build smoke test
└── README.md
```
