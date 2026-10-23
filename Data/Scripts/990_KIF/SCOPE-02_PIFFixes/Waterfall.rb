#===============================================================================
# SCOPE-02 – PIF fix: waterfalls can be climbed again (2026-10-23)
# PIF 6.8.2 commented out the action handler that asks "It's a large
# waterfall. Would you like to use Waterfall?" (012_Overworld/
# 004_Overworld_FieldMoves.rb), and no map event calls pbWaterfall, so
# pressing the confirm key at a waterfall did nothing: neither the HM nor the
# Jetpack worked (only the party menu's Waterfall did). KIF 0.20.7 and PIF
# 6.4.5 had this handler; it's back as it was there. pbWaterfall itself (badge,
# move or Jetpack, Quick HMs) is 6.8.2's.
#===============================================================================
Events.onAction += proc { |_sender, _e|
  terrain = $game_player.pbFacingTerrainTag
  if terrain.waterfall
    pbWaterfall
  elsif terrain.waterfall_crest
    pbMessage(_INTL("A wall of water is crashing down with a mighty roar."))
  end
}
