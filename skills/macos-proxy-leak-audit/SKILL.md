---
name: macos-proxy-leak-audit
description: "在 macOS 上排查和修复 Clash Verge/TUN 场景的 WebRTC 与 DNS 泄漏：追溯系统 DNS 真实来源（含 114.114.114.114 占位地址）、IPv6 旁路、scoped resolver、PAC 残留、TUN 路由与 Clash DNS 上游，并复测代理出口和递归解析器。Use when users report WebRTC/DNS leaks, real IP exposure, DNS being rewritten, or ask where macOS DNS comes from under Clash/TUN."
---

# macOS Proxy Leak Audit

## Overview

Diagnose macOS proxy leaks in three independent layers: IPv6/WebRTC bypass, the source of system DNS, and the recursive resolver seen by the outside world. Start read-only, separate placeholders from real leaks, and verify each change against the proxy exit and resolver path.

## Safety and confirmation gates

- Start with read-only checks. Do not run `networksetup -set*`, edit Clash configs, quit/restart Clash, or use `sudo` until the user explicitly approves that category of change.
- Warn that quitting Clash removes TUN routes and briefly interrupts connectivity.
- Do not upload or paste configs, logs, or leak-test results to external services. Mask public IPs, UUIDs, SSIDs, subscription URLs, and proxy credentials.
- If a command fails or needs privileges you do not have, record `unknown`. Never infer a missing value.
- Do not modify system DNS when Clash is managing it; identify the source first.

## Step 1: Baseline collection

Run the read-only audit script from this skill:

```bash
bash scripts/audit-macos-leaks.sh
```

If the script cannot run, use the commands in `references/forensics-commands.md`. Do not skip `scutil --dns`: `dig` alone can miss the resolver path used by macOS applications.

Collect at minimum:

- active interface, network service name, and primary service UUID
- `scutil --proxy`, static proxy, PAC URL, automatic proxy discovery
- `scutil --dns`, `networksetup -getdnsservers`, DHCP-provided DNS
- IPv4/IPv6 default routes, TUN interfaces, global IPv6 addresses
- Clash Verge runtime config, DNS override file, `.original_dns` backups, recent DNS log lines

## Step 2: Triage

| Observation | Likely cause | Go to |
|---|---|---|
| Public IPv6 on the physical interface, IPv6 default via it, and `tun.ipv6`/`dns.ipv6` disabled | IPv6 bypasses TUN; WebRTC can expose it | Step 3A |
| WebRTC test shows only the proxy exit; no public host candidate | WebRTC path is contained | Verify in the user's browser |
| System DNS is `114.114.114.114`, `.original_dns` backup exists, logs show periodic `set system dns` | Clash Verge system-DNS placeholder | Step 4A |
| Same DNS but TUN is off or queries do not enter TUN | Real DNS exposure, not a placeholder | Step 3A / 4A |
| DNS test shows a domestic ISP resolver despite a foreign proxy exit | Clash DNS upstream or resolver policy | Step 4B |
| PAC URL or automatic proxy discovery is enabled without need | Leftover proxy configuration | Step 5 |

## Step 3: IPv6 and WebRTC

### 3A. Confirm the bypass

Check the runtime config and the host:

```bash
grep -nE '^[[:space:]]*(ipv6|dns-hijack|enable):' \
  "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml"
route -n get -inet6 default
ifconfig en0
```

A public IPv6 address is global unicast in `2000::/3`; `fe80::/10` is link-local and `fc00::/7` is ULA. TUN taking over IPv4 does not imply IPv6 is covered.

Two valid fixes, in order of simplicity:

1. Disable IPv6 on the active network service (simplest, but loses IPv6):
   ```bash
   sudo networksetup -setv6off "Wi-Fi"
   ```
   The GUI equivalent is System Settings > Network > Wi-Fi > Details > TCP/IP > Configure IPv6: Off. Roll back with `sudo networksetup -setv6automatic "Wi-Fi"`.
2. Enable IPv6 in Clash TUN and DNS, then verify IPv6 routes and DNS actually use the tunnel. This preserves IPv6 but is more complex; inspect the effective config and TUN stack before recommending it.

Do not disable IPv6 globally with `sysctl`; scope the change to the network service. Ask before either change, especially if the user relies on IPv6-only LAN services.

### 3B. Browser checks

