#!/usr/bin/env bash
#
# update-claude-desktop.sh
#
# Installs / updates Claude Desktop on Arch (or any non-Debian distro) from
# Anthropic's OFFICIAL, GPG-SIGNED apt repository, without dpkg.
#
# Trust chain (apt-equivalent, strongest to weakest link):
#   embedded Anthropic key (fingerprint-pinned)
#     -> verifies the repo's signed InRelease
#       -> which carries the SHA256 of the Packages index
#         -> which carries the SHA256 of the .deb
# So a tampered mirror, MITM, or swapped key is rejected before anything
# touches your system. SHA256-only (no signature) is NOT trusted here.
#
# It then:
#   * extracts the .deb (ar + tar) to /opt/claude-desktop, root-owned
#   * restores setuid-root on chrome-sandbox (LAST, after chown)
#   * installs a launcher WRAPPER (not a symlink) forcing the
#     gnome-libsecret password backend so sign-in persists on
#     non-GNOME/KDE sessions (Hyprland, COSMIC, sway, ...)
#   * installs the .desktop entry and icons
#
# Re-run any time to upgrade. Idempotent. Use --force to reinstall current.
#
# Usage:  update-claude-desktop.sh [--force]
#
set -euo pipefail

REPO="https://downloads.claude.ai/claude-desktop/apt/stable"
DEST="/opt/claude-desktop"
BIN="/usr/local/bin/claude-desktop"
APPDIR="/usr/local/share/applications"
ICONROOT="/usr/local/share/icons/hicolor"

# Trust anchor. This is the real root of trust — audit it once against
# Anthropic's published fingerprint, then the embedded key below is checked
# against it on every run.
#   Anthropic Claude Code Release Signing <security@anthropic.com>
EXPECT_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

case "$(uname -m)" in
  x86_64)        ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }; }
need curl; need ar; need tar; need sha256sum; need gpg; need awk

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- embedded Anthropic signing key ----------------------------------------
cat > "$TMP/anthropic.asc" <<'ANTHROPIC_KEY_EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGnK73ABEACnbytJXkjweYrwIr0aLEFRlH+C0nF44KxFc7gQmJ6PjSPMGZAD
dxZcaixU7zZl8WxEpVO0wLmIH8cf2zGOdyuZg1Yaugk1vHb2b8WBhAGCQJdPgB8W
XquedepEYtk56uP/gCoTjJDUZluEGBHnlnuujSJ4orxEdhSykEoAUfJZGEILPpMd
bphFt/Sn+Eb/TxM5jpKPdwnv8AShNF/1mZU1fWTQq9tRKJUakZj04gdaDFElQXak
CtTij+GT6yoYCARSHwGO+PC/Pr6q4tc+D7LRjxSBvUWDoFSmlqb/PJ1hj9D/7I2O
e4XXniAPWMR56KvxHlzOzrNQdJujbJdSkCwh1ZijkSd3y8ayW5WYUTGdRab99NUw
agzlabe/VVF6kzJ0Scn5q3PihB2Y9Bwo0CKnkYk7a7KT77EWv0Kkq+VHmOtqX3a2
hhX+b6a6ve9rzJ1qZYGj+obv/C3Sx1LzUjAfqVy7RJDf2uAoP5t2g8u/TkSpUxhM
VEjZBkSxYZhMyzQM6t8IgkUfnSrIPTHixbDWARZ4beMOBjxyPZK1nP7OOrNR3TkK
JtwLMQAabURCDnL0PjS0iwBTU4jtumBD1XSULyWuoTvMljrpQr1nV1oDyOt0OLqa
KA2McWtd9PdXhC8y2EIg7TmrTlJLfHYbdmkiCYj4J49Q8HWkN/6WE+RTUwARAQAB
tD5BbnRocm9waWMgQ2xhdWRlIENvZGUgUmVsZWFzZSBTaWduaW5nIDxzZWN1cml0
eUBhbnRocm9waWMuY29tPokCUQQTAQoAOxYhBDHd3iTd+rZ59C170rqpKf8afsrO
BQJpyu9wAhsPBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJELqpKf8afsrO
l5IP/2I8X1dFy5xYczWB/coIxGjuzS/V6ByZGZZEJsbr04pmuHiFUykJqPGWGQ6q
U0YF5iEwvEkaagS5m7DzhSEf3FM3Cgafax/6d70tar9Vr1D+w6uPfxetu7u/WYJp
aolIsdh5fTrBh9zSM1Njl8FM8wG8CwZQjS33Oa7d8cwRkgdUWbt6LXgz+cTQNuBn
BgW6Ks7oZFI25dfu0ojDR+aDFJg4+4wZoyDLPvJz1SIrJ5WFGs67zsx9SfS3yZnf
XKmBe+f0dUy+GJ2nFZrXFf99+c0dPEHYO8DCeAHZizjkFrdYtUHdDU0YDYEGkLJa
bE+pgcpkHf5EvsZzHsyDbl95W/eh7pcXMbwkN+W4CBYUE9X4uHhqzWaC5yAVRWUA
1BJ9V4LjZfHPLEJt0I3TxzXiEg9/BVeaTYq9RjaxIFo9Nfk158HqJY6SA5jslBlx
Gv/No8u+xVcze2UJyGVfEIUfm92+0UAIkny3+5cuVV0ICzJxXlXj0CnLM9Lt50wE
p3suVwuBEviCbZ08eAH1Ht8gbBdSsiOkIU8CX3v/scwHHx5q0+NBL6xLrQObg13a
tRXBlKObfElkPN3lTUbUnJOW4U8uSjH8VRP+AujKWMDFe7x0zCs+iYY1mTOvbrTS
9n3CmZUmbynZ+E/QWNENpW/pDNZdWFy43PASmML5FHu4m9Sn
=oqMI
-----END PGP PUBLIC KEY BLOCK-----
ANTHROPIC_KEY_EOF

