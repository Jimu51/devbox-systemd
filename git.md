# Git 推送项目到 GitHub 详细步骤

本文档记录 `systemdbox` 项目从本地到 GitHub 私有仓库（`Jimu51/systemdbox`）的完整推送流程，作为以后同类项目的参考手册。

---

## 0. 总览流程

```
┌─────────────────────────────────────────────────────────────────┐
│                  GitHub  推送  完整流程                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ① GitHub 创建空仓库（网页手动）                               │
│  ② 本地生成专用 SSH key                                       │
│  ③ SSH 公钥添加到 GitHub 账号                                │
│  ④ 本地项目 git init + 配置                                   │
│  ⑤ 编写 .gitignore                                            │
│  ⑥ git add + git commit                                       │
│  ⑦ git remote add origin ...                                  │
│  ⑧ git push -u origin main                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. 前置准备：GitHub 创建空仓库

> ⚠️ **必须先建仓库并把 SSH key 添加好**，否则后面 `git push` 会失败。

### 1.1 在 GitHub 网页创建空仓库

打开 https://github.com/new ：

| 字段 | 填什么 |
|---|---|
| Owner | `Jimu51`（你的用户名） |
| Repository name | `systemdbox` |
| Description | （可选）`Multi-language dev container (systemd + Python + Node + JDK + code-server)` |
| Visibility | **Private** ✓ |
| Initialize this repository with: | **全部不勾选** ⚠️ |

点击 **Create repository**。

### 1.2 验证仓库已创建

```bash
git ls-remote git@github.com:Jimu51/systemdbox.git
# 应该看到 refs/heads/main 是空的（或不显示）
```

---

## 2. 生成专用 SSH Key

> 为每个项目生成独立的 SSH key，方便管理；不要复用旧 key。

### 2.1 检查现有 SSH key

```bash
ls -la ~/.ssh/id_*.pub
```

如果有 `id_ed25519_github.pub` 这种项目专用 key，可以跳过生成步骤。

### 2.2 生成 ed25519 key（推荐）

```bash
# 推荐算法：ed25519（短且安全）
ssh-keygen -t ed25519 -N "" \
  -f ~/.ssh/id_ed25519_github \
  -C "Jimu51@systemdbox"
```

参数说明：
- `-t ed25519`：使用 ed25519 算法（256 位，足够安全）
- `-N ""`：空密码（避免每次 push 都要输入密码）
- `-f`：key 文件路径
- `-C`：注释（用于区分不同 key）

### 2.3 验证生成的 key

```bash
ls -la ~/.ssh/id_ed25519_github*
# 私钥 600 权限，公钥 644 权限

ssh-keygen -l -f ~/.ssh/id_ed25519_github.pub
# 输出: 256 SHA256:ZGNLRcAMIycYOsXF8ip1KpsCd9dxU7xKION+RLW6HgU Jimu51@systemdbox (ED25519)
```

> **记下指纹**：添加公钥到 GitHub 后，可在 https://github.com/settings/keys 核对指纹是否一致。

---

## 3. SSH 公钥添加到 GitHub

### 3.1 显示公钥内容

```bash
cat ~/.ssh/id_ed25519_github.pub
```

整行输出形如：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHgAyFRC3Lnw1BOs24CQrEi9s2vut9uNys6WQEDgzn0b Jimu51@systemdbox
```

### 3.2 添加到 GitHub

打开 https://github.com/settings/keys → **New SSH key**：

| 字段 | 填什么 |
|---|---|
| Title | `systemdbox devbox` |
| Key type | `Authentication Key` |
| Key | 粘贴上面整行公钥 |

### 3.3 常见错误与对策

| 错误 | 原因 | 修复 |
|---|---|---|
| "Key is invalid" | 公钥不完整 / 错位 | 重新整行复制，确保以 `ssh-ed25519` 开头 |
| "Begins with ssh-rsa..." | 复制了**私钥** | 删除重贴，应该是公钥 |
| 长度 <99 字符 | 截断 | 重新 `cat ~/.ssh/id_ed25519_github.pub` 复制 |
| 注释不是 `Jimu51@systemdbox` | key 搞混了 | 删除重贴 |

### 3.4 验证连接

```bash
ssh -T -i ~/.ssh/id_ed25519_github \
  -o IdentitiesOnly=yes \
  git@github.com
```

期望输出：

```
Hi Jimu51! You've successfully authenticated, but GitHub does not provide shell access.
```

---

## 4. 配置 ~/.ssh/config（推荐）

让 `git@github.com` 自动使用正确的 key：

```bash
mkdir -p ~/.ssh
cat > ~/.ssh/config <<'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config
```

