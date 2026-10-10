#===============================================================================
# SCOPE-02 – Luvdisc gift on every playthrough (tester request, 2026-10-10)
#   The deliveryman in the PokéMart (map 81, event 28) gives a Luvdisc once
#   you have the Pokédex (switch 988) - but PIF also needs switch 972, which
#   the intro sets only when a save file already existed (a 2nd playthrough).
#   KIF drops that second condition, so every game gets the gift.
#   (Luvdisc is also wild in the Sevii and Pinkan waters.)
#===============================================================================
KIF::MapPatches.add(81, "Luvdisc gift on every playthrough") do |map|
  ev = map.events[28]
  pg = ev && ev.pages[0]
  if pg && pg.condition.switch2_valid && pg.condition.switch2_id == 972 &&
     pg.list.any? { |c| c.code == 355 && c.parameters[0].to_s.include?("LUVDISC") }
    pg.condition.switch2_valid = false
  else
    KIF.log("Luvdisc gift: map 81 event 28 is not the expected event; left as it is")
  end
end
