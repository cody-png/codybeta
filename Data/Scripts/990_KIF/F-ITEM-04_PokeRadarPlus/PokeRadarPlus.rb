#===============================================================================
# F-ITEM-04 – PokéRadar+ (and KIF's Poké Radar changes)
# Source: KIF 0.20.7 013_Items/005_Item_PokeRadar.rb
#   :47, :331-333 autorepel (Repel doesn't run down while the radar is on)
#   :157-159 "Chain count: N" (PokeRadar+)
#   :185-187 radar shiny chance uses the Wild Shiny Odds setting (shinyodds)
#   :198-203 "Nothing happened... PokeRadar+ saved the chain!" (PokeRadar+)
#   :278 a chain never breaks on shaking grass (PokeRadar+)
#   016_UI/015_UI_Options.rb:2826-2830 option "PokeRadar+" (Others, Off)
#
# PokeRadar+ On: the chain count is shown each time the grass shakes, chains
#   don't randomly drop when you step into shaking grass, and a radar use with
#   no shaking grass keeps the chain.
# Always (as in KIF): while the radar is active your Repel steps don't run
#   down, and the radar's shiny grass uses "Wild Shiny Odds" (F-SHINY-02)
#   instead of the fixed 1/4096 base.
#
# 6.8.2 adaptations: pbPokeRadarHighlightGrass is a guarded copy (keeps
# 6.8.2's chain cap of 40 for the odds). The chain-break is in an
# EncounterModifier proc that can't be wrapped, so while PokeRadar+ keeps a
# chain the proc's pbPokeRadarCancel is held back and the chained species is
# put back. Hoenn's PokéNav radar (Settings::HOENN) isn't changed.
#===============================================================================
KIF::Options.define(:pokeradarplus, 0, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("PokeRadar+"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.pokeradarplus },
                 proc { |value| $PokemonSystem.pokeradarplus = value },
                 [_INTL("Normal Poké Radar."),
                  _INTL("Adds a chain count display. Chains won't randomly drop.")])
}

module KIF
  module RadarPlus
    @hold_cancel = false
    @cancel_held = false
    class << self
      attr_accessor :hold_cancel, :cancel_held
    end

    def self.on?
      return $PokemonSystem && $PokemonSystem.pokeradarplus.to_i > 0
    end

    def self.shiny_odds
      return $PokemonSystem.shinyodds.to_i if $PokemonSystem && $PokemonSystem.respond_to?(:shinyodds)
      return Settings::SHINY_POKEMON_CHANCE
    end

    # Stepping into shaking grass while chaining, on a normal land encounter
    def self.keeps_chain?
      return false unless on? && !Settings::HOENN && $PokemonTemp.pokeradar
      return false unless $PokemonTemp.pokeradar[2] > 0 && pbPokeRadarGetShakingGrass >= 0
      return false if $PokemonGlobal.partner
      return GameData::EncounterType.get($PokemonTemp.encounterType).type == :land
    rescue
      return false
    end
  end
end

KIF.guard_base("013_Items/005_Item_PokeRadar.rb", 2523489654, "pbPokeRadarHighlightGrass")

