#===============================================================================
# SCOPE-02 – Silph Co. 7F debug tile (2026-10-26)
#   Map 665 event 36, an invisible action-button event in the west wall at
#   (0,7): A at (1,7) turned off switches 228 "Giovanni-gone_silphco" and 222
#   "Saffron-giovanni" and turned on 825 "V 5.1", a developer reset left in
#   the map (PIF 6.4.5 had it too). Nothing else turns 228 off, so after
#   Silph Co. Giovanni, his Rockets and the Silph trainers came back.
#   Removed while it still holds exactly those commands (a later PIF fix is
#   left alone).
#===============================================================================
KIF::MapPatches.add(665, "PIF fix: Silph Co. 7F debug tile") do |map|
  ev = map.events[36]
  cmds = ev && ev.pages.length == 1 ? ev.pages[0].list.map { |c| [c.code, c.parameters] } : nil
  map.events.delete(36) if cmds == [[121, [228, 228, 1]], [121, [222, 222, 1]], [121, [825, 825, 0]], [0, []]]
end

# A save the tile already broke gets 228 back when it loads. 191 "ROCKET
# GONE - - SAFFRON" is set only after the Giovanni win (on every 11F, after
# 228), so 191 on with 228 off is that damage. 222 is left as it is: the
# 11F in use (map 757) turns it off after the win, and nothing reads it
# while 228 is on.
alias kif_silph_onLoadExistingGame onLoadExistingGame unless Object.method_defined?(:kif_silph_onLoadExistingGame) || Object.private_method_defined?(:kif_silph_onLoadExistingGame)

def onLoadExistingGame(*args)
  ret = kif_silph_onLoadExistingGame(*args)
  if $game_switches && $game_switches[191] && !$game_switches[228]
    $game_switches[228] = true
    $game_map.need_refresh = true if $game_map
    KIF.log("Silph Co.: switch 228 was off after Giovanni's defeat (7F debug tile); turned back on")
  end
  return ret
end
