# Skills

[中文](README.zh-CN.md) · **English**

A personal collection of reusable [Agent Skills](https://agentskills.io/specification) — portable, self-contained folders of instructions, scripts, and references that teach a coding agent how to do a specific job well.

Every skill follows the open `SKILL.md` convention, so it works with Claude Code, Codex, Cursor, OpenCode, DeepSeek Harness, and any other host that reads the standard. Nothing here is tied to one vendor.

## Skills

| Skill | What it does |
| --- | --- |
| [`macos-proxy-leak-audit`](skills/macos-proxy-leak-audit/SKILL.md) | Audits WebRTC and DNS leaks on macOS behind Clash Verge / TUN, traces where system DNS really comes from, and isolates the foreign browser without breaking domestic WebRTC. |

### [macos-proxy-leak-audit](skills/macos-proxy-leak-audit/SKILL.md)

Your proxy exit says Frankfurt, but a WebRTC test still shows your real address. This skill finds out why.

- Traces the true source of system DNS, including the `114.114.114.114` placeholder Clash Verge's TUN helper writes — which looks like a leak but usually is not
- Checks IPv6 bypass, scoped resolvers, TUN routes, and leftover PAC / WPAD configuration
- Explains why CN STUN servers can go `DIRECT` and expose your real IPv4, and isolates just the foreign browser (a Chrome profile with a WebRTC-restriction extension, or a Firefox profile with `media.peerconnection.enabled=false`) while keeping domestic WebRTC working
- Re-tests the proxy exit and the recursive resolver, and documents rollback before changing anything
- Read-only by default; every system or Clash change requires explicit confirmation

Bundled: a read-only audit script, a forensics command reference, and a Clash Verge DNS/TUN model.

## Install

### Any agent (skills CLI)

```bash
npx skills add real-jacket/skills
```

Pick the skills and agents interactively, or install one directly:

```bash
npx skills add real-jacket/skills --skill macos-proxy-leak-audit -a claude-code
```

Add `-g` to install for all projects instead of the current one.

### Claude Code (plugin marketplace)

```bash
/plugin marketplace add real-jacket/skills
/plugin install macos-proxy-leak-audit@jacket-skills
```

### Manually

Copy or symlink a skill directory into your agent's skills directory:

```bash
cp -R skills/macos-proxy-leak-audit <your-agent-skills-dir>/
```

The exact path is host-specific and deliberately not hardcoded here. Back up any existing copy first.

## How a skill is laid out

```text
skills/<skill-name>/
├── SKILL.md          # required: YAML frontmatter + instructions
├── references/       # optional: detail loaded only when needed
├── scripts/          # optional: deterministic helpers
└── assets/           # optional: files copied into the output
```

`SKILL.md` frontmatter carries `name` (lowercase kebab-case, matching the directory) and `description` (what it does plus the exact phrases that should trigger it). Everything else is optional.

The design rule is progressive disclosure: only the `name` and `description` sit in the agent's context permanently. The body loads when the skill triggers, and `references/` loads only if the agent decides it needs it. That is why `SKILL.md` stays short and the detail lives in references.

## Repository layout

```text
skills/
├── .claude-plugin/
│   └── marketplace.json   # makes the repo installable as a plugin marketplace
├── .github/workflows/
│   └── validate.yml       # CI: validator + shellcheck
├── skills/
│   └── macos-proxy-leak-audit/
├── scripts/
│   └── validate-skills.mjs
├── template/
│   └── SKILL.md           # starting point for a new skill
├── LICENSE
├── README.md
└── README.zh-CN.md
```

## Adding a skill

1. Copy `template/` to `skills/<skill-name>/` and keep the directory name identical to the frontmatter `name`.
2. Add the entry to `.claude-plugin/marketplace.json`.
3. Validate before committing:

   ```bash
   node scripts/validate-skills.mjs
   ```

The validator checks that frontmatter parses, the name matches the directory, the description is long enough to trigger reliably, every `references/` and `scripts/` path mentioned in `SKILL.md` actually exists, bundled scripts are executable, and `marketplace.json` lists exactly the skills that exist. CI runs the same check plus `shellcheck` on every bundled shell script.

## Safety

- `skills/macos-proxy-leak-audit/scripts/audit-macos-leaks.sh` is read-only. It does not change network settings.
- Its output contains local network details. Review and redact before sharing.
- Any `networksetup -set*`, Clash config edit, or restart requires explicit confirmation — the skill instructs the agent to ask first.
- No personal public IPs, UUIDs, subscription URLs, or credentials are stored in this repository.

Review any skill before use: skills run with the permissions you give your agent.

## License

[MIT](LICENSE) © real-jacket