# Copy of 6.8.2 pbPokeRadarHighlightGrass with the KIF lines marked
def pbPokeRadarHighlightGrass(showmessage = true)
  if KIF::RadarPlus.on? && $PokemonTemp.pokeradar                       # KIF
    pbMessage(_INTL("Chain count: {1}\\wtnp[10]", $PokemonTemp.pokeradar[2])) # KIF
  end                                                                  # KIF
  grasses = [] # x, y, ring (0-3 inner to outer), rarity§
  # Choose 1 random tile from each ring around the player
  for i in 0...4
    r = rand((i + 1) * 8)
    # Get coordinates of randomly chosen tile
    x = $game_player.x
    y = $game_player.y
    if r <= (i + 1) * 2
      x = $game_player.x - i - 1 + r
      y = $game_player.y - i - 1
    elsif r <= (i + 1) * 6 - 2
      x = [$game_player.x + i + 1, $game_player.x - i - 1][r % 2]
      y = $game_player.y - i + ((r - 1 - (i + 1) * 2) / 2).floor
    else
      x = $game_player.x - i + r - (i + 1) * 6
      y = $game_player.y + i + 1
    end
    # Add tile to grasses array if it's a valid grass tile
    if x >= 0 && x < $game_map.width &&
      y >= 0 && y < $game_map.height
      terrain = $game_map.terrain_tag(x, y)
      if terrain.land_wild_encounters && terrain.shows_grass_rustle
        # Choose a rarity for the grass (0=normal, 1=rare, 2=shiny)
        s = (rand(100) < 25) ? 1 : 0
        if $PokemonTemp.pokeradar && $PokemonTemp.pokeradar[2] > 0
          chain_for_odds = [$PokemonTemp.pokeradar[2], 40].min
          odds = [KIF::RadarPlus.shiny_odds, 1].max                                        # KIF
          v = [(65536 / odds) - chain_for_odds * 200, 200].max                             # KIF
          v = 0xFFFF / v
          v = rand(65536) / v
          s = 2 if v == 0
        end
        grasses.push([x, y, i, s])
      end
    end
  end
  if grasses.length == 0
    # No shaking grass found, break the chain
    if KIF::RadarPlus.on? && $PokemonTemp.pokeradar                    # KIF
      pbMessage(_INTL("Nothing happened...\nPokeRadar+ saved the chain!"))   # KIF
    else                                                               # KIF
      pbMessage(_INTL("Nothing happened...")) if showmessage
      pbPokeRadarCancel
    end                                                                # KIF
  else
    # Show grass rustling animations
    for grass in grasses
      case grass[3]
      when 0 # Normal rustle
        $scene.spriteset.addUserAnimation(Settings::RUSTLE_NORMAL_ANIMATION_ID, grass[0], grass[1], true, 1)
      when 1 # Vigorous rustle
        $scene.spriteset.addUserAnimation(Settings::RUSTLE_VIGOROUS_ANIMATION_ID, grass[0], grass[1], true, 1)
      when 2 # Shiny rustle
        $scene.spriteset.addUserAnimation(Settings::RUSTLE_SHINY_ANIMATION_ID, grass[0], grass[1], true, 1)
      end
    end
    $PokemonTemp.pokeradar[3] = grasses if $PokemonTemp.pokeradar
    pbWait(Graphics.frame_rate / 2)
  end
end

alias kif_radar_pbPokeRadarCancel pbPokeRadarCancel unless defined?(kif_radar_pbPokeRadarCancel)

def pbPokeRadarCancel(*args)
  if KIF::RadarPlus.hold_cancel
    KIF::RadarPlus.cancel_held = true
    return
  end
  return kif_radar_pbPokeRadarCancel(*args)
end

module EncounterModifier
  class << self
    alias kif_radar_trigger trigger unless method_defined?(:kif_radar_trigger)

    def trigger(encounter)
      return kif_radar_trigger(encounter) unless KIF::RadarPlus.keeps_chain?
      chain = [$PokemonTemp.pokeradar[0], $PokemonTemp.pokeradar[1]]
      KIF::RadarPlus.cancel_held = false
      KIF::RadarPlus.hold_cancel = true
      begin
        ret = kif_radar_trigger(encounter)
      ensure
        KIF::RadarPlus.hold_cancel = false
      end
      if KIF::RadarPlus.cancel_held   # the chain would have broken
        KIF::RadarPlus.cancel_held = false
        ret = chain
        $PokemonTemp.forceSingleBattle = true
      end
      return ret
    end
  end
end

# KIF autorepel: one Repel step back for every step while the radar is on
Events.onStepTaken += proc { |_sender, _e|
  next if Settings::HOENN
  $PokemonGlobal.repel += 1 if $PokemonTemp.pokeradar && $PokemonGlobal.repel > 0
}
