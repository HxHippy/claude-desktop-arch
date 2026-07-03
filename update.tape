# Reproducible "update check" demo.
# Regenerate with:  vhs update.tape   (from the repo root)
# Shows the everyday case: re-running the updater verifies the GPG signature
# chain and reports it is already on the latest build. No sudo, no download.

Output assets/update.gif
Require ./update-claude-desktop.sh

Set Shell bash
Set Theme "TokyoNight"
Set FontSize 16
Set Width 1000
Set Height 300
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
Sleep 5s
