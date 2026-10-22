#===============================================================================
# SCOPE-02 – PIF fix: a choice list next to a message stays on screen
# (2026-10-22)
# pbPositionNearMsgWindow (007/002_MessageConfig.rb) puts the list above the
# message, else below, else above again. A speech bubble message sits near
# the speaker, often mid-screen, so a long list (the Cinnabar Lab fossil
# choice with many fossils) fits on neither side and ended up above the top
# of the screen with only its bottom edge showing (Doragon). Now, when the
# list would leave the screen, it goes on the side with more room and is cut
# to that height (the list scrolls).
#===============================================================================
alias kif_cs_pbPositionNearMsgWindow pbPositionNearMsgWindow unless defined?(kif_cs_pbPositionNearMsgWindow)

def pbPositionNearMsgWindow(cmdwindow, msgwindow, side, x_offset = nil, y_offset = nil)
  kif_cs_pbPositionNearMsgWindow(cmdwindow, msgwindow, side, x_offset, y_offset)
  return if !cmdwindow || !msgwindow
  return if cmdwindow.y >= 0 && cmdwindow.y + cmdwindow.height <= Graphics.height
  above = msgwindow.y
  below = Graphics.height - (msgwindow.y + msgwindow.height)
  if [above, below].max >= 64 # room for at least one row
    if below > above
      cmdwindow.height = [cmdwindow.height, below].min
      cmdwindow.y = msgwindow.y + msgwindow.height
    else
      cmdwindow.height = [cmdwindow.height, above].min
      cmdwindow.y = msgwindow.y - cmdwindow.height
    end
  else
    cmdwindow.height = [cmdwindow.height, Graphics.height].min
    cmdwindow.y = [[cmdwindow.y, 0].max, Graphics.height - cmdwindow.height].min
  end
end
