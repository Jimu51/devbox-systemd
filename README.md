# devbox-systemd

A Docker image that ships a full multi-language developer workstation
with systemd as PID 1:

| Component | Version | Notes |
|---|---|---|
| Base | `debian:13-slim` (trixie) | systemd 257, glibc 2.41 |
| Init | `systemd` (PID 1) | run as actual init system |
| Python | **3.12.14** | built from source, `venv` / `pipx` / `poetry` / `pip-tools` preinstalled |
| Node.js | **22.23.2** (Jod LTS) | `yarn`, `pnpm`, `typescript`, `tsx`, `corepack` enabled |
| JDK | **Temurin 21.0.12.1+1** | `JAVA_HOME=/opt/jdk-21`, JDK only |
| Maven | **3.9.9** | Aliyun mirror, `MAVEN_HOME=/opt/maven` |
| code-server | **4.135.0** | official `.deb`, managed by `systemd` |
| `lsof` | **4.99.4+dfsg-2** | debug tool (open files), preinstalled |

All binaries are pinned by SHA-256; `Dockerfile` rebuilds fail loudly on mismatch.

---

## Quick start

### docker run

```bash
docker run -d \
  --name devbox-systemd \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 3443:8443 \
  -e PASSWORD='changeme' \
  devbox-systemd:latest
```

Open <http://localhost:3443> and log in with the password above.

### docker compose

```bash
PASSWORD='changeme' docker compose up -d
```

### access shell

```bash
docker exec -it devbox-systemd bash
docker exec -it devbox-systemd systemctl list-units
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
| `TZ` | timezone, defaults to `Asia/Shanghai` |

The entrypoint writes these into `/etc/code-server/code-server.env`, which
the systemd unit sources via `EnvironmentFile=`.

### Files

| Path | Purpose |
|---|---|
| `/etc/code-server/config.yaml` | code-server config (bind addr, auth mode) |
| `/etc/code-server/code-server.env` | generated runtime env |
| `/etc/systemd/system/code-server.service` | systemd unit |
| `/etc/systemd/system/code-server.service.d/override.conf` | restart policy |
| `/etc/systemd/system/fix-hostname.service` | Debian Bug #853731 workaround |
| `/home/coder/workspace` | default workspace mount point |

### Restart policy

* systemd: `Restart=on-failure`, `RestartSec=5`
* docker: `restart: unless-stopped` (compose) / `--restart unless-stopped` (cli)

---

## Verify the image

```bash
./scripts/verify.sh             # CONTAINER=devbox-systemd ./scripts/verify.sh
```

Checks installed versions, `systemctl is-system-running`, code-server
service status, and the `/healthz` endpoint.

---

## Build

```bash
docker build -t devbox-systemd:latest .
# Full mode (keep all code-server built-in extensions, ~880 MB)
docker build -t devbox-systemd:full --build-arg SLIM_CODE_SERVER=false .
# Custom component versions:
docker build -t devbox-systemd:py3.12.14-node22.23.2-jdk21.0.12.1-cs4.135.0 \
  --build-arg PYTHON_VERSION=3.12.14 \
  --build-arg NODE_VERSION=22.23.2 \
  --build-arg JDK_VERSION=21.0.12.1 \
  --build-arg JDK_BUILD=1 \
  --build-arg CODE_SERVER_VERSION=4.135.0 .
```

### Slim mode (default)

`SLIM_CODE_SERVER=true` 默认开启。镜像会移除以下内置扩展：

| Extension | Saved |
|---|---|
| GitHub Copilot | ~360 MB |
| Mermaid Markdown Features | ~63 MB |

如需这些功能，可在 code-server 内手动安装。

最终镜像大小：**~475 MB**（精简模式）/ **~880 MB**（完整模式）。

---

## Layout

```
.
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .github/
│   ├── workflows/build-push.yml     # GH Actions → ACR
│   ├── ISSUE_TEMPLATE/{bug,feature}_*.md
│   └── PULL_REQUEST_TEMPLATE.md
├── systemd/
│   ├── code-server.service
│   ├── fix-hostname.service    # Debian Bug #853731 workaround
│   ├── override.conf
│   └── mask-units.sh
├── config/                       # user-level config templates
│   ├── code-server-config.yaml
│   ├── code-server-settings.json
│   ├── code-server.env.template
│   └── maven-settings.xml
├── scripts/
│   ├── entrypoint.sh            # hostname sync, env propagation, exec systemd
│   └── verify.sh                # post-build smoke test
└── README.md
```