作用：
- `git push` 时自动用专用 key，不会因多个 key 混淆而失败
- `IdentitiesOnly yes` 禁止 ssh-agent 兜底（避免 key 探测耗时）
- `StrictHostKeyChecking accept-new` 自动接受新主机指纹

---

## 5. 本地 Git 初始化

### 5.1 配置 Git 身份

```bash
git config --global user.name "Jimu51"
git config --global user.email "Jimu51@users.noreply.github.com"
git config --global init.defaultBranch main
git config --global core.sshCommand "ssh -i ~/.ssh/id_ed25519_github -o IdentitiesOnly=yes"
```

> **邮件地址推荐用 GitHub 提供的 noreply 地址**（`用户名@users.noreply.github.com`），这样 commit 不会被关联到真实邮箱，且 GitHub 会正确显示头像链接。

### 5.2 验证配置

```bash
git config --global --list | grep -E "user|init|sshCommand"
```

期望输出形如：

```
user.name=Jimu51
user.email=Jimu51@users.noreply.github.com
init.defaultbranch=main
core.sshcommand=ssh -i ~/.ssh/id_ed25519_github -o IdentitiesOnly=yes
```

---

## 6. 创建 .gitignore

> `.gitignore` 与 `.dockerignore` 用途不同：
> - `.gitignore`：阻止 git 跟踪
> - `.dockerignore`：阻止 docker 构建时拷贝进镜像

新建 `.gitignore`（内容根据项目调整）：

```gitignore
# 运行期数据（Docker 卷挂载点）
home/
workspace/

# 通用 IDE / 编辑器
.vscode/
.idea/
.DS_Store
*.swp
*.bak
*.tmp

# 敏感配置
.env
.env.local

# Python
__pycache__/
*.pyc

# Node
node_modules/

# 构建产物
build/
dist/
*.tar.gz
*.deb

# 凭据
*.pem
*.key
credentials.json
```

### 验证忽略生效

```bash
# 检查是否被忽略
git check-ignore -v home home/ workspace workspace/

# 应该输出类似：
# .gitignore:2:home/    home
# .gitignore:2:home/    home/
# .gitignore:3:workspace/ workspace
```

---

## 7. git init + 首次 commit

### 7.1 在项目根目录初始化

```bash
cd /path/to/your/project
git init -b main
```

`-b main` 直接用 `main` 作为默认分支（避免 `master`）。

### 7.2 检查要提交的文件

```bash
git status --short
git status --ignored | grep "^!!" | head -10
```

确保：
- ✅ 所有源码/配置文件都在 untracked 列表里
- ✅ 敏感数据（home/ workspace/ 等）不在 untracked 里

### 7.3 添加并提交

```bash
git add .

# 再次确认
git status --short

# 写好 commit message（推荐详细格式）
git commit -m "feat: initial commit - systemdbox multi-language dev container

Components:
- Base: debian:12-slim
- Init:  systemd (PID 1, privileged + cgroup host)
- Python: 3.12.14 (源码编译 + slim)
- Node:   22.23.2 (Jod LTS) + yarn/pnpm/typescript/tsx
- JDK:    Temurin 21.0.12.1+1 (Server VM only)
- code-server: 4.135.0 (运行身份 root)

Features:
- /healthz 健康检查
- 自动生成 16 位 code-server 密码
- Asia/Shanghai 时区默认
- host 网络模式可选
- host:3443 → container:8443 端口映射
- ./home 持久化 coder 数据
- ./workspace 工作区挂载

镜像: crpi-itfr2l0fn5lzqol6.cn-chengdu.personal.cr.aliyuncs.com/giwu/devbox:latest
大小: ~466 MB (slim)"
```

Commit message 规范（可选但推荐）：
- `feat:` 新功能
- `fix:` 修复 bug
- `docs:` 文档
- `refactor:` 重构
- `chore:` 构建/CI 等杂项

---

## 8. 关联远程仓库

```bash
git remote add origin git@github.com:Jimu51/systemdbox.git
git remote -v
```

期望输出：

```
origin  git@github.com:Jimu51/systemdbox.git (fetch)
origin  git@github.com:Jimu51/systemdbox.git (push)
```

---

## 9. 首次推送

### 9.1 正常推送（远程为空时）

```bash
git push -u origin main
```

期望输出：

```
To github.com:Jimu51/systemdbox.git
 * [new branch]      main -> main
Branch 'main' set up to track remote branch 'main' from 'origin'.
```

### 9.2 处理冲突（远程已有提交时）

如果远程有别人或自己之前提交的代码：

