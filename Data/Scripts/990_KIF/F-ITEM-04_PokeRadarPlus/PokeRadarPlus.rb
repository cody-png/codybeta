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
# PokeRadar+ On: the chain count is shown each time the grass shakes (port
#   addition: "Radar Chain Count" Off hides it), chains
#   don't randomly drop when you step into shaking grass, and a radar use with
#   no shaking grass keeps the chain.
# Always (as in KIF): while the radar is active your Repel steps don't run
#   down, and the radar's shiny grass uses "Wild Shiny Odds" (F-SHINY-02)
#   instead of the fixed 1/4096 base.
#
# Endless chains (Cody, 2026-10-14; Kanto radar, with or without PokeRadar+):
#   PIF stops counting at 40 and its shiny odds stop improving at chain 20.
#   KIF keeps its own count past 40 ($PokemonTemp.pokeradar[4]); the odds
#   follow PIF's formula up to 20 and then keep improving with no floor
#   (Cody, 2026-10-15): through the points in ANCHORS - PIF's best at 20
#   (1 in 200), 1 in 20 at 100, 1 in 10 at 200 - smoothly in between, and
#   past 200 it keeps improving at the same rate (2x per 100 links) until
#   every patch of shaking grass is shiny.
#   How easily a chain breaks stays PIF's (it reads PIF's count, max 40).
#   A message (with the shiny chance) at 20, 40, 60, 80, 100, 150 and 200,
#   whether or not the chain count is shown; every change of the chance is
#   written to Logs/KIF_log.txt.
#
# Multi-Battle Radar (Cody, 2026-10-15; Off / Same Species / Mixed, Off by
#   default): PIF makes every radar grass battle a single battle. With it on
#   and Battle Format 2v2/3v3 for wild battles, the radar Pokémon brings
#   company: Same Species - the others are the chained species too; Mixed -
#   the others are normal encounters from the area. Either way a won battle
#   adds 1 to the chain, however many foes it had (Cody, 2026-10-15: a 3v3
#   adding 3 was too much). Shininess:
#   the shaking patch only decides the radar Pokémon's; every other Pokémon
#   rolls its own with the chain's chance, as if it had its own shaking patch
#   (both modes; Mixed used normal odds until Cody's call, 2026-10-15).
#   A milestone passed by a jump of more than 1 is still announced.
#
# 6.8.2 adaptations: pbPokeRadarHighlightGrass is a guarded copy. The chain-break is in an
# EncounterModifier proc that can't be wrapped, so while PokeRadar+ keeps a
# chain the proc's pbPokeRadarCancel is held back and the chained species is
# put back. Hoenn's PokéNav radar (Settings::HOENN) isn't changed.
#===============================================================================
KIF::Options.define(:pokeradarplus, 0, :save)
KIF::Options.define(:radarchaincount, 1, :save)   # port addition (Cody, 2026-10-05)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("PokeRadar+"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.pokeradarplus },
                 proc { |value| $PokemonSystem.pokeradarplus = value },
                 [_INTL("Normal Poké Radar."),
                  _INTL("Adds a chain count display. Chains won't randomly drop.")])
}
KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Radar Chain Count"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.radarchaincount },
                 proc { |value| $PokemonSystem.radarchaincount = value },
                 [_INTL("PokeRadar+ doesn't show the chain count"),
                  _INTL("PokeRadar+ shows the chain count when the grass shakes")])
}