# --- import key into an ephemeral keyring and pin its fingerprint -----------
export GNUPGHOME="$TMP/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
gpg --quiet --import "$TMP/anthropic.asc" 2>/dev/null
GOT_FPR="$(gpg --with-colons --fingerprint 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')"
if [[ "$GOT_FPR" != "$EXPECT_FPR" ]]; then
  echo "FATAL: embedded key fingerprint mismatch." >&2
  echo "  got:      $GOT_FPR" >&2
  echo "  expected: $EXPECT_FPR" >&2
  exit 1
fi

# --- verify the signed InRelease with ONLY that key -------------------------
echo ">> Verifying repository signature ..."
curl -fsSL "$REPO/dists/stable/InRelease" -o "$TMP/InRelease"
if ! gpg --batch --status-fd 3 --decrypt "$TMP/InRelease" \
        3>"$TMP/gpgstatus" >"$TMP/Release" 2>/dev/null \
   || ! grep -q '^\[GNUPG:\] VALIDSIG' "$TMP/gpgstatus"; then
  echo "FATAL: InRelease signature did not verify against Anthropic's key." >&2
  exit 1
fi
echo "   InRelease signature OK"

# --- pull the SHA256 of the Packages index from the SIGNED Release ----------
PKG_PATH="main/binary-$ARCH/Packages"
read -r PKG_SHA PKG_SIZE < <(
  awk -v p="$PKG_PATH" '$3==p && length($1)==64 {print $1, $2; exit}' "$TMP/Release"
) || true
[[ -n "${PKG_SHA:-}" ]] || { echo "FATAL: $PKG_PATH not found in signed Release." >&2; exit 1; }

echo ">> Fetching + verifying package index ..."
curl -fsSL "$REPO/dists/stable/$PKG_PATH" -o "$TMP/Packages"
echo "$PKG_SHA  $TMP/Packages" | sha256sum -c - >/dev/null \
  || { echo "FATAL: Packages index hash does not match signed Release." >&2; exit 1; }
echo "   Packages index authenticated"

# --- pick the newest version and its .deb hash from the trusted index -------
read -r VERSION FILENAME SHA256 < <(
  awk -v RS='' '
    { ver=""; fn=""; sha=""
      n=split($0, L, "\n")
      for (i=1;i<=n;i++) {
        if (L[i] ~ /^Version: /)  { ver=L[i]; sub(/^Version: /,"",ver) }
        if (L[i] ~ /^Filename: /) { fn=L[i];  sub(/^Filename: /,"",fn) }
        if (L[i] ~ /^SHA256: /)   { sha=L[i]; sub(/^SHA256: /,"",sha) }
      }
      if (ver!="") print ver "\t" fn "\t" sha
    }' "$TMP/Packages" \
  | sort -V | tail -n1 | awk -F'\t' '{print $1, $2, $3}'
) || true
[[ -n "${VERSION:-}" && -n "${FILENAME:-}" && -n "${SHA256:-}" ]] \
  || { echo "FATAL: could not parse latest version from index." >&2; exit 1; }

