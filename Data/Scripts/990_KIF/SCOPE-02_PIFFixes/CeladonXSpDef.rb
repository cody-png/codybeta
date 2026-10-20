#===============================================================================
# SCOPE-02 – Celadon Dept. Store X Sp. Def (2026-10-20)
#   The X-item clerk (map 433, event 4) lists :SPDEF, which isn't an item, so
#   PIF's lookup falls back to its placeholder "Thing" (P50, "Some kind of
#   object..."). It was meant to be X Sp. Def (:XSPDEF).
#===============================================================================
KIF::MapPatches.add(433, "Celadon Dept. Store sells X Sp. Def, not a Thing") do |map|
  ev = map.events[4]
  cmd = ev && ev.pages[0] && ev.pages[0].list.find { |c| [355, 655].include?(c.code) && c.parameters[0].to_s =~ /(?<![A-Z_]):SPDEF\b/ }
  if cmd
    cmd.parameters[0] = cmd.parameters[0].sub(/(?<![A-Z_]):SPDEF\b/, ":XSPDEF")
  else
    KIF.log("Celadon X Sp. Def: map 433 event 4 is not the expected shop; left as it is")
  end
end
