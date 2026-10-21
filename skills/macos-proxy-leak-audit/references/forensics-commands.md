# macOS forensics command reference

Read-only commands for leak diagnosis. Do not add `sudo` unless a command explicitly needs it. If a command fails, record `unknown` and continue; do not guess the value.

## 1. Interface and network service

```bash
scutil <<< 'show State:/Network/Global/IPv4'
route -n get default
networksetup -listallnetworkservices
networksetup -listnetworkserviceorder
```

- `PrimaryInterface` is normally the physical interface (for example `en0`), even when TUN owns the default route.
- `PrimaryService` is a UUID. Clash Verge names its DNS backups after this UUID, so it can link a system-DNS value to a network service.
- Mapping an interface to a service name:

```bash
IFACE=en0
networksetup -listnetworkserviceorder | awk -v dev="$IFACE" '
  /^\([0-9]+\)/ { name=$0; sub(/^\([0-9]+\) /, "", name); next }
  $0 ~ ("Device: " dev "[,)]") { print name; exit }
'
```

Do not map a `utun` interface to a network service; it is not the service that owns system DNS.

## 2. Proxy state

```bash
scutil --proxy
networksetup -getautoproxyurl "Wi-Fi"
networksetup -getproxyautodiscovery "Wi-Fi"
```

`scutil --proxy` fields to read:

- `HTTPEnable`, `HTTPSEnable`, `HTTPProxy`, `HTTPPort`
- `ProxyAutoConfigEnable`, `ProxyAutoConfigURLString`
- `ProxyAutoDiscoveryEnable`

A local static proxy such as `127.0.0.1:7897` is normal. A PAC URL or enabled auto-discovery without an intentional PAC is residue.

## 3. DNS configuration and source

```bash
scutil --dns
networksetup -getdnsservers "Wi-Fi"
ipconfig getpacket en0
scutil <<< 'show State:/Network/Global/IPv4'
```

Read `scutil --dns` carefully:

- `resolver #1` is the default resolver.
- Additional resolvers with `if_index : ... (en0)` and `flags : Scoped` are per-interface resolvers. They can send queries out the physical interface and bypass TUN.
- `nameserver[0]` values are what the system resolver uses. They are not necessarily the recursive resolver seen by the internet.
- A DNS leak test result reflects the recursive resolver that fetched the final answer, not just the system DNS setting.

`ipconfig getpacket` fields:

- `domain_name_server` — DNS supplied by DHCP.
- `router` — gateway supplied by DHCP.
- `yiaddr` — address offered to the client.

If DHCP supplies a LAN resolver, the service currently shows a different value, and a `.original_dns` backup exists, something wrote the current value after DHCP.

## 4. Clash Verge evidence

Default directory:

```bash
CLASH_DIR="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
ls -la "$CLASH_DIR"
ls -la "$CLASH_DIR/.original_dns"
```

Relevant files:

- `clash-verge.yaml` — generated runtime config. This is what the core runs.
- `dns_config.yaml` — DNS override file, if the DNS override feature is active.
- `verge.yaml` — app settings, including TUN/system-proxy/DNS-override flags.
- `logs/latest.log` — runtime events.
- `.original_dns/<service-uuid>` — previous system DNS per service. Content `empty` means no static DNS was set.

Inspect only relevant keys to avoid dumping proxy credentials or subscription URLs:

```bash
grep -nE '^[[:space:]]*(ipv6|dns-hijack|respect-rules|nameserver|direct-nameserver|proxy-server-nameserver|fallback|enhanced-mode|fake-ip-range|dns-override|enable_dns_settings|tun_mode)[[:space:]]*:' "$CLASH_DIR/clash-verge.yaml"
grep -inE 'set system dns|unset system dns|DNS script task' "$CLASH_DIR/logs/latest.log" | tail -20
```

If available, check the app binaries for the placeholder constant:

```bash
strings -a "/Applications/Clash Verge.app/Contents/MacOS/clash-verge" | grep -n -C1 '114\.114\.114\.114'
```

`strings` may be unavailable or the binary name may differ by version. Treat a hit as supporting evidence, not proof of behavior; pair it with logs and observed system DNS.

## 5. Routes, TUN, and IPv6

```bash
route -n get default
route -n get -inet6 default
netstat -rn -f inet
netstat -rn -f inet6
ifconfig en0
ifconfig -l | tr ' ' '\n' | grep '^utun'
```

- IPv4 TUN takeover is visible as `default` and broad routes pointing at `utun*`.
- A global IPv6 address on the physical interface plus an IPv6 default route via that interface is a bypass if TUN carries only IPv4.
- Check whether `utun*` has IPv6 addresses and whether IPv6 routes use it.
- `2000::/3` is global unicast. `fe80::/10` is link-local and `fc00::/7` is ULA; neither is a public address.
- WebRTC host candidates from a global IPv6 address are a real exposure. Private LAN IPv4 candidates reveal the local subnet but are lower risk.

## 6. Resolver probes

```bash
dig +short whoami.akamai.net
dig +short TXT whoami.ds.akahelp.net
dscacheutil -q host -a name example.com
```

- The Akamai probes echo the recursive resolver IP observed by Akamai. Check ASN and country.
- `dig` uses the resolver library and may skip the macOS mDNSResponder cache. `dscacheutil` exercises the system resolution path. Use both.
- Fake-ip answers confirm interception by Clash DNS; they do not prove a clean resolver.
- Browser leak tests (for example `https://www.dnsleaktest.com/`) are authoritative for browser traffic only after Secure DNS/DoH and VPN extensions are disabled.

## 7. Failure handling

- `ipconfig getpacket` may fail or require privileges on some versions. Report `unknown`; do not assume DHCP.
- `strings` and app-binary paths vary. If unavailable, skip the check.
- `scutil --dns` can contain private search domains and interface names. Redact before sharing.
- Do not use `kill -9` or `killall` to restart Clash; a graceful quit lets the helper restore system DNS.
- Do not run `networksetup -set*`, edit configs, or quit the proxy during diagnosis without explicit approval.

## 8. Redaction checklist

Before sharing output with another person or service, mask:

- public IPv4 and IPv6 addresses
- network service UUIDs
- Wi-Fi SSID/BSSID
- subscription URLs and proxy credentials
- resolver IPs if they identify the user's ISP or location

Keep RFC1918 addresses, `fe80::`, and ULA addresses only when needed for local troubleshooting. Public DoH provider addresses are generally safe.
