#!/usr/bin/env bash
#
# setup-cowork.sh
#
# Makes Claude Desktop's "Cowork" feature work on Arch Linux.
#
# Cowork runs agent work inside a local QEMU/KVM virtual machine. The app
# probes a fixed set of Debian file paths for the VM tooling:
#
#   qemu-system-x86_64                    (on PATH)
#   /usr/share/OVMF/OVMF_CODE_4M.fd       (or OVMF_CODE.fd)   -- firmware
#   /usr/share/OVMF/OVMF_VARS_4M.fd       (derived: CODE->VARS) -- nvram template
#   /usr/libexec/virtiofsd  or  /usr/bin/virtiofsd            -- shared-fs daemon
#
# Arch ships the exact same components, just under different paths
# (/usr/share/edk2/x64/, /usr/lib/). This script installs the packages if
# needed and creates symlinks at the paths the app expects. The symlinks
# point at Arch package files, so they survive Claude Desktop upgrades.
#
# Nothing here weakens the VM isolation boundary -- it only points the app
# at Arch's official firmware and virtiofsd binary.
#
# Idempotent. Re-run any time. Requires: Arch (pacman), sudo.
#
set -euo pipefail

# Colour ONLY when stdout is a terminal -- never leak escape codes into pipes,
# redirects, or logs. When redirected, every variable below is empty.
if [[ -t 1 ]]; then
  B=$'\e[1;34m'; G=$'\e[1;32m'; Y=$'\e[0;33m'; R=$'\e[1;31m'; Z=$'\e[0m'
else
  B=''; G=''; Y=''; R=''; Z=''
fi
h()   { printf '%s>>%s %s\n' "$B" "$Z" "$*"; }          # step heading
die() { printf '%sFATAL:%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

command -v pacman >/dev/null 2>&1 || die "this script targets Arch Linux (pacman not found)."

PKGS=(qemu-system-x86 edk2-ovmf virtiofsd)
missing=()
for p in "${PKGS[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if (( ${#missing[@]} )); then
  h "Installing missing packages: ${Y}${missing[*]}${Z}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
else
  h "All Cowork packages already installed."
fi

# --- locate the real Arch paths (discover, don't hardcode filenames) --------
QEMU="$(command -v qemu-system-x86_64 || true)"
[[ -n "$QEMU" ]] || die "qemu-system-x86_64 not on PATH after install."

# Prefer the 4M split firmware; fall back to any OVMF_CODE the package ships.
OVMF_CODE="$(ls -1 /usr/share/edk2/x64/OVMF_CODE.4m.fd \
                   /usr/share/edk2/x64/OVMF_CODE.fd 2>/dev/null | head -n1 || true)"
[[ -n "$OVMF_CODE" ]] || die "OVMF_CODE firmware not found under /usr/share/edk2/x64/."
# The VARS template sits next to CODE with CODE->VARS in the name.
OVMF_VARS="${OVMF_CODE/OVMF_CODE/OVMF_VARS}"
[[ -r "$OVMF_VARS" ]] || die "OVMF_VARS template not found ($OVMF_VARS)."

VIRTIOFSD="$(command -v virtiofsd || true)"
[[ -n "$VIRTIOFSD" && -x "$VIRTIOFSD" ]] || VIRTIOFSD=/usr/lib/virtiofsd
[[ -x "$VIRTIOFSD" ]] || die "virtiofsd binary not found."

h "Discovered:"
printf '     %-10s %s%s%s\n' "qemu"      "$Y" "$QEMU"      "$Z"
printf '     %-10s %s%s%s\n' "OVMF CODE" "$Y" "$OVMF_CODE" "$Z"
printf '     %-10s %s%s%s\n' "OVMF VARS" "$Y" "$OVMF_VARS" "$Z"
printf '     %-10s %s%s%s\n' "virtiofsd" "$Y" "$VIRTIOFSD" "$Z"

# --- bridge to the paths the app probes -------------------------------------
h "Creating compatibility symlinks (needs sudo) ..."
sudo bash -euc '
  OVMF_CODE="'"$OVMF_CODE"'"; OVMF_VARS="'"$OVMF_VARS"'"; VIRTIOFSD="'"$VIRTIOFSD"'"
  install -d /usr/share/OVMF /usr/libexec
  ln -sfn "$OVMF_CODE" /usr/share/OVMF/OVMF_CODE_4M.fd
  ln -sfn "$OVMF_VARS" /usr/share/OVMF/OVMF_VARS_4M.fd
  ln -sfn "$VIRTIOFSD" /usr/libexec/virtiofsd
'

# --- report readiness -------------------------------------------------------
allok=1
check() {
  if eval "$2"; then printf '   %sOK%s    %s\n'   "$G" "$Z" "$1"
  else               printf '   %sFAIL%s  %s\n'   "$R" "$Z" "$1"; allok=0; fi
}
h "Readiness:"
check "qemu-system-x86_64"                 '[[ -x "$QEMU" ]]'
check "/usr/share/OVMF/OVMF_CODE_4M.fd"    '[[ -r /usr/share/OVMF/OVMF_CODE_4M.fd ]]'
check "/usr/share/OVMF/OVMF_VARS_4M.fd"    '[[ -r /usr/share/OVMF/OVMF_VARS_4M.fd ]]'
check "/usr/libexec/virtiofsd"             '[[ -x /usr/libexec/virtiofsd ]]'
check "/dev/kvm present"                   '[[ -e /dev/kvm ]]'
check "/dev/kvm writable by you"           '[[ -w /dev/kvm ]]'
check "member of kvm group"                'id -nG | tr " " "\n" | grep -qx kvm'

if [[ ! -w /dev/kvm ]] || ! id -nG | tr ' ' '\n' | grep -qx kvm; then
  printf '\n%sNOTE:%s KVM acceleration needs access to /dev/kvm. Add yourself to the\n' "$Y" "$Z"
  printf '      kvm group and re-login:  sudo usermod -aG kvm "$USER"\n'
fi

echo
if (( allok )); then
  h "Cowork prerequisites satisfied. Restart Claude Desktop:"
  printf '     %spkill -f /opt/claude-desktop/claude-desktop; claude-desktop%s\n' "$Y" "$Z"
else
  die "some checks failed -- see FAIL lines above."
fi