KIF::Options.define(:radarmulti, 0, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Multi-Battle Radar"), [_INTL("Off"), _INTL("Same Species"), _INTL("Mixed")],
                 proc { $PokemonSystem.radarmulti },
                 proc { |value| $PokemonSystem.radarmulti = value },
                 [_INTL("Poké Radar battles are always 1v1 (as in PIF)"),
                  _INTL("With Battle Format 2v2/3v3: all foes are the chained species (chain +1 per battle)"),
                  _INTL("With Battle Format 2v2/3v3: the others are normal encounters (chain +1 per battle)")])
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

    MILESTONES = [20, 40, 60, 80, 100, 150, 200]
    # [chain, 1 in N] with the default odds; between two points the chance
    # changes by the same factor every link, and past the last point it keeps
    # the last stretch's rate. Other Wild Shiny Odds scale the whole curve.
    ANCHORS = [[20, 200.0], [100, 20.0], [200, 10.0]]

    # The real chain length: PIF's count, then KIF's own past PIF's cap of 40
    def self.chain
      r = $PokemonTemp.pokeradar
      return 0 unless r
      return [r[2].to_i, r[4].to_i].max
    end

    # Called at the start of every highlight. The battle-end call (no message)
    # comes right after PIF added 1 to the chain (and capped it at 40).
    def self.count_step(after_battle)
      r = $PokemonTemp.pokeradar
      return 0 unless r
      pif = r[2].to_i
      if pif <= 0
        r[4] = 0
      elsif after_battle
        r[4] = (pif < 40) ? pif : [r[4].to_i + 1, 40].max
      else
        r[4] = [r[4].to_i, pif].max
      end
      return r[4]
    end

    # 1 in this many per patch of shaking grass
    def self.odds_denominator(chain, odds)
      pif = [(65536 / [odds, 1].max) - [chain, 40].min * 200, 200].max   # PIF
      return pif if chain <= 20
      best = [(65536 / [odds, 1].max) - 20 * 200, 200].max               # PIF at 20
      v = (best * curve(chain) / ANCHORS[0][1]).round
      return [[v, pif].min, 1].max   # no cap: 1 in 1 = every patch shiny
    end

    # 1 in N along ANCHORS (log-linear between points, extended past the end)
    def self.curve(chain)
      a = ANCHORS
      i = (0...a.length - 1).find { |k| chain <= a[k + 1][0] } || a.length - 2
      c0, v0 = a[i]
      c1, v1 = a[i + 1]
      return v0 * ((v1 / v0) ** ((chain - c0).to_f / (c1 - c0)))
    end

    # "Chain count" with the shiny chance (Monto, 2026-10-15)
    def self.count_message(chain)
      d = odds_denominator(chain, shiny_odds)
      return _INTL("Chain count: {1} (every patch shiny)\\wtnp[10]", chain) if d <= 1
      return _INTL("Chain count: {1} (shiny 1 in {2})\\wtnp[10]", chain, d)
    end

    def self.chance_text(chain)
      d = odds_denominator(chain, shiny_odds)
      return d <= 1 ? _INTL("every patch is shiny") : _INTL("shiny chance 1 in {1}", d)
    end

    # KIF_log: every time the chance changes
    def self.log_chance(chain)
      return if chain <= 0
      d = odds_denominator(chain, shiny_odds)
      return if @last_logged == d
      @last_logged = d
      KIF.log("Poké Radar chain #{chain}: shiny chance per patch of shaking grass 1 in #{d}") if defined?(KIF.log)
    end

    # passed: the milestone reached (a multi battle can jump past it)
    def self.milestone_message(chain, passed = nil)
      return _INTL("Poké Radar chain: {1}! Every patch of shaking grass is shiny now!", chain) if odds_denominator(chain, shiny_odds) <= 1
      return _INTL("Poké Radar chain: {1}! Shiny chance: 1 in {2}.", chain, odds_denominator(chain, shiny_odds))
    end

    # The highest milestone reached since the last highlight (nil: none).
    # $PokemonTemp.pokeradar[5] = the chain at the last highlight.
    def self.milestone_passed(chain)
      r = $PokemonTemp.pokeradar
      return nil unless r && chain > 0
      prev = r[5] ? r[5].to_i : chain - 1
      prev = chain - 1 if prev >= chain
      r[5] = chain
      return MILESTONES.select { |m| m > prev && m <= chain }.max
    end

    def self.count_shown?
      return on? && $PokemonSystem.radarchaincount.to_i == 1
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
  chain = KIF::RadarPlus.count_step(!showmessage)                      # KIF: endless chain
  KIF::RadarPlus.log_chance(chain)                                     # KIF
  passed = KIF::RadarPlus.milestone_passed(chain)                      # KIF
  if !showmessage && passed                                            # KIF: milestones
    pbMessage(KIF::RadarPlus.milestone_message(chain, passed))         # KIF
  elsif chain > 0 && KIF::RadarPlus.count_shown?                       # KIF
    pbMessage(KIF::RadarPlus.count_message(chain))                     # KIF
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
          v = KIF::RadarPlus.odds_denominator(chain, KIF::RadarPlus.shiny_odds)          # KIF
          if v <= 1                                                                   # KIF: every patch shiny
            s = 2                                                                     # KIF
          else                                                                        # KIF
            v = 0xFFFF / v
            v = rand(65536) / v
            s = 2 if v == 0
          end                                                                         # KIF
        end
        grasses.push([x, y, i, s])
      end
    end
  end
  if grasses.length == 0
    # No shaking grass found, break the chain
    if KIF::RadarPlus.on? && $PokemonTemp.pokeradar && $PokemonTemp.pokeradar[2].to_i > 0   # KIF: only a real chain
      pbMessage(_INTL("Nothing happened...\nPokeRadar+ saved the chain!")) if showmessage   # KIF
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
      # the other Pokémon of a multi radar battle (Multi-Battle Radar)
      multi = KIF::RadarPlus.multi
      return KIF::RadarPlus.multi_encounter(encounter) if multi
      single_before = $PokemonTemp.forceSingleBattle
      on_grass = (pbPokeRadarGetShakingGrass >= 0 rescue false)
      ret = kif_radar_trigger_keep(encounter)
      KIF::RadarPlus.multi_begin(ret) if on_grass && !single_before && $PokemonTemp.forceSingleBattle
      return ret
    end

    def kif_radar_trigger_keep(encounter)
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