```bash
# 查看远程有什么
git fetch origin
git log --oneline origin/main

# 看差异
git log --oneline HEAD..origin/main  # 远程多出
git log --oneline origin/main..HEAD  # 本地多出
```

#### 方案 A：拉取并合并（保留双方历史）

```bash
git pull --rebase origin main
git push -u origin main
```

#### 方案 B：强推覆盖（**仅适用于新仓库 / 你确定远程内容可丢**）

```bash
git push --force-with-lease origin main
```

`--force-with-lease` 比 `--force` 安全：会先检查远程没有别人新提交，避免覆盖。

#### 方案 C：合并（保留双方历史但产生 merge commit）

```bash
git pull origin main
git push -u origin main
```

### 9.3 systemdbox 实际遇到的情况

我们推 `Jimu51/systemdbox` 时，远程已有 3 个 "Add files via upload" 提交（用户通过 GitHub 网页上传的）。处理：

```bash
git push --force-with-lease origin main
# 输出: + b2916d9...c072ba8 main -> main (forced update)
```

理由：项目刚建、用户单独使用、本地有完整的 LICENSE + .github/，结构化历史更合适。

---

## 10. 验证推送结果

### 10.1 本地核对

```bash
git fetch origin
git log --oneline origin/main
```

### 10.2 浏览器查看

打开 https://github.com/Jimu51/systemdbox 应看到：
- 文件树
- commit 历史
- README.md 渲染

---

## 11. 后续维护

### 11.1 修改文件并提交

```bash
# 修改某些文件后
git add .
git commit -m "feat: 新增 ..."
git push origin main
```

### 11.2 打 tag（语义化版本）

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### 11.3 拉取远程更新

```bash
git pull --rebase origin main
```

### 11.4 切换 key（多项目场景）

如果要给另一个项目用不同的 key：

```bash
# ~/.ssh/config 中加 Host 别名
cat >> ~/.ssh/config <<'EOF'

Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
EOF

# remote URL 用别名
git remote set-url origin git@github-work:Org/repo.git
```

---

## 12. 备选方案：HTTPS + Personal Access Token

如果 SSH 添加始终不顺利，HTTPS + PAT 更简单。

### 12.1 创建 PAT

打开 https://github.com/settings/tokens → **Generate new token (classic)**：

| 字段 | 值 |
|---|---|
| Note | `systemdbox devbox` |
| Expiration | `90 days` 或 `No expiration` |
| Scopes | 勾选 `repo` |

**立即复制 token**（页面关闭后无法再看到）。

### 12.2 切换 remote 到 HTTPS

```bash
git remote set-url origin https://github.com/Jimu51/systemdbox.git
```

### 12.3 推送时输入凭据

```bash
git push -u origin main
# Username: Jimu51
# Password: <粘贴 PAT，不是 GitHub 密码>
```

### 12.4 保存凭据（避免每次输入）

```bash
# 方法 1：凭据存储（明文，但省事）
git config --global credential.helper store

# 方法 2：缓存（10小时有效）
git config --global credential.helper cache

# 第一次推送后会自动保存
```

### 12.5 HTTPS vs SSH 对比

| 维度 | HTTPS + PAT | SSH |
|---|---|---|
| 设置难度 | 简单 | 中等 |
| 跨平台 | ✓ Windows/macOS/Linux 全支持 | ✓ 全支持 |
| 防火墙友好 | ✓ 仅 443 端口 | 需 22 端口 |
| 多账号 | 需用 `includeIf` 分目录 | 用 `~/.ssh/config` 的 Host 别名 |
| 推荐度 | ★ ★ ★ | ★ ★ ★ |

---

## 13. systemdbox 项目最终状态

### 13.1 提交历史

```
927016e docs: 添加 MIT License
c072ba8 ci:   添加 GitHub Actions 自动构建推送流程 + Issue/PR 模板
f495080 docs:  添加中文 README (README-CN.md)
dde0836 feat: initial commit - systemdbox multi-language dev container
```

### 13.2 远程文件清单（16 个）

```
.dockerignore
.github/ISSUE_TEMPLATE/bug_report.md
.github/ISSUE_TEMPLATE/feature_request.md
.github/PULL_REQUEST_TEMPLATE.md
.github/workflows/build-push.yml
.gitignore
Dockerfile
LICENSE
README.md
README-CN.md
docker-compose.yml
scripts/entrypoint.sh
scripts/verify.sh
systemd/code-server.service
systemd/mask-units.sh
systemd/override.conf
```

### 13.3 GitHub Secrets（CI 触发需要）

打开 https://github.com/Jimu51/systemdbox/settings/secrets/actions 添加：

