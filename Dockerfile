# ============================================================
# devbox 镜像构建文件（多阶段 + 精简版）
# ------------------------------------------------------------
# 组件版本：
#   * Base   : debian:12-slim
#   * Init   : systemd (PID 1)
#   * Python : 3.12.14 (源码编译)
#   * Node   : 22.23.2 (Jod LTS)
#   * JDK    : Temurin 21.0.12.1+1
#   * code-server : 4.135.0
# 体积优化：
#   * 构建阶段（gcc/编译器/-dev 包）独立，不进入最终镜像
#   * 移除 Python 测试套件 / IDLE / tkinter / lib2to3
#   * 移除 Node.js include / 文档
#   * 移除 JDK src.zip / jmods / include
#   * 移除 code-server 内置的 Copilot / Mermaid 等可选扩展
# ============================================================

# syntax=docker/dockerfile:1.7

# ============================================================
# 构建阶段：仅用于编译 Python
# ============================================================
FROM debian:12-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VERSION=3.12.14
ARG PYTHON_SHA256=5c8462af5790baf43a321a1559dbe0db06d1be4300fb85fb53c40060668e548a

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        build-essential \
        pkg-config \
        libffi-dev \
        libssl-dev \
        zlib1g-dev \
        libsqlite3-dev \
        libbz2-dev \
        libreadline-dev \
        libncursesw5-dev \
        libgdbm-dev \
        libgdbm-compat-dev \
        liblzma-dev \
        uuid-dev \
        libexpat1-dev; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors \
         --connect-timeout 60 --max-time 1800 \
         "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" \
         -o python.tar.xz; \
    echo "${PYTHON_SHA256}  python.tar.xz" | sha256sum -c -; \
    mkdir -p /usr/src/python; \
    tar -xJf python.tar.xz -C /usr/src/python --strip-components=1; \
    rm python.tar.xz; \
    cd /usr/src/python; \
    ./configure \
        --prefix=/opt/python-3.12.14 \
        --enable-shared \
        --with-ensurepip=install \
        --without-test-suite \
        --without-doc-strings \
        LDFLAGS="-Wl,-rpath=/opt/python-3.12.14/lib"; \
    make -j"$(nproc)"; \
    make install; \
    cd /; \
    rm -rf /usr/src/python

# ============================================================
# 运行阶段：最终镜像（无编译器、无 -dev 包）
# ============================================================
FROM debian:12-slim

ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND} \
    container=docker \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    JAVA_HOME=/opt/jdk-21 \
    PATH=/opt/python-3.12.14/bin:/opt/node-22/bin:/opt/jdk-21/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ARG PYTHON_VERSION=3.12.14
ARG NODE_VERSION=22.23.2
ARG NODE_SHA256=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
ARG JDK_VERSION=21.0.12.1
ARG JDK_BUILD=1
ARG JDK_SHA256=ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
ARG CODE_SERVER_VERSION=4.135.0
ARG CODE_SERVER_SHA256=f87d0d49c6c0a59d41214c9510f506e4123991f2d27b41f6d56f3f5c96458d3e
# 是否移除 code-server 的可选扩展（copilot、mermaid 等，约 420MB）
# 默认开启精简；如需完整 IDE，可设 --build-arg SLIM_CODE_SERVER=false
ARG SLIM_CODE_SERVER=true

