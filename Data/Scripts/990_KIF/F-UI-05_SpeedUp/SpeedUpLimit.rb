#===============================================================================
# F-UI-05 (part) – Speed-up limit for Toggle mode
# Source: KIF 0.20.7 "Speed-up Limit (Toggle)" (speeduplimit, 052_AddOns/Spped Up.rb)
#
# PIF 6.8.2 already has Hold/Toggle speed-up with 1-10x sliders for Hold, but
# Toggle cycles a fixed SPEEDUP_STAGES = [1, 2, 3]. KIF let Toggle go up to 10x.
# "Speed-up Limit (Toggle)" (global): Toggle cycles 1x .. Nx, N = 1..10
# (default 3 = PIF). Stored like PIF's own speed sliders (value - 1), so KIF's
# saved speeduplimit carries over (KIF default 4 -> 5x).
# The array is updated in place, so 052_InfiniteFusion/System/Spped Up.rb is
# untouched.
#===============================================================================
KIF::Options.define(:speeduplimit, 2, :global)

module KIF
  def self.sync_speedup_stages
    return unless defined?(SPEEDUP_STAGES) && $PokemonSystem
    limit = ($PokemonSystem.speeduplimit || 2) + 1
    limit = limit.clamp(1, 10)
    return if SPEEDUP_STAGES.length == limit
    SPEEDUP_STAGES.replace((1..limit).to_a)
    $GameSpeed = 0 if $GameSpeed.nil? || $GameSpeed >= SPEEDUP_STAGES.length
  end
end

KIF::Options.add(:others, :global) {
  SliderOption.new(_INTL("Speed-up Limit (Toggle)"), 1, 10, 1,
                   proc { $PokemonSystem.speeduplimit },
                   proc { |value|
                     $PokemonSystem.speeduplimit = value
                     KIF.sync_speedup_stages
                   }, _INTL("Sets the highest speed reached when speed-up is in Toggle mode (PIF: 3x)"))
}

class Scene_Map
  alias kif_speedup_update update unless method_defined?(:kif_speedup_update)

  def update
    KIF.sync_speedup_stages
    kif_speedup_update
  end
end