#-------------------------------------------------------------------------------
# Multi-Battle Radar
#-------------------------------------------------------------------------------
module KIF
  module RadarPlus
    @multi = nil
    class << self
      attr_accessor :multi
    end

    def self.multi_mode
      return 0 if Settings::HOENN || !$PokemonSystem || !$PokemonSystem.respond_to?(:radarmulti)
      return $PokemonSystem.radarmulti.to_i
    end

    # The radar Pokémon was just chosen and PIF asked for a single battle
    def self.multi_begin(encounter)
      return unless encounter && multi_mode > 0 && $PokemonTemp.pokeradar
      return unless KIF.random_encounter && KIF.format_for_wild?
      return if $Trainer.able_pokemon_count <= 1 || pbInSafari? || $PokemonGlobal.partner
      @multi = { :mode => multi_mode, :species => encounter[0], :level => encounter[1],
                 :made => 0, :ends => 0, :slot => 0 }
      patch_battle_end_event
      $PokemonTemp.forceSingleBattle = false
    end

    # The other foes: the chained species, or the area's normal encounter
    def self.multi_encounter(encounter)
      m = @multi
      return [m[:species], m[:level]] if m[:mode] == 1
      return encounter
    end

    def self.multi_end
      @multi = nil
    end

    # The foes in a random order, so the radar Pokémon (the one the shaking
    # patch decides) can be in any spot (Cody, 2026-10-15). pairs: [[species,
    # level], ...] in battle order; :slot = where the radar Pokémon is.
    def self.multi_shuffle(pairs)
      m = @multi
      radar = pairs[m[:slot]] || pairs[0]
      order = (0...pairs.length).to_a.shuffle
      out = order.map { |i| pairs[i] }
      m[:slot] = order.index(pairs.index { |p| p.equal?(radar) } || 0)
      return out
    end

    # Wild Pokémon creation: the shaking patch only decides the radar Pokémon
    def self.multi_generate(args)
      m = @multi
      m[:made] += 1
      return yield if m[:made] == m[:slot] + 1
      r = $PokemonTemp.pokeradar
      saved = r ? r[3] : nil
      r[3] = [] if r                       # PIF's patch shininess skips this one
      begin
        pkmn = yield
      ensure
        r[3] = saved if r
      end
      if pkmn && !pkmn.shiny?
        d = odds_denominator(chain, shiny_odds)
        if d <= 1 || rand(d) == 0
          pkmn.shiny = true
          pkmn.debug_shiny = false if pkmn.respond_to?(:debug_shiny=)
          pkmn.radar_shiny = true if pkmn.respond_to?(:radar_shiny=)
        end
      end
      return pkmn
    end

    # onWildBattleEnd runs once per foe. Only the radar Pokémon's call
    # reaches PIF's radar handler, so a battle adds 1 to the chain; the others
    # never do (it would add again: in Kanto it continues the chain with any
    # species).
    def self.multi_battle_end(event, args)
      m = @multi
      m[:ends] += 1
      r = $PokemonTemp.pokeradar
      return event.kif_radar_trigger_orig(*args) if m[:ends] == m[:slot] + 1
      # PIF's Kanto handler continues the chain with whatever species it is
      # given, so the radar is hidden from it for these calls (its
      # pbPokeRadarCancel is held back); other handlers see the real battle
      $PokemonTemp.pokeradar = nil
      self.hold_cancel = true
      begin
        return event.kif_radar_trigger_orig(*args)
      ensure
        self.hold_cancel = false
        self.cancel_held = false
        $PokemonTemp.pokeradar = r if $PokemonTemp.pokeradar.nil?
      end
    end

    def self.patch_battle_end_event
      ev = Events.onWildBattleEnd
      return if ev.nil? || ev.respond_to?(:kif_radar_trigger_orig)
      ev.singleton_class.send(:alias_method, :kif_radar_trigger_orig, :trigger)
      ev.define_singleton_method(:trigger) do |*args|
        next KIF::RadarPlus.multi_battle_end(self, args) if KIF::RadarPlus.multi
        kif_radar_trigger_orig(*args)
      end
    end
  end
