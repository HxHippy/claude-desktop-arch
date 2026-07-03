# Reproducible terminal demo for the README.
# Regenerate with:  vhs demo.tape   (run from the repo root)
# Records the no-sudo "verify + already up to date" fast path, which shows
# the full GPG signature / package-index trust chain.

Output assets/demo.gif
Require ./update-claude-desktop.sh

Set Shell bash
Set Theme "TokyoNight"
Set FontSize 17
Set Width 960
Set Height 320
Set Padding 22
Set TypingSpeed 55ms

# Clean, minimal prompt (hide the setup from the recording)
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
