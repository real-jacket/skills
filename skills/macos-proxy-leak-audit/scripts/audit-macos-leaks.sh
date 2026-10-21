#!/usr/bin/env bash
# Read-only audit. Every command here must remain non-mutating.
set -u
export LC_ALL=C

section() { printf '\n## %s\n' "$*"; }
note() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

run() {
  printf '\n$ %s\n' "$*"
  "$@" 2>&1 || printf '(command failed; value unknown)\n'
}

mask_uuid() {
  printf '%s' "${1:-}" | sed -E 's/^([0-9A-Fa-f]{8})-[0-9A-Fa-f-]{27}(.*)$/\1...\2/'
}

mask_global_v6() {
  awk '{
    if ($1 == "inet6" && ($2 ~ /^2[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:/ || $2 ~ /^3[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:/)) {
      split($2, a, ":")
      $2 = a[1] ":" a[2] ":****"
    }
    print
  }'
}

printf 'READ-ONLY macOS proxy/DNS audit - no changes are made.\n'
printf 'Output contains local network details; review before sharing.\n'

PRIMARY_IF=$(scutil <<< 'show State:/Network/Global/IPv4' 2>/dev/null | awk -F' : ' '/PrimaryInterface/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
SERVICE_UUID=$(scutil <<< 'show State:/Network/Global/IPv4' 2>/dev/null | awk -F' : ' '/PrimaryService/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
IFACE=${PRIMARY_IF:-}
if [ -z "$IFACE" ]; then
  IFACE=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')
fi
if [ -z "$IFACE" ]; then
  IFACE="en0"
  warn "Could not detect the primary interface; using en0."
fi

SERVICE=$(networksetup -listnetworkserviceorder 2>/dev/null | awk -v dev="$IFACE" '
  /^\([0-9]+\)/ { name=$0; sub(/^\([0-9]+\) /, "", name); next }
  $0 ~ ("Device: " dev "[,)]") { print name; exit }
')
if [ -z "$SERVICE" ]; then
  SERVICE=$(networksetup -listallnetworkservices 2>/dev/null | sed -n '2p')
  warn "Could not map $IFACE to a service name; using ${SERVICE:-Wi-Fi}."
fi
SERVICE=${SERVICE:-Wi-Fi}

CLASH_DIR="${CLASH_VERGE_DIR:-$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev}"

section "System"
printf 'macOS: %s (%s)\n' "$(sw_vers -productVersion 2>/dev/null || printf 'unknown')" "$(uname -m)"
printf 'Primary interface: %s\n' "$IFACE"
printf 'Network service: %s\n' "$SERVICE"
printf 'Primary service UUID: %s\n' "$(mask_uuid "${SERVICE_UUID:-unknown}")"

section "System proxy (scutil --proxy)"
scutil --proxy 2>&1 || warn "scutil --proxy failed."

section "Network service state"
run networksetup -getinfo "$SERVICE"
run networksetup -getdnsservers "$SERVICE"
run networksetup -getautoproxyurl "$SERVICE"
run networksetup -getproxyautodiscovery "$SERVICE"

section "DNS resolvers (scutil --dns)"
scutil --dns 2>&1 || warn "scutil --dns failed."

section "Default routes"
run route -n get default
run route -n get -inet6 default

section "IPv4 route table (first 30 lines)"
netstat -rn -f inet 2>&1 | sed -n '1,30p'

section "IPv6 route table (first 40 lines)"
netstat -rn -f inet6 2>&1 | sed -n '1,40p'

section "Primary interface $IFACE"
ifconfig "$IFACE" 2>&1 | grep -E 'flags=|status:|media:|inet |inet6 ' | mask_global_v6

section "TUN interfaces"
UTUNS=$(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep '^utun' || true)
if [ -z "$UTUNS" ]; then
  note "none"
else
  for u in $UTUNS; do
    printf '\n%s\n' "$u"
    ifconfig "$u" 2>&1 | grep -E 'flags=|inet |inet6 ' | mask_global_v6
  done
fi

section "DHCP (ipconfig getpacket $IFACE)"
DHCP_OUT=$(ipconfig getpacket "$IFACE" 2>&1) || true
if printf '%s\n' "$DHCP_OUT" | grep -qiE 'domain_name_server|router|yiaddr|subnet_mask'; then
  printf '%s\n' "$DHCP_OUT" | grep -iE 'domain_name_server|router|yiaddr|subnet_mask|server_identifier'
else
  warn "DHCP data unavailable (may require admin); DNS source unknown."
fi

section "Clash Verge directory"
if [ ! -d "$CLASH_DIR" ]; then
  note "not found: $CLASH_DIR"
  note "Set CLASH_VERGE_DIR if the app uses another path."
else
  printf '%s\n' "$CLASH_DIR"
  ls -1 "$CLASH_DIR" 2>/dev/null | sed -n '1,40p'

  for f in clash-verge.yaml verge.yaml dns_config.yaml; do
    path="$CLASH_DIR/$f"
    [ -f "$path" ] || continue
    printf '\n--- %s (DNS/TUN keys)\n' "$f"
    {
      grep -nE '^[[:space:]]*(ipv6|enable|stack|dns-hijack|respect-rules|nameserver|direct-nameserver|proxy-server-nameserver|fallback|enhanced-mode|fake-ip-range|dns-override|dns_override|enable_dns_settings|enable_tun_mode|tun_mode)[[:space:]]*:' "$path"
      grep -nE -A3 '^[[:space:]]*(nameserver|direct-nameserver|proxy-server-nameserver|fallback):' "$path"
    } | head -n 80
  done

  printf '\n--- .original_dns backups\n'
  if [ -d "$CLASH_DIR/.original_dns" ]; then
    found=0
    for f in "$CLASH_DIR/.original_dns"/*; do
      [ -f "$f" ] || continue
      found=1
      base=$(basename "$f")
      content=$(head -c 200 "$f" 2>/dev/null | tr '\n' ' ')
      printf '%s = %s\n' "$(mask_uuid "$base")" "${content:-<empty file>}"
    done
    [ "$found" -eq 1 ] || note "directory is empty"
  else
    note "no .original_dns directory"
  fi

  printf '\n--- recent DNS-related log lines\n'
  if [ -f "$CLASH_DIR/logs/latest.log" ]; then
    grep -inE 'set system dns|unset system dns|DNS script task|dns.*(fail|error)' "$CLASH_DIR/logs/latest.log" | tail -n 20
  else
    note "latest.log not found"
  fi

  printf '\n--- placeholder string check\n'
  if command -v strings >/dev/null 2>&1; then
    APP="/Applications/Clash Verge.app"
    found_bin=0
    if [ -d "$APP/Contents/MacOS" ]; then
      for bin in "$APP"/Contents/MacOS/*; do
        [ -f "$bin" ] || continue
        hits=$(strings -a "$bin" 2>/dev/null | grep -n -C1 '114\.114\.114\.114' | head -n 12)
        if [ -n "$hits" ]; then
          found_bin=1
          printf '%s\n' "$(basename "$bin")"
          printf '%s\n' "$hits"
        fi
      done
    fi
    [ "$found_bin" -eq 1 ] || note "no 114.114.114.114 constant found (version may differ)"
  else
    warn "strings not available; skip binary placeholder check."
  fi
fi

section "Summary"
GLOBAL_V6=no
if ifconfig "$IFACE" 2>/dev/null | awk '$1 == "inet6" && ($2 ~ /^2[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:/ || $2 ~ /^3[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:/) { found=1 } END { exit !found }'; then
  GLOBAL_V6=yes
fi
DNS_SERVERS=$(networksetup -getdnsservers "$SERVICE" 2>/dev/null | tr '\n' ' ')
if printf '%s' "$DNS_SERVERS" | grep -qi "aren't any"; then
  DNS_SERVERS="none (DHCP)"
fi
PAC_URL=$(networksetup -getautoproxyurl "$SERVICE" 2>/dev/null | sed -n 's/^URL: //p')
DISCOVERY=$(networksetup -getproxyautodiscovery "$SERVICE" 2>/dev/null)
TUN_COUNT=$(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -c '^utun' || true)
TUN_V6_ROUTES=$(netstat -rn -f inet6 2>/dev/null | grep -c 'utun' || true)

printf 'Global IPv6 on %s: %s\n' "$IFACE" "$GLOBAL_V6"
printf 'System DNS: %s\n' "${DNS_SERVERS:-none}"
printf 'PAC URL: %s\n' "${PAC_URL:-none}"
printf 'Auto proxy discovery: %s\n' "${DISCOVERY:-unknown}"
printf 'TUN interfaces: %s\n' "$TUN_COUNT"
printf 'IPv6 routes through utun: %s\n' "$TUN_V6_ROUTES"
if [ -f "$CLASH_DIR/logs/latest.log" ]; then
  printf 'set system dns log entries: %s\n' "$(grep -c 'set system dns' "$CLASH_DIR/logs/latest.log" 2>/dev/null || true)"
fi
note "No external leak tests were run. Use the browser and resolver probes in SKILL.md."
note "Read-only audit complete. Apply fixes only with explicit user approval."