end

KIF::RadarPlus.patch_battle_end_event

alias kif_radar_pbDoubleWildBattle pbDoubleWildBattle unless defined?(kif_radar_pbDoubleWildBattle)
def pbDoubleWildBattle(species1, level1, species2, level2, *rest)
  if KIF::RadarPlus.multi
    (species1, level1), (species2, level2) = KIF::RadarPlus.multi_shuffle([[species1, level1], [species2, level2]])
  end
  return kif_radar_pbDoubleWildBattle(species1, level1, species2, level2, *rest)
end

alias kif_radar_pbTripleWildBattle pbTripleWildBattle unless defined?(kif_radar_pbTripleWildBattle)
def pbTripleWildBattle(species1, level1, species2, level2, species3, level3, *rest)
  if KIF::RadarPlus.multi
    (species1, level1), (species2, level2), (species3, level3) =
      KIF::RadarPlus.multi_shuffle([[species1, level1], [species2, level2], [species3, level3]])
  end
  return kif_radar_pbTripleWildBattle(species1, level1, species2, level2, species3, level3, *rest)
end

alias kif_radar_pbGenerateWildPokemon pbGenerateWildPokemon unless defined?(kif_radar_pbGenerateWildPokemon)
def pbGenerateWildPokemon(*args)
  return kif_radar_pbGenerateWildPokemon(*args) unless KIF::RadarPlus.multi
  return KIF::RadarPlus.multi_generate(args) { kif_radar_pbGenerateWildPokemon(*args) }
end

EncounterModifier.registerEncounterEnd(proc { KIF::RadarPlus.multi_end }) if EncounterModifier.respond_to?(:registerEncounterEnd)

# KIF autorepel: one Repel step back for every step while the radar is on
Events.onStepTaken += proc { |_sender, _e|
  next if Settings::HOENN
  $PokemonGlobal.repel += 1 if $PokemonTemp.pokeradar && $PokemonGlobal.repel > 0
}