- Disable Chrome Secure DNS / Firefox DoH / VPN extensions for the test, or pin them to the intended resolver.
- Test `https://browserleaks.com/webrtc` in the user's own browser. A built-in browser may have different policies.
- `No Leak` with only the proxy exit is success. A private LAN IPv4 candidate reveals the local subnet but is lower risk than a public IPv6 candidate.
- The proxy's own IPv6 exit address is not a leak.

### 3C. WebRTC: isolate the foreign browser

Why: CN STUN servers such as miwifi, bilibili, and hitv can match `GEOSITE,cn` / `GEOIP,CN` and go DIRECT, exposing the real CN IPv4 even when local IPv6 is off. A site's IPv6 may be the proxy's egress, not local IPv6. Any working WebRTC exposes some address, so a global STUN block or proxy also breaks or reroutes domestic WebRTC.

How:

- Chrome: create a separate profile for Claude/foreign sites and install a minimal WebRTC-restriction extension only there, such as WebRTC Leak Prevent; choose force-proxy or disable WebRTC. Keep domestic WebRTC in the normal profile or native apps.
- Firefox: create a separate profile for Claude/foreign sites and set `media.peerconnection.enabled=false` in `about:config`. Keep the domestic profile and other apps enabled.
- Do not add global STUN rules or set a Chrome-wide policy; both affect domestic WebRTC.
- Keep the existing IPv6-off, split-DNS, and PAC-off mitigations.

Verify in the Claude profile that a WebRTC test shows no real CN IPv4; verify a domestic call in the other browser or app still works.

## Step 4: DNS source and resolver

### 4A. Trace the system DNS source

```bash
scutil --dns
networksetup -getdnsservers "Wi-Fi"
ipconfig getpacket en0
scutil <<< 'show State:/Network/Global/IPv4'
ls -la "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/.original_dns"
grep -inE 'set system dns|unset system dns|DNS script task' \
  "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/logs/latest.log" | tail -20
```

Interpretation:

- A `.original_dns/<service-uuid>` backup whose content is `empty` means the service had no static DNS before Clash changed it; the real source was DHCP.
- If DHCP offered a LAN resolver but the service now has `114.114.114.114`, and logs show periodic `set system dns successfully`, the app is rewriting the value. Manual system-DNS edits will be overwritten.
- In the audited Clash Verge Rev environment, `114.114.114.114` was a hardcoded helper placeholder, not the recursive resolver. Verify this for the installed version with logs and, when available, strings from the app binary. Do not assume every version behaves identically.
- With TUN active and `dns-hijack: any:53`, queries sent to the placeholder should be intercepted and resolved by Clash. Confirm with fake-ip answers and routes.
- If `scutil --dns` shows a scoped resolver on the physical interface, or TUN is off, queries may leave outside the tunnel even though the system DNS looks normal.
- Do not rely only on `verge.yaml`'s DNS-override flag; it can disagree with actual behavior. Use backups, logs, `scutil --dns`, and the runtime config together.

If the placeholder is confirmed, do not change system DNS. Continue to examine the actual recursive resolver.

### 4B. Check the actual resolver

```bash
dig +short whoami.akamai.net
dig +short TXT whoami.ds.akahelp.net
dscacheutil -q host -a name example.com
```

- The Akamai probes echo the recursive resolver IP. Check its ASN and country; a domestic resolver paired with a foreign proxy exit is a DNS leak.
- `dscacheutil` exercises the macOS resolver path; `dig` may bypass mDNSResponder. Use both when possible.
- A fake-ip answer (commonly `198.18.0.0/15`) confirms Clash DNS interception, not a clean resolver.
- Use a browser DNS leak test such as `https://www.dnsleaktest.com/` (extended test) for browser behavior, with Secure DNS disabled.

Inspect the effective DNS upstreams:

```bash
grep -nE -A4 '^[[:space:]]*(nameserver|direct-nameserver|proxy-server-nameserver|fallback|respect-rules|dns-hijack):' \
  "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml"
```

Mixed domestic and foreign upstreams in `nameserver` can make proxied domains resolve through a domestic resolver. Split the paths: proxied domains through foreign DoH that follows proxy rules, direct/domestic domains through domestic DoH. See `references/clash-verge-dns.md` for a template and caveats.

Do not edit configs blindly:

