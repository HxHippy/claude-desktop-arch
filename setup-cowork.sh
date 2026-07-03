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

command -v pacman >/dev/null 2>&1 || { echo "This script targets Arch Linux (pacman not found)." >&2; exit 1; }

PKGS=(qemu-system-x86 edk2-ovmf virtiofsd)
missing=()
for p in "${PKGS[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if (( ${#missing[@]} )); then
  echo ">> Installing missing packages: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
else
  echo ">> All Cowork packages already installed."
fi

# --- locate the real Arch paths (discover, don't hardcode filenames) --------
QEMU="$(command -v qemu-system-x86_64 || true)"
[[ -n "$QEMU" ]] || { echo "qemu-system-x86_64 not on PATH after install." >&2; exit 1; }

# Prefer the 4M split firmware; fall back to any OVMF_CODE the package ships.
OVMF_CODE="$(ls -1 /usr/share/edk2/x64/OVMF_CODE.4m.fd \
                   /usr/share/edk2/x64/OVMF_CODE.fd 2>/dev/null | head -n1 || true)"
[[ -n "$OVMF_CODE" ]] || { echo "OVMF_CODE firmware not found under /usr/share/edk2/x64/." >&2; exit 1; }
# The VARS template sits next to CODE with CODE->VARS in the name.
OVMF_VARS="${OVMF_CODE/OVMF_CODE/OVMF_VARS}"
[[ -r "$OVMF_VARS" ]] || { echo "OVMF_VARS template not found ($OVMF_VARS)." >&2; exit 1; }

VIRTIOFSD="$(command -v virtiofsd || true)"
[[ -n "$VIRTIOFSD" && -x "$VIRTIOFSD" ]] || VIRTIOFSD=/usr/lib/virtiofsd
[[ -x "$VIRTIOFSD" ]] || { echo "virtiofsd binary not found." >&2; exit 1; }

echo ">> Discovered:"
echo "     qemu      $QEMU"
echo "     OVMF CODE $OVMF_CODE"
echo "     OVMF VARS $OVMF_VARS"
echo "     virtiofsd $VIRTIOFSD"

# --- bridge to the paths the app probes -------------------------------------
echo ">> Creating compatibility symlinks (needs sudo) ..."
sudo bash -euc '
  OVMF_CODE="'"$OVMF_CODE"'"; OVMF_VARS="'"$OVMF_VARS"'"; VIRTIOFSD="'"$VIRTIOFSD"'"
  install -d /usr/share/OVMF /usr/libexec
  ln -sfn "$OVMF_CODE" /usr/share/OVMF/OVMF_CODE_4M.fd
  ln -sfn "$OVMF_VARS" /usr/share/OVMF/OVMF_VARS_4M.fd
  ln -sfn "$VIRTIOFSD" /usr/libexec/virtiofsd
'

# --- report readiness -------------------------------------------------------
ok=1
check() { if eval "$2"; then printf "   OK    %s\n" "$1"; else printf "   FAIL  %s\n" "$1"; ok=0; fi; }
echo ">> Readiness:"
check "qemu-system-x86_64"                 '[[ -x "$QEMU" ]]'
check "/usr/share/OVMF/OVMF_CODE_4M.fd"    '[[ -r /usr/share/OVMF/OVMF_CODE_4M.fd ]]'
check "/usr/share/OVMF/OVMF_VARS_4M.fd"    '[[ -r /usr/share/OVMF/OVMF_VARS_4M.fd ]]'
check "/usr/libexec/virtiofsd"             '[[ -x /usr/libexec/virtiofsd ]]'
check "/dev/kvm present"                   '[[ -e /dev/kvm ]]'
check "/dev/kvm writable by you"           '[[ -w /dev/kvm ]]'
check "member of kvm group"                'id -nG | tr " " "\n" | grep -qx kvm'

if [[ ! -w /dev/kvm ]] || ! id -nG | tr ' ' '\n' | grep -qx kvm; then
  echo
  echo "NOTE: KVM acceleration needs access to /dev/kvm. Add yourself to the"
  echo "      kvm group and re-login:  sudo usermod -aG kvm \"\$USER\""
fi

echo
if (( ok )); then
  echo ">> Cowork prerequisites satisfied. Restart Claude Desktop:"
  echo "     pkill -f /opt/claude-desktop/claude-desktop; claude-desktop"
else
  echo ">> Some checks failed -- see FAIL lines above."
  exit 1
fi
