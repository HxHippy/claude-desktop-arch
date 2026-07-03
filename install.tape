# Reproducible "standard install" demo.
# Regenerate with:  sudo -v && vhs install.tape   (from the repo root)
# (sudo is pre-authorised so the install step doesn't prompt mid-recording;
#  no password is stored here. Stage a fresh install first:
#  sudo rm -rf /opt/claude-desktop)
#
# NOTE: this run is long enough to exceed LinkedIn's 400-frame GIF cap, so the
# committed assets/install.gif is downsampled to 15 fps afterwards (crisp for a
# terminal, ~245 frames). Reproduce that step with:
#   ffmpeg -y -i assets/install.gif -vf "fps=15,palettegen=stats_mode=full" /tmp/p.png
#   ffmpeg -y -i assets/install.gif -i /tmp/p.png \
#     -lavfi "fps=15[x];[x][1:v]paletteuse=dither=none" assets/install.gif

Output assets/install.gif
Require ./update-claude-desktop.sh

Set Shell bash
Set Theme "TokyoNight"
Set FontSize 16
Set Width 1000
Set Height 470
Set Padding 22
Set Framerate 12
Set TypingSpeed 55ms

Hide
Type "export PS1='$ '"
Enter
Type "clear"
Enter
Show

Sleep 600ms
Type "./update-claude-desktop.sh"
Sleep 400ms
Enter
Sleep 14s