# Sanitise fields before they ever reach a shell / sudo context. The character
# classes deliberately exclude quotes, $, backtick, backslash, and whitespace,
# so a hostile index cannot break out of the double-quoted sudo assignment.
# A Debian revision suffix (-N) is allowed; everything else is refused.
[[ "$VERSION"  =~ ^[0-9][0-9A-Za-z.+~]*(-[0-9A-Za-z.+~]+)?$ ]] || { echo "FATAL: refusing suspicious version '$VERSION'." >&2; exit 1; }
[[ "$SHA256"   =~ ^[0-9a-f]{64}$ ]]                 || { echo "FATAL: refusing suspicious sha256." >&2; exit 1; }
[[ "$FILENAME" =~ ^pool/[A-Za-z0-9._/+-]+\.deb$ ]]  || { echo "FATAL: refusing suspicious filename '$FILENAME'." >&2; exit 1; }

echo ">> Latest available: $VERSION"
STAMP="$DEST/.app-version"
INSTALLED="$(cat "$STAMP" 2>/dev/null || echo none)"
echo ">> Currently installed: $INSTALLED"
if [[ "$INSTALLED" == "$VERSION" && $FORCE -eq 0 ]]; then
  echo ">> Already up to date. Use --force to reinstall."
  exit 0
fi

DEB="$TMP/$(basename "$FILENAME")"
echo ">> Downloading $(basename "$FILENAME") ..."
curl -fSL -o "$DEB" "$REPO/$FILENAME"
echo ">> Verifying .deb SHA256 (chained to signed Release) ..."
echo "$SHA256  $DEB" | sha256sum -c - >/dev/null
echo "   OK"

echo ">> Extracting ..."
( cd "$TMP" && ar x "$DEB" && tar -xf data.tar.* )

if pgrep -f "$DEST/claude-desktop" >/dev/null 2>&1; then
  echo ">> Stopping running Claude Desktop ..."
  pkill -f "$DEST/claude-desktop" || true
  sleep 1
fi

echo ">> Installing to $DEST (needs sudo) ..."
sudo bash -euc '
  DEST="'"$DEST"'"; SRC="'"$TMP"'/usr"; VERSION="'"$VERSION"'"
  BIN="'"$BIN"'"; APPDIR="'"$APPDIR"'"; ICONROOT="'"$ICONROOT"'"

  rm -rf "$DEST"; mkdir -p "$DEST"
  cp -a "$SRC/lib/claude-desktop/." "$DEST/"
  chown -R root:root "$DEST"
  # setuid MUST be set AFTER chown -- chown clears the setuid bit.
  chmod 4755 "$DEST/chrome-sandbox"
  printf "%s\n" "$VERSION" > "$DEST/.app-version"

  # Launcher WRAPPER (not a symlink): forces the libsecret backend so sign-in
  # persists on non-GNOME/KDE sessions. Re-created every run on purpose.
  rm -f "$BIN"
  cat > "$BIN" <<EOF
#!/bin/sh
exec "$DEST/claude-desktop" --password-store=gnome-libsecret "\$@"
EOF
  chmod 0755 "$BIN"

  install -Dm644 "$SRC/share/applications/claude-desktop.desktop" \
    "$APPDIR/claude-desktop.desktop"
  for sz in 16 32 48 128 256; do
    install -Dm644 "$SRC/share/icons/hicolor/${sz}x${sz}/apps/claude-desktop.png" \
      "$ICONROOT/${sz}x${sz}/apps/claude-desktop.png"
  done
  update-desktop-database "$APPDIR" 2>/dev/null || true
  gtk-update-icon-cache -q "$ICONROOT" 2>/dev/null || true
'

SB="$(stat -c '%A %U:%G' "$DEST/chrome-sandbox")"
echo ">> chrome-sandbox: $SB"
[[ "$SB" == -rws* ]] || echo ">> WARNING: setuid bit missing on chrome-sandbox"
echo ">> Installed Claude Desktop $VERSION"
echo ">> Launch with: claude-desktop"