# ------------------ 第一阶段：基础系统与运行时依赖 ------------------
# 注意：这里只安装运行/调试时需要的包，不安装 gcc / *-dev
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # systemd：让容器以 systemd 为 PID 1
        systemd \
        systemd-sysv \
        dbus \
        # 基础工具
        ca-certificates \
        curl \
        locales \
        tini \
        xz-utils \
        # 运行时库（与 Python 链接）
        libffi8 \
        libsqlite3-0 \
        libbz2-1.0 \
        libreadline8 \
        libncursesw6 \
        libgdbm6 \
        liblzma5 \
        libexpat1 \
        # 通用开发辅助工具
        git \
        openssh-client \
        sudo \
        file \
        procps; \
    rm -rf /var/lib/apt/lists/*; \
    sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen; \
    locale-gen; \
    echo "uninitialized" > /etc/machine-id; \
    rm -f /var/lib/systemd/random-seed

# 引入屏蔽脚本并执行
COPY systemd/mask-units.sh /tmp/mask-units.sh
RUN bash /tmp/mask-units.sh && rm /tmp/mask-units.sh

# ------------------ 第二阶段：从 builder 复制 Python ------------------
COPY --from=builder /opt/python-3.12.14 /opt/python-3.12.14
RUN set -eux; \
    ldconfig; \
    ln -sf /opt/python-3.12.14/bin/python3.12 /usr/local/bin/python3.12; \
    ln -sf /opt/python-3.12.14/bin/python3.12 /usr/local/bin/python3; \
    ln -sf /opt/python-3.12.14/bin/python3.12-config /usr/local/bin/python3.12-config; \
    ln -sf /opt/python-3.12.14/bin/pip3.12   /usr/local/bin/pip3.12; \
    ln -sf /opt/python-3.12.14/bin/pip3.12   /usr/local/bin/pip; \
    # 升级 pip 并安装常用工具
    python3.12 -m pip install --no-cache-dir --upgrade pip setuptools wheel; \
    python3.12 -m pip install --no-cache-dir virtualenv pipx poetry pip-tools; \
    # 清理 Python 冗余文件（约 150MB）
    PY_LIB=/opt/python-3.12.14/lib/python3.12; \
    rm -rf ${PY_LIB}/test          # 标准库测试套件 \
              ${PY_LIB}/idlelib    # IDLE IDE \
              ${PY_LIB}/lib2to3    # 废弃的转换工具 \
              ${PY_LIB}/pydoc_data # pydoc 文档数据 \
              ${PY_LIB}/tkinter    # 容器内通常不需要 GUI \
              ${PY_LIB}/turtledemo \
              /opt/python-3.12.14/share/man \
              /opt/python-3.12.14/share/doc; \
    find /opt/python-3.12.14 -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true; \
    strip --strip-unneeded /opt/python-3.12.14/lib/libpython3.12.so.* 2>/dev/null || true; \
    strip --strip-unneeded /opt/python-3.12.14/bin/python3.12 2>/dev/null || true; \
    rm -rf /root/.cache /tmp/* /var/tmp/*

# ------------------ 第三阶段：Node.js 22.23.2 LTS ------------------
RUN set -eux; \
    curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors \
         --connect-timeout 60 --max-time 1800 \
         "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
         -o node.tar.xz; \
    echo "${NODE_SHA256}  node.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/node-22; \
    tar -xJf node.tar.xz -C /opt/node-22 --strip-components=1; \
    rm node.tar.xz; \
    ln -sf /opt/node-22/bin/node     /usr/local/bin/node; \
    ln -sf /opt/node-22/bin/corepack /usr/local/bin/corepack; \
    ln -sf /opt/node-22/bin/npm      /usr/local/bin/npm; \
    ln -sf /opt/node-22/bin/npx      /usr/local/bin/npx; \
    # 删除 Node 自带 include / 文档（~70MB）
    rm -rf /opt/node-22/include \
              /opt/node-22/share \
              /opt/node-22/CHANGELOG.md \
              /opt/node-22/README.md \
              /opt/node-22/LICENSE; \
    # 常用全局包
    npm install -g --silent --no-audit --no-fund yarn pnpm typescript tsx @types/node; \
    npm cache clean --force; \
    corepack enable

# ------------------ 第四阶段：Temurin JDK 21 ------------------
RUN set -eux; \
    curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors \
         --connect-timeout 60 --max-time 1800 \
         "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JDK_VERSION}%2B${JDK_BUILD}/OpenJDK21U-jdk_x64_linux_hotspot_${JDK_VERSION}_${JDK_BUILD}.tar.gz" \
         -o jdk.tar.gz; \
    echo "${JDK_SHA256}  jdk.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/jdk-21; \
    tar -xzf jdk.tar.gz -C /opt/jdk-21 --strip-components=1; \
    rm jdk.tar.gz; \
    ln -sf /opt/jdk-21/bin/java  /usr/local/bin/java; \
    ln -sf /opt/jdk-21/bin/javac /usr/local/bin/javac; \
    ln -sf /opt/jdk-21/bin/jar   /usr/local/bin/jar; \
    ln -sf /opt/jdk-21/bin/jshell /usr/local/bin/jshell; \
    # 删除 JDK 冗余（~140MB），保留 lib/server（Server VM 是默认 JVM）
    rm -rf /opt/jdk-21/lib/src.zip \
              /opt/jdk-21/jmods \
              /opt/jdk-21/include \
              /opt/jdk-21/man \
              /opt/jdk-21/legal; \
    strip --strip-unneeded /opt/jdk-21/lib/server/libjvm.so 2>/dev/null || true

# ------------------ 第五阶段：code-server ------------------
RUN set -eux; \
    curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors \
         --connect-timeout 60 --max-time 1800 \
         "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb" \
         -o code-server.deb; \
    echo "${CODE_SERVER_SHA256}  code-server.deb" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends ./code-server.deb; \
    rm code-server.deb; \
    rm -rf /var/lib/apt/lists/*; \
    # 将 .deb 自带的 unit 迁移到 /etc，便于后续覆盖
    if [ -e /lib/systemd/system/code-server.service ] && [ ! -e /etc/systemd/system/code-server.service ]; then \
        mv /lib/systemd/system/code-server.service /etc/systemd/system/code-server.service; \
    fi; \
    # 可选：移除大型内置扩展（节省 ~420MB）
    # 包括 Copilot (~360MB) 与 Mermaid (~63MB)；如需可在 IDE 内手动安装
    # 注意：@microsoft/* 是 code-server 核心运行依赖（遥测 / 1ds-core-js），必须保留
    if [ "${SLIM_CODE_SERVER}" = "true" ]; then \
        rm -rf /usr/lib/code-server/lib/vscode/extensions/copilot \
               /usr/lib/code-server/lib/vscode/extensions/mermaid-markdown-features \
               /usr/lib/code-server/lib/vscode/node_modules/@github \
               /usr/lib/code-server/lib/vscode/node_modules/katex; \
    fi; \
    rm -rf /usr/lib/code-server/lib/vscode/node_modules/.cache /tmp/* /var/tmp/*; \
    # ----------------------------------------------------------- \
    # 修复 workbench.js 中 vsda 404 警告 \
    # code-server 4.135.0 基于 VSCode 1.95+，vsda 已被上游移除 \
    # 但 workbench.js 仍会动态加载 /static/node_modules/vsda/* \
    # 这里创建 stub：脚本能加载但 default() 立刻抛错，被 catch 吞掉 \
    # ----------------------------------------------------------- \
    mkdir -p /usr/lib/code-server/lib/vscode/node_modules/vsda/rust/web; \
    printf "%s\n" \
        '// vsda stub - upstream 已移除，workbench.js 仍引用' \
        '// 让 vsda_web.default() 抛错，调用方 catch 处理' \
        'globalThis.vsda_web = { default: function() { throw new Error("vsda not bundled"); } };' \
        > /usr/lib/code-server/lib/vscode/node_modules/vsda/rust/web/vsda.js; \
    # WASM 文件只需存在（不被实际解析），用 Python 生成 8 字节 WASM magic+version \
    python3 -c "open('/usr/lib/code-server/lib/vscode/node_modules/vsda/rust/web/vsda_bg.wasm','wb').write(b'\\x00asm\\x01\\x00\\x00\\x00')"

# ------------------ 第六阶段：创建普通用户 ------------------
RUN set -eux; \
    if ! id coder >/dev/null 2>&1; then \
        useradd -m -s /bin/bash -G sudo coder; \
    fi; \
    echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder; \
    mkdir -p /home/coder/.local/share/code-server /home/coder/workspace; \
    chown -R coder:coder /home/coder

# ------------------ 第七阶段：注入 systemd 单元 ------------------
COPY systemd/code-server.service /etc/systemd/system/code-server.service
COPY systemd/override.conf      /etc/systemd/system/code-server.service.d/override.conf

RUN set -eux; \
    mkdir -p /etc/code-server /home/coder/.local/share/code-server; \
    if [ ! -e /etc/code-server/config.yaml ]; then \
        printf 'bind-addr: 0.0.0.0:8443\nauth: password\ndisable-telemetry: true\n' \
            > /etc/code-server/config.yaml; \
    fi; \
    printf '%s\n' \
        '# 容器启动时由 entrypoint.sh 自动生成，请勿手工编辑。' \
        '# 编辑 /etc/code-server/code-server.env 后重启 code-server 即可生效。' \
        '# 取消下面任意一行的注释即可启用密码：' \
        '# PASSWORD=changeme' \
        '# HASHED_PASSWORD=' \
        > /etc/code-server/code-server.env; \
    systemctl enable code-server.service; \
    systemctl set-default multi-user.target

# ------------------ 第八阶段：最终清理 ------------------
RUN set -eux; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/* /root/.cache

# ============================================================
# 元数据
# ============================================================
VOLUME ["/sys/fs/cgroup", "/run", "/run/lock", "/tmp", "/var/log/journal", "/home/coder"]

EXPOSE 8443

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
    CMD curl -fsS http://127.0.0.1:8443/healthz || exit 1

STOPSIGNAL SIGRTMIN+3

COPY scripts/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/lib/systemd/systemd", "--system"]
