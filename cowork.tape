# Reproducible "Cowork setup" demo.
# Regenerate with:  sudo -v && vhs cowork.tape   (from the repo root)
# (sudo is pre-authorised so the symlink step doesn't prompt mid-recording;
#  no password is stored here.)

Output assets/cowork.gif
Require ./setup-cowork.sh

Set Shell bash
Set Theme "TokyoNight"
Set FontSize 16
Set Width 1000
Set Height 540
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
Type "./setup-cowork.sh"
Sleep 400ms
Enter
Sleep 6s