1. Identify the effective file: `dns_config.yaml` applies only when DNS override is active; otherwise the profile or runtime config is authoritative.
2. Back up with a timestamp.
3. Quit Clash Verge gracefully; do not `kill -9`, or the helper may skip restoring system DNS.
4. Edit, validate YAML, and restart.
5. Confirm the runtime config and TUN came back before declaring success.

## Step 5: PAC and automatic proxy discovery

Record before changing:

```bash
scutil --proxy
networksetup -getautoproxyurl "Wi-Fi"
networksetup -getproxyautodiscovery "Wi-Fi"
```

If a leftover PAC/WPAD configuration is present and the user does not need it, get consent and disable it:

```bash
sudo networksetup -setautoproxystate "Wi-Fi" off
sudo networksetup -setproxyautodiscovery "Wi-Fi" off
```

Keep the static proxy (`127.0.0.1:<port>`) unchanged. Record the old PAC URL and discovery state first so they can be restored.

## Step 6: Verification

- IPv6: no global IPv6 on the physical interface, no IPv6 default route escaping the tunnel; WebRTC shows only the proxy exit.
- DNS: system DNS may still show `114.114.114.114` in TUN mode; that is expected if it is the placeholder. Confirm queries are hijacked, resolver probes show a resolver consistent with the proxy region, and no domestic ASN remains in the DNS leak test.
- Routing: TUN routes and system proxy are restored; normal sites and domestic direct sites load.
- Browser: re-test in the user's Chrome/Firefox because extensions, DoH, and enterprise policies can differ.
- Re-run `bash scripts/audit-macos-leaks.sh` and compare with the baseline.

## Step 7: Rollback

- Restore the timestamped DNS backup, quit and restart Clash, then re-check runtime config and connectivity.
- Re-enable IPv6 with `sudo networksetup -setv6automatic "Wi-Fi"`.
- Restore PAC/discovery only if the user needs it.
- If DNS is broken and Clash is not managing it, `sudo networksetup -setdnsservers "Wi-Fi" Empty` restores DHCP. If Clash is managing DNS, quit it gracefully and let `.original_dns` restore, then verify.
- Do not delete backups or `.original_dns` files.

## Interpretation rules

- `114.114.114.114` is not proof of a leak by itself.
- The proxy's IPv6 exit address is not a WebRTC leak.
- A private LAN WebRTC candidate is not a public-IP leak.
- `dig` alone does not describe the path used by macOS apps.
- A config flag does not prove actual behavior; check logs, backups, runtime config, and routes.
- `.original_dns` containing `empty` means DHCP, not "no DNS".
- Clash's upstream DNS is separate from the system DNS placeholder.

## Pitfalls

- Manual system DNS changes are overwritten while Clash manages DNS.
- Force-killing Clash can leave system DNS pointing at the placeholder; quit gracefully.
- Quitting Clash briefly disconnects the network and removes TUN routes.
- Chrome/Firefox Secure DNS and VPN extensions can bypass Clash entirely.
- Disabling IPv6 can break IPv6-only services; offer the TUN IPv6 alternative.
- Profile updates or subscription changes can overwrite DNS behavior; re-check after updates.
- `respect-rules` with an unreachable `proxy-server-nameserver` can break startup.
- File paths and key names differ across Clash Verge versions; read the installed files rather than assuming.

## Resources

- `scripts/audit-macos-leaks.sh` — read-only baseline and post-change audit.
- `references/forensics-commands.md` — command reference, output interpretation, and failure handling.
- `references/clash-verge-dns.md` — Clash Verge file model, placeholder behavior, split-DNS template, and change procedure.

## Suggested companion skills

These are follow-up scopes, not separate skills that exist yet. Keep this skill read-only and hand off to them when the user wants durable configuration changes:

- `clash-verge-split-dns-routing` — turn the DNS diagnosis into a persistent split-DNS setup: proxied domains through foreign DoH that follows proxy rules, direct/domestic domains through domestic DoH, with backup, rollback, and resolver verification. Reuse the template in `references/clash-verge-dns.md`.
- `clash-verge-cn-split-routing` — make CN split routing subscription-independent: use maintained CN data such as `GEOSITE,cn` / `GEOIP,CN` instead of hand-written domains, prepend those rules in the global extension script, keep proxy-only domains such as Anthropic/Claude ahead of them with a dynamically selected valid proxy group, and verify after profile switches.
