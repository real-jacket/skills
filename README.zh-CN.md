# Skills

**中文** · [English](README.md)

个人收集的可复用 [Agent Skills](https://agentskills.io/specification) —— 每个 skill 都是自包含的文件夹，包含指令、脚本和参考资料，让编码 Agent 掌握某项具体工作的正确做法。

所有 skill 都遵循开放的 `SKILL.md` 约定，因此可以在 Claude Code、Codex、Cursor、OpenCode、DeepSeek Harness 等任何支持该标准的宿主中使用，不绑定任何单一厂商。

## 技能列表

| Skill | 作用 |
| --- | --- |
| [`macos-proxy-leak-audit`](skills/macos-proxy-leak-audit/SKILL.md) | 排查 macOS 上 Clash Verge / TUN 场景的 WebRTC 与 DNS 泄漏，追溯系统 DNS 的真实来源，并隔离境外浏览器而不影响国内 WebRTC。 |

### [macos-proxy-leak-audit](skills/macos-proxy-leak-audit/SKILL.md)

代理出口显示在法兰克福，但 WebRTC 测试仍然暴露出你的真实地址。这个 skill 负责找出原因。

- 追溯系统 DNS 的真实来源，包括 Clash Verge 的 TUN 助手写入的 `114.114.114.114` 占位地址 —— 它看起来像泄漏，但通常并不是
- 检查 IPv6 旁路、scoped resolver、TUN 路由，以及 PAC / WPAD 残留配置
- 解释为什么国内 STUN 服务器会走 `DIRECT` 从而暴露真实 IPv4，并只隔离境外浏览器（Chrome 独立 profile 配合 WebRTC 限制扩展，或 Firefox profile 设置 `media.peerconnection.enabled=false`），同时保持国内 WebRTC 可用
- 复测代理出口与递归解析器，并在改动前先写好回滚方案
- 默认只读；任何系统或 Clash 改动都需要明确确认

附带：只读审计脚本、取证命令参考、Clash Verge DNS/TUN 模型说明。

## 安装

### 任意 Agent（skills CLI）

```bash
npx skills add real-jacket/skills
```

交互式选择 skill 和 Agent，或直接安装指定的一个：

```bash
npx skills add real-jacket/skills --skill macos-proxy-leak-audit -a claude-code
```

加 `-g` 可安装到所有项目而不是当前项目。

### Claude Code（插件市场）

```bash
/plugin marketplace add real-jacket/skills
/plugin install macos-proxy-leak-audit@jacket-skills
```

### 手动安装

把 skill 目录复制或软链接到你的 Agent skills 目录：

```bash
cp -R skills/macos-proxy-leak-audit <your-agent-skills-dir>/
```

具体路径因宿主而异，这里刻意不写死。覆盖已有的同名 skill 前请先备份。

## 目录结构

```text
skills/<skill-name>/
├── SKILL.md          # 必需：YAML frontmatter + 指令
├── references/       # 可选：按需加载的详细资料
├── scripts/          # 可选：确定性脚本
└── assets/           # 可选：复制到输出中的文件
```

`SKILL.md` 的 frontmatter 包含 `name`（小写 kebab-case，与目录名一致）和 `description`（说明做什么，以及哪些说法应该触发它）。其余部分都是可选的。

设计原则是渐进式披露：只有 `name` 和 `description` 会常驻 Agent 上下文；skill 被触发时才加载正文；`references/` 仅在 Agent 判断需要时才加载。所以 `SKILL.md` 保持精简，细节放在 references 里。

## 仓库结构

```text
skills/
├── .claude-plugin/
│   └── marketplace.json   # 使仓库可作为插件市场安装
├── .github/workflows/
│   └── validate.yml       # CI：校验器 + shellcheck
├── skills/
│   └── macos-proxy-leak-audit/
├── scripts/
│   └── validate-skills.mjs
├── template/
│   └── SKILL.md           # 新建 skill 的起点
├── LICENSE
├── README.md
└── README.zh-CN.md
```

## 新增一个 skill

1. 复制 `template/` 到 `skills/<skill-name>/`，目录名必须与 frontmatter 的 `name` 完全一致。
2. 在 `.claude-plugin/marketplace.json` 中添加对应条目。
3. 提交前先校验：

   ```bash
   node scripts/validate-skills.mjs
   ```

校验器会检查：frontmatter 能否解析、name 是否与目录名一致、description 是否足够长以保证可靠触发、`SKILL.md` 中提到的每个 `references/` 与 `scripts/` 路径是否真实存在、随附脚本是否可执行，以及 `marketplace.json` 是否恰好列出了实际存在的 skill。CI 会运行同样的检查，并对所有随附 shell 脚本执行 `shellcheck`。

## 安全说明

- `skills/macos-proxy-leak-audit/scripts/audit-macos-leaks.sh` 是只读的，不会修改网络设置。
- 其输出包含本地网络信息，分享前请先审阅并脱敏。
- 任何 `networksetup -set*`、Clash 配置修改或重启都需要明确确认 —— skill 会指示 Agent 先询问。
- 仓库中不包含任何个人公网 IP、UUID、订阅链接或凭证。

使用任何 skill 前请自行审阅：skill 会以你授予 Agent 的权限运行。

## License

[MIT](LICENSE) © real-jacket
