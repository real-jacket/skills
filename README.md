# Personal Skills

A personal collection of reusable agent skills built around the portable `SKILL.md` convention. Each skill is self-contained and not tied to a specific agent.

## Skills

### macos-proxy-leak-audit

Audit WebRTC and DNS leaks on macOS with Clash Verge / TUN, and choose a browser-isolation strategy that keeps domestic WebRTC working.

- Trace the real source of system DNS, including the `114.114.114.114` placeholder
- Check IPv6 bypass, scoped resolvers, TUN routes, and PAC residue
- Detect CN STUN direct-connection leaks that expose the real CN IPv4
- WebRTC recommendation: isolate the foreign browser (Chrome profile + WebRTC restriction extension, or Firefox profile with `media.peerconnection.enabled=false`), keep domestic WebRTC direct
- Read-only by default; system or Clash changes require explicit confirmation

Entry point: [skills/macos-proxy-leak-audit/SKILL.md](skills/macos-proxy-leak-audit/SKILL.md)

## Compatibility

Each skill uses a standard `SKILL.md` entrypoint with YAML frontmatter and optional `scripts/` and `references/`. Install it into the skills directory of any agent that supports this convention; the exact path is host-specific and is not part of this repository.

## Install

Copy or symlink a skill directory into your agent skills directory:

```bash
cp -R skills/macos-proxy-leak-audit <your-agent-skills-dir>/
```

Back up an existing copy first.

## Repository layout

```text
personal-skills/
├── README.md
├── .gitignore
└── skills/
    └── macos-proxy-leak-audit/
        ├── SKILL.md
        ├── scripts/
        └── references/
```

## Safety

- `scripts/audit-macos-leaks.sh` is read-only and does not change network settings.
- Its output can contain local network details; redact before sharing.
- Any `networksetup -set*`, Clash config edit, or restart requires explicit confirmation.
- The repository contains no personal public IPs, UUIDs, subscription URLs, or credentials.

## License

Personal repository; no open-source license specified.