| Name | 用途 |
|---|---|
| `ACR_USERNAME` | 阿里云 ACR 登录用户名 |
| `ACR_PASSWORD` | 阿里云 ACR 登录密码 |

添加后，`git push` 会自动触发构建并推送 `crpi-.../giwu/devbox:latest`。

---

## 14. 排错速查

| 错误 | 原因 | 修复 |
|---|---|---|
| `Permission denied (publickey)` | SSH key 未注册 / 配置错 | 重新添加公钥、检查 `~/.ssh/config` |
| `fatal: not a git repository` | 没 `git init` 或在错误目录 | `cd /path/to/project && git init` |
| `rejected: fetch first` | 远程有本地没有的提交 | `git pull --rebase` 或 `git push --force-with-lease` |
| `fatal: refusing to merge unrelated histories` | 两个仓库没有关系 | `git pull --allow-unrelated-histories` 或强推 |
| `RPC failed; HTTP 413` | 推送文件过大 | `git config --global http.postBuffer 524288000` |
| `error: bad credentials` | PAT 错 / 过期 | 重新生成 PAT，更新凭据 |
| `fatal: protocol error: bad pack header` | 网络问题 / 代理问题 | 检查代理设置或换 HTTPS |

---

## 15. 一次性脚本（整合以上所有步骤）

把整个流程做成脚本，仅用于已确认的全新项目：

```bash
#!/bin/bash
# push-to-github.sh — 一键推送新项目到 GitHub
# 用法：bash push-to-github.sh <用户名> <仓库名> <邮箱> [private|public]

set -e

GITHUB_USER="$1"
REPO_NAME="$2"
EMAIL="$3"
VISIBILITY="${4:-private}"

if [ -z "$GITHUB_USER" ] || [ -z "$REPO_NAME" ]; then
    echo "用法: $0 <用户名> <仓库名> <邮箱> [private|public]"
    exit 1
fi

KEY_FILE="$HOME/.ssh/id_ed25519_${REPO_NAME}"

echo "=== 1. 生成 SSH key ==="
if [ ! -f "$KEY_FILE.pub" ]; then
    ssh-keygen -t ed25519 -N "" \
        -f "$KEY_FILE" \
        -C "${GITHUB_USER}@${REPO_NAME}"
fi

echo
echo "=== 2. 公钥（请到 https://github.com/settings/keys 添加） ==="
cat "$KEY_FILE.pub"
echo
echo "等待你添加完公钥后按回车继续..."
read

echo
echo "=== 3. 配置 ~/.ssh/config ==="
grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null || cat >> "$HOME/.ssh/config" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile ${KEY_FILE}
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
chmod 600 "$HOME/.ssh/config"

echo "=== 4. 测试连接 ==="
ssh -T -i "$KEY_FILE" -o IdentitiesOnly=yes git@github.com

echo
echo "=== 5. Git 配置 ==="
git config --global user.name "$GITHUB_USER"
git config --global user.email "${EMAIL}"
git config --global init.defaultBranch main
git config --global core.sshCommand "ssh -i ${KEY_FILE} -o IdentitiesOnly=yes"

echo
echo "=== 6. 请确认 GitHub 仓库已创建："
echo "    https://github.com/${GITHUB_USER}/${REPO_NAME} (${VISIBILITY})"
echo "    Initialize 选项全部不勾选"
echo "按回车继续..."
read

echo
echo "=== 7. git init + commit ==="
git init -b main

# 创建默认 .gitignore（如果不存在）
if [ ! -f .gitignore ]; then
    cat > .gitignore <<'EOF'
# 运行期数据
home/
workspace/
# 通用
.vscode/ .idea/ .DS_Store *.swp *.bak
# 敏感
.env .env.local
# Python
__pycache__/ *.pyc
# Node
node_modules/
# 构建产物
build/ dist/ *.tar.gz *.deb
# 凭据
*.pem *.key credentials.json
EOF
fi

git add .
git commit -m "feat: initial commit"

echo
echo "=== 8. 推送 ==="
git remote add origin "git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
git push --force-with-lease -u origin main

echo
echo "✓ 完成！https://github.com/${GITHUB_USER}/${REPO_NAME}"
```

> ⚠️ **使用注意**：脚本要求用户手动添加公钥 + 手动创建空仓库。仅用于全新项目。

---

## 16. 参考资料

- GitHub 官方文档：https://docs.github.com/en/authentication/connecting-to-github-with-ssh
- Pro Git（中文）：https://git-scm.com/book/zh/v2
- Conventional Commits：https://www.conventionalcommits.org/