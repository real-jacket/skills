# Clash Verge DNS and TUN behavior

## File model

Paths below use the Clash Verge Rev application-support directory; confirm the actual path for the installed version.

- `clash-verge.yaml` — generated runtime configuration. Read this to see what the core actually runs.
- `dns_config.yaml` — DNS override configuration used by Clash Verge when the DNS override feature is active.
- `verge.yaml` — app settings, including TUN and DNS override flags.
- `logs/latest.log` — runtime events, including system DNS set/unset operations.
- `.original_dns/<service-uuid>` — prior system DNS for each network service. Content `empty` means the service had no static DNS before the override.

Precedence differs across versions. A toggle in `verge.yaml` or an edit in `dns_config.yaml` is not proof of the effective configuration; confirm against `clash-verge.yaml` after restart.

## The `114.114.114.114` placeholder

In the audited Clash Verge Rev environment, `114.114.114.114` was written by the TUN helper as a hardcoded system-DNS placeholder, not chosen as the recursive resolver. Supporting evidence:

- `.original_dns/<primary-service-uuid>` contained `empty`, while DHCP offered a LAN DNS server.
- `logs/latest.log` showed repeated `set system dns successfully` events at roughly 30-minute intervals.
- The app binary contained `114.114.114.114` alongside system-DNS error strings such as `set system dns failed` and `unset system dns failed`.

Consequences:

- Do not "fix" a suspected DNS leak by manually changing system DNS to `127.0.0.1` or another server while Clash manages it; the helper will rewrite it.
- In TUN mode with `dns-hijack: any:53`, queries sent to the placeholder enter TUN and are resolved by Clash. The placeholder is an entry point, not the final resolver.
- If a leak test reports `114.114.114.114` or a domestic ISP, first determine whether queries actually enter TUN. Check scoped resolvers on the physical interface, TUN status, routes, and `dns-hijack`.
- On graceful quit, the helper restores the `.original_dns` value. After a crash, restore manually if the system still points at the placeholder.
- Another Clash Verge version may use a different placeholder or behavior. Re-verify with logs, backups, and (when available) binary strings.

A prior diagnosis can be misleading if it only reads the DNS-override flag. In the audited session the flag appeared off while the system DNS was clearly being overridden. Treat logs, backups, `scutil --dns`, and runtime config as the evidence chain.

## DNS keys that matter

- `dns.enable` — runs Clash's DNS server.
- `dns.ipv6` — enables IPv6 DNS answers; keep false when TUN has no IPv6 path.
- `dns.nameserver` — default upstreams.
- `dns.direct-nameserver` — upstreams for DIRECT connections (Clash Meta core).
- `dns.proxy-server-nameserver` — upstreams used to resolve proxy server domains; must be reachable without the tunnel.
- `dns.respect-rules: true` — DNS queries follow routing rules; proxied domains are resolved through the proxy.
- `dns.dns-hijack: any:53` — captures port-53 queries entering TUN.
- `tun.enable` / `tun.ipv6` — TUN status and IPv6 coverage.

A domestic DoH server in `nameserver` can make a DNS leak test show a domestic recursive resolver even when the web traffic is proxied. The fix is to separate proxied-domain resolution from direct/domestic resolution.

## Split-DNS template

Illustrative only. Key names and support depend on the Clash core and Clash Verge version; validate before use.

```yaml
dns:
  enable: true
  ipv6: false
  respect-rules: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  direct-nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
  proxy-server-nameserver:
    - https://doh.pub/dns-query
```

Caveats:

- If proxy nodes use domain names, `proxy-server-nameserver` (or the version's equivalent bootstrap setting) must resolve without the proxy. Without it, startup can fail or loop.
- `respect-rules` changes which path DNS queries take; verify proxied domains still resolve and domestic sites remain fast.
- Do not paste the template into both `dns_config.yaml` and the profile. Edit the effective source only.
- After a profile update or subscription switch, re-check the runtime DNS because the configuration may be regenerated.

In the audited session, proxied names were moved to Cloudflare/Google DoH while direct names stayed on domestic DoH. After restart, the resolver observed externally was Cloudflare and matched the proxy exit region; the previous domestic resolver disappeared.

## Change procedure

1. Read the current runtime DNS and upstreams; record them.
2. Identify the effective file: `dns_config.yaml` only when DNS override is active, otherwise the profile or runtime source.
3. Back up with a timestamp, for example:
   ```bash
   cp -p "$CLASH_DIR/dns_config.yaml" "$CLASH_DIR/dns_config.yaml.bak-$(date +%Y%m%d-%H%M%S)"
   ```
4. Quit Clash Verge gracefully. Warn the user about the brief disconnect; do not force-kill it.
5. Edit the effective file and validate YAML indentation.
6. Start Clash Verge and wait for TUN and the system-DNS placeholder to return.
7. Verify the runtime config reflects the new DNS upstreams; check resolver probes, a browser DNS leak test, WebRTC, normal browsing, and a domestic direct site.
8. If DNS or connectivity breaks, quit Clash, restore the backup, restart, and verify. Restore system DNS from `.original_dns` or DHCP only if Clash is not managing it.

## Verification signals

- `scutil --dns` still shows the placeholder in TUN mode; that is expected, not a failure.
- `dig` returns fake-ip addresses for proxied domains, confirming interception.
- The Akamai resolver probe returns a foreign resolver consistent with the proxy region; no domestic ASN remains in the leak test.
- WebRTC shows only the proxy exit, with no public IPv6 host candidate.
- Domestic direct sites resolve and load normally.
- TUN interfaces and routes are restored after restart.

## Pitfalls

- Config flag versus actual behavior: use logs and backups.
- Subscription updates can regenerate DNS settings; re-check after updates.
- `respect-rules` with an unreachable bootstrap resolver can break proxy startup.
- Force-killing Clash can skip system-DNS restoration.
- Disabling IPv6 and enabling TUN IPv6 are different tradeoffs; choose with the user.
- Browser Secure DNS, Firefox DoH, and VPN extensions bypass Clash; disable them for tests.
- Leak-test sites observe real resolver and exit information; redact before sharing results.
