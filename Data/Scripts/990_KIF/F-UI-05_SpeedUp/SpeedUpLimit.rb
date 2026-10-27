#===============================================================================
# F-UI-05 (part) – Toggle speed-up steps up to each area's own speed
# Source: KIF 0.20.7 "Speed-up Limit (Toggle)" (speeduplimit, 052_AddOns/Spped Up.rb)
#
# PIF 6.8.2 has Hold/Toggle speed-up: Hold uses the "Speed-up (Overworld)" /
# "Speed-up (Battles)" sliders, Toggle cycles a fixed SPEEDUP_STAGES =
# [1, 2, 3]. KIF 0.20.7 added a "Speed-up Limit (Toggle)" slider (1-10x).
# Since 2026-10-27 (Cody's settings review) there is no separate limit:
# Toggle steps 1x .. the current area's slider (Overworld on the map,
# Battles in battle), then back to 1x. Hold is unchanged (holding = the
# area's slider). The picked speed comes back when the area allows it again
# (5x on the map -> the Battles cap in battle -> 5x again).
# Migration (once, global): a player in Toggle mode gets the old Toggle Limit
# on both area sliders, so their top speed doesn't change; speeduplimit is
# then -1. The array is updated in place, so 052's Spped Up.rb is untouched.
# The toggle key's controller button (RB) is in SpeedTitle.rb.
#===============================================================================
KIF::Options.define(:speeduplimit, 2, :global)

module KIF
  # the old Toggle Limit (stored as value - 1, like PIF's sliders) moves to
  # the area sliders for Toggle players
  def self.migrate_speeduplimit
    ps = $PokemonSystem
    old = ps.speeduplimit
    return if old.nil? || old.to_i < 0
    if ps.speedup == 1
      ps.speedup_speed = old.to_i
      ps.speedup_speed_battles = old.to_i
    end
    ps.speeduplimit = -1
  end

  # Toggle's top speed here: the area's slider (PIF stores value - 1)
  def self.speedup_cap
    return 3 if defined?(KIF::Modules) && !KIF::Modules.active?("F-UI-05_SpeedUp")   # PIF's 1x/2x/3x
    ps = $PokemonSystem
    v = ($game_temp && $game_temp.in_battle) ? ps.speedup_speed_battles : ps.speedup_speed
    v = Settings::DEFAULT_SPEED_UP_SPEED if v.nil?
    return (v.to_i + 1).clamp(1, 10)
  end

  # @speed_want: the step the player picked; an area with a lower cap shows
  # less, and the pick comes back where it fits again
  def self.sync_speedup_stages
    return unless defined?(SPEEDUP_STAGES) && $PokemonSystem
    migrate_speeduplimit
    limit = speedup_cap
    g = $GameSpeed.to_i
    @speed_want = g if @speed_want.nil? || g != @speed_shown   # a key press changed it
    SPEEDUP_STAGES.replace((1..limit).to_a) if SPEEDUP_STAGES.length != limit
    $GameSpeed = @speed_shown = [@speed_want, limit - 1].min
  end
end

# Before 052's Graphics.update reads SPEEDUP_STAGES[$GameSpeed] (map and battle)
module Graphics
  class << Graphics
    alias kif_speedcap_update update unless method_defined?(:kif_speedcap_update)
  end

  def self.update
    KIF.sync_speedup_stages rescue nil
    kif_speedcap_update
  end
end

# Module Off: back to PIF's three stages at once (not gated: watchers run anyway)
KIF::Modules.watch(:qol) { |_active| KIF.sync_speedup_stages } if defined?(KIF::Modules)
