## 📋 变更类型

- [ ] Bug 修复（fix）
- [ ] 新功能（feat）
- [ ] 文档更新（docs）
- [ ] 性能优化（perf）
- [ ] 重构（refactor）
- [ ] 构建 / CI（build / ci）
- [ ] 其他：____

## 🔗 关联 Issue

- 关联: #____

## 📝 变更说明

简要描述这个 PR 做了什么、为什么这么做。

## 🧪 测试

- [ ] 本地 `docker build -t devbox:test .` 通过
- [ ] 本地 `docker compose up -d` 后 `/healthz` 返回 200
- [ ] `CONTAINER=devbox ./scripts/verify.sh` 通过
- [ ] 浏览器登录 code-server 正常
- [ ] `sudo` 在终端工作正常

## 📋 改动清单

- [ ] Dockerfile
- [ ] docker-compose.yml
- [ ] systemd/
- [ ] scripts/
- [ ] .github/workflows/
- [ ] README.md / README-CN.md

## 🖼️ 截图 / 日志

如有，贴出验证日志或截图。

## ⚠️ 注意事项

- 是否涉及镜像版本号变更（PYTHON_VERSION / NODE_VERSION / JDK_VERSION / CODE_SERVER_VERSION）？
- 是否动过密码默认值（`docker-compose.yml` 的 `PASSWORD`）？
- 是否会影响镜像大小（增减 > 50 MB）？
- 是否引入了新的环境变量？

## 🔍 自查清单

- [ ] 没有提交运行期数据（`home/`、`workspace/`）
- [ ] 没有提交密码或密钥
- [ ] 没有合并冲突
- [ ] commit 信息清晰
- [ ] 通过 GitHub Actions CI（如果已配置）