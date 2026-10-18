#===============================================================================
# C-BATTLE-03 – Battle Info (2026-10-14)
# While choosing Fight / Bag / Pokémon / Run, the Action button (Z / Shift)
# opens a screen with what the battle knows, one page per Pokémon on the
# field plus a Field page (Left / Right to switch, Back to close):
#   * stat changes (+1 ... +6 / -1 ... -6) with their multiplier, and the
#     resulting stats of your own Pokémon;
#   * types (as changed in battle), HP, status;
#   * ability and held item: always for yours, for foes only once the battle
#     has shown them (ability pop-up or a message naming them);
#   * effects with turns left (Taunt, Encore, Leech Seed, Substitute...);
#   * weather, terrain, rooms and Gravity, screens and hazards per side,
#     Future Sight and Wish.
# Works the same in PIF's battle screen and EBDX's. A base feature (no
# module);
# "Battle Info" setting, On by default (Off for Classic KIF).
# On also shows how to open it, kept out of the way: a small "Z INFO" tab above the left end of PIF's
# command box (the right end has your Pokémon's battle box), and a 5th INFO
# button in EBDX's command row (EBDX fits 5; not added when its DEBUG button
# already takes the 5th place). "On, no button" keeps only the key.
#===============================================================================
KIF::Options.define(:cody_battleinfo, 1, :global)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Battle Info"), [_INTL("Off"), _INTL("On"), _INTL("No button")],
                 proc { $PokemonSystem.cody_battleinfo },
                 proc { |value| $PokemonSystem.cody_battleinfo = value },
                 [_INTL("No battle info screen"),
                  _INTL("In battle, INFO (or {1}) shows stat changes, effects and the field", KIF::Keys.name(Input::ACTION)),
                  _INTL("Battle info with {1} only, no INFO button on screen", KIF::Keys.name(Input::ACTION))])
}

module KIF
  module BattleInfo
    STAT_ORDER = [[:ATTACK, "Attack"], [:DEFENSE, "Defense"], [:SPECIAL_ATTACK, "Sp. Atk"],
                  [:SPECIAL_DEFENSE, "Sp. Def"], [:SPEED, "Speed"], [:ACCURACY, "Accuracy"],
                  [:EVASION, "Evasion"]]

    module_function

    def on?
      return $PokemonSystem && $PokemonSystem.respond_to?(:cody_battleinfo) &&
             $PokemonSystem.cody_battleinfo.to_i > 0
    end

    # the INFO tab (PIF) / INFO button (EBDX) is shown
    def button?
      return on? && $PokemonSystem.cody_battleinfo.to_i == 1
    end

    def const(name)
      return PBEffects.const_defined?(name) ? PBEffects.const_get(name) : nil
    end

    def eff(effects, name)
      i = const(name)
      return nil if i.nil? || effects.nil?
      return effects[i]
    end

    def turns(n)
      return n.to_i == 1 ? _INTL("1 turn") : _INTL("{1} turns", n.to_i)
    end

    def multiplier(stage, acc = false)
      stage = [[stage.to_i, -6].max, 6].min
      if acc
        num = stage >= 0 ? 3 + stage : 3
        den = stage >= 0 ? 3 : 3 - stage
      else
        num = stage >= 0 ? 2 + stage : 2
        den = stage >= 0 ? 2 : 2 - stage
      end
      return num.to_f / den
    end

    def mult_text(m)
      s = format("%.2f", m).sub(/0+\z/, "").sub(/\.\z/, "")
      return "x#{s}"
    end

    # The player's own Pokémon (and a partner's: the player sees their screen)
    def own?(battler)
      return !battler.opposes?(0)
    end

    #---------------------------------------------------------------------------
    # What the battle has shown about a foe
    #---------------------------------------------------------------------------
    def ability_known?(battle, battler)
      return true if own?(battler)
      known = battle.instance_variable_get(:@cody_known_abilities) || {}
      return true if known[battler.pokemon.object_id] == battler.ability_id
      shown = battle.instance_variable_get(:@kif_bi_abilities) || {}
      return shown[battler.pokemon.object_id] == battler.ability_id
    end

    # nil: not shown yet; otherwise the text to show
    def item_text(battle, battler)
      return battler.item ? battler.itemName : _INTL("None") if own?(battler)
      seen = (battle.instance_variable_get(:@kif_bi_items) || {})[battler.pokemon.object_id]
      return nil if seen.nil?
      return battler.itemName if battler.item && battler.item_id == seen
      return _INTL("None") if !battler.item
      return nil   # it holds something else now that the battle hasn't named
    end

    # A message naming a foe's item or ability reveals it
    def note_message(battle, msg)
      return unless msg.is_a?(String) && !msg.empty?
      battle.battlers.each do |b|
        next if !b || !b.pokemon || own?(b)
        key = b.pokemon.object_id
        if b.item && (name = b.itemName.to_s) != "" && msg.include?(name)
          (battle.instance_variable_set(:@kif_bi_items, {}) unless battle.instance_variable_get(:@kif_bi_items))
          battle.instance_variable_get(:@kif_bi_items)[key] = b.item_id
        end
        if b.ability && (name = b.abilityName.to_s) != "" && msg.include?(name)
          (battle.instance_variable_set(:@kif_bi_abilities, {}) unless battle.instance_variable_get(:@kif_bi_abilities))
          battle.instance_variable_get(:@kif_bi_abilities)[key] = b.ability_id
        end
      end
    rescue StandardError
    end

    #---------------------------------------------------------------------------
    # Text lists (also what the kit test reads)
    #---------------------------------------------------------------------------
    def stage_rows(battler)
      STAT_ORDER.map do |stat, label|
        stage = battler.stages[stat].to_i
        m = multiplier(stage, stat == :ACCURACY || stat == :EVASION)
        value = nil
        if own?(battler) && ![:ACCURACY, :EVASION].include?(stat)
          base = case stat
                 when :ATTACK then battler.attack
                 when :DEFENSE then battler.defense
                 when :SPECIAL_ATTACK then battler.spatk
                 when :SPECIAL_DEFENSE then battler.spdef
                 when :SPEED then battler.speed
                 end
          value = (base.to_i * m).floor
          # Speed as the battle uses it (paralysis, Tailwind, items, abilities)
          if stat == :SPEED && battler.respond_to?(:pbSpeed)
            value = (battler.pbSpeed rescue value)
          end
        end
        [label, stage, m, value]
      end
    end

    def battler_effects(battle, b)
      e = b.effects
      out = []
      add = ->(text) { out << text }
      add.call(_INTL("Confused")) if eff(e, :Confusion).to_i > 0
      add.call(_INTL("In love")) if eff(e, :Attract).to_i >= 0 && eff(e, :Attract) != -1 && !eff(e, :Attract).nil?
      add.call(_INTL("Seeded (Leech Seed)")) if eff(e, :LeechSeed).to_i >= 0 && eff(e, :LeechSeed) != -1 && !eff(e, :LeechSeed).nil?
      add.call(_INTL("Substitute ({1} HP)", eff(e, :Substitute).to_i)) if eff(e, :Substitute).to_i > 0
      add.call(_INTL("Taunted: {1}", turns(eff(e, :Taunt)))) if eff(e, :Taunt).to_i > 0
      if eff(e, :Encore).to_i > 0
        mv = eff(e, :EncoreMove)
        name = (GameData::Move.get(mv).name rescue nil)
        add.call(name ? _INTL("Encore ({1}): {2}", name, turns(eff(e, :Encore))) : _INTL("Encore: {1}", turns(eff(e, :Encore))))
      end
      if eff(e, :Disable).to_i > 0
        mv = eff(e, :DisableMove)
        name = (GameData::Move.get(mv).name rescue nil)
        add.call(name ? _INTL("{1} disabled: {2}", name, turns(eff(e, :Disable))) : _INTL("Disabled: {1}", turns(eff(e, :Disable))))
      end
      add.call(_INTL("Tormented")) if eff(e, :Torment)
      add.call(_INTL("Drowsy (Yawn)")) if eff(e, :Yawn).to_i > 0
      add.call(_INTL("Perish count: {1}", eff(e, :PerishSong).to_i)) if eff(e, :PerishSong).to_i > 0
      add.call(_INTL("Cursed")) if eff(e, :Curse)
      add.call(_INTL("Nightmare")) if eff(e, :Nightmare)
      add.call(_INTL("Rooted (Ingrain)")) if eff(e, :Ingrain)
      add.call(_INTL("Aqua Ring")) if eff(e, :AquaRing)
      add.call(_INTL("Getting pumped (crits)")) if eff(e, :FocusEnergy).to_i > 0
      add.call(_INTL("Laser Focus")) if eff(e, :LaserFocus).to_i > 0
      add.call(_INTL("Charged")) if eff(e, :Charge).to_i > 0
      add.call(_INTL("Stockpile: {1}", eff(e, :Stockpile).to_i)) if eff(e, :Stockpile).to_i > 0
      add.call(_INTL("Floating (Magnet Rise): {1}", turns(eff(e, :MagnetRise)))) if eff(e, :MagnetRise).to_i > 0
      add.call(_INTL("Telekinesis: {1}", turns(eff(e, :Telekinesis)))) if eff(e, :Telekinesis).to_i > 0
      add.call(_INTL("Heal Block: {1}", turns(eff(e, :HealBlock)))) if eff(e, :HealBlock).to_i > 0
      add.call(_INTL("Embargo: {1}", turns(eff(e, :Embargo)))) if eff(e, :Embargo).to_i > 0
      add.call(_INTL("Throat Chop: {1}", turns(eff(e, :ThroatChop)))) if eff(e, :ThroatChop).to_i > 0
      if eff(e, :Trapping).to_i > 0
        mv = eff(e, :TrappingMove)
        name = (GameData::Move.get(mv).name rescue nil)
        add.call(name ? _INTL("Trapped by {1}: {2}", name, turns(eff(e, :Trapping))) : _INTL("Trapped: {1}", turns(eff(e, :Trapping))))
      end
      add.call(_INTL("Can't escape")) if eff(e, :MeanLook).to_i >= 0 && eff(e, :MeanLook) != -1 && !eff(e, :MeanLook).nil?
      add.call(_INTL("Grounded (Smack Down)")) if eff(e, :SmackDown)
      add.call(_INTL("Identified")) if eff(e, :Foresight) || eff(e, :MiracleEye)
      add.call(_INTL("Minimized")) if eff(e, :Minimize)
      add.call(_INTL("Flash Fire boost")) if eff(e, :FlashFire)
      add.call(_INTL("Uproar: {1}", turns(eff(e, :Uproar)))) if eff(e, :Uproar).to_i > 0
      add.call(_INTL("Slow Start: {1}", turns(eff(e, :SlowStart)))) if eff(e, :SlowStart).to_i > 0
      add.call(_INTL("Transformed")) if eff(e, :Transform)
      add.call(_INTL("Imprison")) if eff(e, :Imprison)
      add.call(_INTL("Powder")) if eff(e, :Powder)
      add.call(_INTL("Electrified")) if eff(e, :Electrify)
      if battle.respond_to?(:positions) && battle.positions[b.index]
        pe = battle.positions[b.index].effects
        add.call(_INTL("Future Sight hits in {1}", turns(eff(pe, :FutureSightCounter)))) if eff(pe, :FutureSightCounter).to_i > 0
        add.call(_INTL("Wish comes true next turn")) if eff(pe, :Wish).to_i > 0
      end
      return out
    rescue StandardError => ex
      KIF.log("Battle Info: effects failed (#{ex.class}: #{ex.message})") if defined?(KIF.log)
      return out || []
    end

    def side_effects(side)
      e = side.effects
      out = []
      { :Reflect => "Reflect", :LightScreen => "Light Screen", :AuroraVeil => "Aurora Veil",
        :Tailwind => "Tailwind", :Safeguard => "Safeguard", :Mist => "Mist",
        :LuckyChant => "Lucky Chant", :Rainbow => "Rainbow", :SeaOfFire => "Sea of fire",
        :Swamp => "Swamp" }.each do |k, label|
        out << _INTL("{1}: {2}", _INTL(label), turns(eff(e, k))) if eff(e, k).to_i > 0
      end
      out << _INTL("Spikes x{1}", eff(e, :Spikes).to_i) if eff(e, :Spikes).to_i > 0
      out << _INTL("Toxic Spikes x{1}", eff(e, :ToxicSpikes).to_i) if eff(e, :ToxicSpikes).to_i > 0
      out << _INTL("Stealth Rock") if eff(e, :StealthRock)
      out << _INTL("Sticky Web") if eff(e, :StickyWeb)
      return out
    end

    def field_lines(battle)
      f = battle.field
      out = []
      w = f.weather
      if w && w != :None
        name = (GameData::BattleWeather.get(w).name rescue w.to_s)
        out << (f.weatherDuration.to_i > 0 ? _INTL("Weather: {1} ({2})", name, turns(f.weatherDuration)) : _INTL("Weather: {1}", name))
      else
        out << _INTL("Weather: none")
      end
      t = f.terrain
      if t && t != :None
        name = (GameData::BattleTerrain.get(t).name rescue t.to_s)
        out << (f.terrainDuration.to_i > 0 ? _INTL("Terrain: {1} ({2})", name, turns(f.terrainDuration)) : _INTL("Terrain: {1}", name))
      end
      { :TrickRoom => "Trick Room", :Gravity => "Gravity", :WonderRoom => "Wonder Room",
        :MagicRoom => "Magic Room", :MudSportField => "Mud Sport", :WaterSportField => "Water Sport",
        :FairyLock => "Fairy Lock" }.each do |k, label|
        out << _INTL("{1}: {2}", _INTL(label), turns(eff(f.effects, k))) if eff(f.effects, k).to_i > 0
      end
      out << _INTL("Ion Deluge") if eff(f.effects, :IonDeluge)
      return out
    end

    # The battlers shown, in page order: yours first, then the foes
    def battlers(battle)
      list = battle.battlers.select { |b| b && !b.fainted? && b.pokemon }
      return list.select { |b| own?(b) } + list.reject { |b| own?(b) }
    end
  end
end

#-------------------------------------------------------------------------------
# Pages added 2026-10-16 (PokeRogue Redux style): Abilities, Moves,
# Speed Order. Mods can add abilities to the Abilities page (the Innates mod
# shows a Pokémon's innates there):
#
#   KIF::BattleInfo.register_abilities(:my_mod) do |battle, battler|
#     [{ :label  => "INNATE",        # small label above the name
#        :ability => :EFFECTSPORE,   # name and description come from the game
#        :known  => true,            # false: shown as ??? (a foe's, not revealed)
#        :worked => false }]         # true: "WORKED THIS BATTLE"
#   end
#
# :name / :description can be given instead of :ability. A provider that
# raises is skipped (and logged); the page still shows everything else.
#-------------------------------------------------------------------------------
module KIF
  module BattleInfo
    @ability_providers = {}

    def self.register_abilities(id, &block)
      @ability_providers[id] = block
    end

    def self.ability_providers
      return @ability_providers
    end

    def self.ability_description(id)
      return (GameData::Ability.get(id).description.to_s rescue "")
    end

    # The splash showed this ability for this Pokémon (Effectiveness.rb notes it)
    def self.ability_worked?(battle, battler, id)
      known = battle.instance_variable_get(:@cody_known_abilities) || {}
      return known[battler.pokemon.object_id] == id
    end

    # [{label:, name:, desc:, known:, worked:}] – the main ability first
    def self.ability_entries(battle, battler)
      known = ability_known?(battle, battler)
      out = [{ :label => _INTL("ABILITY"), :name => known ? battler.abilityName.to_s : "???",
               :desc => known ? ability_description(battler.ability_id) : _INTL("Shown once the battle reveals it."),
               :known => known, :worked => ability_worked?(battle, battler, battler.ability_id),
               :main => true }]
      @ability_providers.each do |id, prov|
        begin
          list = prov.call(battle, battler) || []
          list.each do |e|
            k = e[:known] != false
            name = e[:name] || (e[:ability] && (GameData::Ability.get(e[:ability]).name rescue e[:ability].to_s))
            desc = e[:description] || (e[:ability] && ability_description(e[:ability])) || ""
            out << { :label => (e[:label] || _INTL("ABILITY")).to_s.upcase,
                     :name => k ? name.to_s : "???",
                     :desc => k ? desc.to_s : _INTL("Shown once it activates."),
                     :known => k, :worked => k && e[:worked] }
          end
        rescue StandardError => ex
          KIF.log("Battle Info: ability list from #{id} failed (#{ex.class}: #{ex.message})") if defined?(KIF.log)
        end
      end
      return out
    end

    #---------------------------------------------------------------------------
    # Moves: yours in full; a foe's only once it has used them
    #---------------------------------------------------------------------------
    def self.note_move(battler, move_id)
      return unless battler && battler.pokemon && move_id
      battle = battler.battle
      seen = battle.instance_variable_get(:@kif_bi_moves)
      battle.instance_variable_set(:@kif_bi_moves, seen = {}) unless seen
      per = (seen[battler.pokemon.object_id] ||= {})
      per[move_id] = per[move_id].to_i + 1
    rescue StandardError
    end

    def self.times_used(battle, battler, move_id)
      seen = battle.instance_variable_get(:@kif_bi_moves) || {}
      return (seen[battler.pokemon.object_id] || {})[move_id].to_i
    end

    # [{name:, type:, cat:, power:, acc:, pp:}] or nil for an unseen foe move
    def self.move_entries(battle, battler)
      own = own?(battler)
      battler.moves.compact.first(4).map do |m|
        used = times_used(battle, battler, m.id)
        next nil if !own && used == 0
        cat = case m.category
              when 0 then _INTL("Phys")
              when 1 then _INTL("Spec")
              else _INTL("Status")
              end
        { :name => m.name.to_s, :type => m.type, :cat => cat,
          :power => (m.baseDamage.to_i > 1 ? m.baseDamage.to_s : "-"),
          :acc => (m.accuracy.to_i > 0 ? m.accuracy.to_s : "-"),
          :pp => own ? "#{m.pp}/#{m.total_pp}" : (used == 1 ? _INTL("used 1x") : _INTL("used {1}x", used)) }
      end
    end

    #---------------------------------------------------------------------------
    # Speed order this turn (priority moves aside): pbSpeed counts paralysis,
    # Tailwind, items and abilities; Trick Room reverses it.
    #---------------------------------------------------------------------------
    def self.trick_room(battle)
      return eff(battle.field.effects, :TrickRoom).to_i
    end

    def self.speed_order(battle)
      list = battle.battlers.select { |b| b && !b.fainted? && b.pokemon }
      sp = list.map { |b| [b, (b.pbSpeed rescue b.speed).to_i] }
      sp.sort_by! { |b, s| [-s, b.index] }
      sp.reverse! if trick_room(battle) > 0
      return sp
    end

    def self.speed_note(b)
      notes = []
      notes << _INTL("Paralyzed") if b.status == :PARALYSIS
      notes << _INTL("Tailwind") if eff(b.pbOwnSide.effects, :Tailwind).to_i > 0 rescue nil
      notes << _INTL("Choice Scarf") if b.item == :CHOICESCARF && own?(b)
      return notes.join(", ")
    end
  end
end

class PokeBattle_Battler
  alias kif_bi_pbUseMove pbUseMove unless method_defined?(:kif_bi_pbUseMove)

  def pbUseMove(choice, specialUsage = false)
    ret = kif_bi_pbUseMove(choice, specialUsage)
    KIF::BattleInfo.note_move(self, @lastMoveUsed) if @lastMoveUsed && !specialUsage
    return ret
  end
end

#-------------------------------------------------------------------------------
# The screen (new look 2026-10-16: KIF pixel UI). Left / Right: the Pokémon
# on the field, then Field and Speed. Up / Down: a Pokémon's pages (Stats,
# Abilities, Moves). Back closes.
#-------------------------------------------------------------------------------
class KifBattleInfoScreen
  include KIF::PixelUI

  W = 512
  H = 384
  PF = KIF::PixelFont
  PAGES = [:stats, :abilities, :moves]

  TYPE_COLORS = {
    :NORMAL => [160, 160, 140], :FIRE => [230, 120, 60], :WATER => [90, 140, 230], :GRASS => [110, 180, 80],
    :ELECTRIC => [230, 190, 50], :ICE => [110, 200, 210], :FIGHTING => [190, 70, 60], :POISON => [160, 80, 170],
    :GROUND => [200, 170, 100], :FLYING => [150, 140, 230], :PSYCHIC => [230, 90, 130], :BUG => [150, 175, 40],
    :ROCK => [180, 160, 80], :GHOST => [110, 90, 150], :DRAGON => [110, 70, 230], :DARK => [110, 90, 80],
    :STEEL => [170, 170, 200], :FAIRY => [225, 130, 190]
  }

  def initialize(battle)
    @battle = battle
    @entries = KIF::BattleInfo.battlers(battle) + [:field, :speed]
    @index = 0
    @page = 0
  end

  def run
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 999_999
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(W, H)
    refresh
    loop do
      Graphics.update
      Input.update
      if Input.trigger?(Input::LEFT)
        @index = (@index - 1) % @entries.length
        pbPlayCursorSE
        refresh
      elsif Input.trigger?(Input::RIGHT)
        @index = (@index + 1) % @entries.length
        pbPlayCursorSE
        refresh
      elsif (Input.trigger?(Input::UP) || Input.trigger?(Input::DOWN)) && battler?
        @page = (@page + (Input.trigger?(Input::DOWN) ? 1 : -1)) % PAGES.length
        pbPlayCursorSE
        refresh
      elsif Input.trigger?(Input::BACK) || Input.trigger?(Input::ACTION) || Input.trigger?(Input::USE)
        pbPlayCancelSE
        break
      end
    end
  ensure
    @sprite.bitmap.dispose if @sprite && @sprite.bitmap
    @sprite.dispose if @sprite
    @viewport.dispose if @viewport
  end

  def current
    return @entries[@index]
  end

  def battler?
    return !current.is_a?(Symbol)
  end

  def type_color(t)
    return Color.new(*(TYPE_COLORS[t] || [130, 130, 130]))
  end

  def type_name(t)
    return (GameData::Type.get(t).name rescue t.to_s)
  end

  #---------------------------------------------------------------------------
  def refresh
    b = @sprite.bitmap
    b.fill_rect(0, 0, W, H, BG)
    draw_top(b)
    case current
    when :field then draw_field(b)
    when :speed then draw_speed(b)
    else
      draw_battler_head(b, current)
      case PAGES[@page]
      when :stats then draw_stats(b, current)
      when :abilities then draw_abilities(b, current)
      when :moves then draw_moves(b, current)
      end
    end
    hints = [[:lr, _INTL("Pokémon")]]
    hints << [:ud, _INTL("Page")] if battler?
    hints << [KIF::Keys.name(Input::BACK), _INTL("Close")]
    footer(b, hints)
  end

  # chips: every Pokémon (green dot yours, red foes), then Field and Speed
  def draw_top(b)
    b.fill_rect(0, 0, W, 32, PANEL2)
    b.fill_rect(0, 31, W, 1, LINE)
    labels = @entries.map do |e|
      case e
      when :field then [_INTL("Field"), nil]
      when :speed then [_INTL("Speed"), nil]
      else [e.name.to_s, KIF::BattleInfo.own?(e) ? OWN : FOE]
      end
    end
    max_name = 120
    loop do
      total = labels.sum { |n, dot| [PF.width(PF::TEXT, n), max_name].min + (dot ? 22 : 14) + 3 }
      break if total <= W - 12 || max_name <= 30
      max_name -= 6
    end
    x = 6
    labels.each_with_index do |(name, dot), i|
      name = PF.fit(PF::TEXT, name, max_name)
      w = PF.width(PF::TEXT, name) + (dot ? 22 : 14)
      act = (i == @index)
      rbox(b, x, 5, x + w, 27, 5, act ? SEL : PANEL, act ? SELB : LINE)
      tx = x + 7
      if dot
        rrect(b, x + 7, 13, x + 12, 18, 2, dot)
        tx = x + 16
      end
      text(b, tx, 5, w, 22, name, act ? TXT : DIM)
      x += w + 3
    end
  end

  def draw_battler_head(b, bt)
    x = 6
    PAGES.each_with_index do |p, i|
      label = { :stats => _INTL("Stats"), :abilities => _INTL("Abilities"), :moves => _INTL("Moves") }[p]
      w = PF.width(PF::TEXT, label) + 16
      act = (i == @page)
      rbox(b, x, 36, x + w, 58, 4, act ? SEL : PANEL, act ? SELB : LINE)
      text(b, x + 8, 36, w, 22, label, act ? TXT : DIM)
      x += w + 4
    end
    own = KIF::BattleInfo.own?(bt)
    hp = own ? "#{bt.hp}/#{bt.totalhp}" : "#{(100.0 * bt.hp / [bt.totalhp, 1].max).ceil}%"
    st = bt.status && bt.status != :NONE ? (GameData::Status.get(bt.status).name rescue bt.status.to_s) : _INTL("OK")
    xr = W - 8
    types = (bt.pbTypes(true) rescue [bt.type1, bt.type2]).compact.uniq
    types.reverse.each { |t| xr -= pill(b, xr, 41, type_name(t).upcase, type_color(t), true) + 4 }
    info = _INTL("Lv.{1}  {2}  {3}", bt.level, hp, st)
    info = PF.fit(PF::TEXT, info, xr - 4 - (x + 4))
    text(b, xr - 4 - PF.width(PF::TEXT, info), 36, 300, 22, info, DIM)
  end

  #---------------------------------------------------------------------------
  def draw_stats(b, bt)
    bi = KIF::BattleInfo
    rbox(b, 6, 62, 250, H - 30, 6, PANEL)
    heading(b, 14, 242, 68, _INTL("Stat changes"))
    y = 86
    bi.stage_rows(bt).each do |label, stage, m, value|
      col = stage > 0 ? UP : (stage < 0 ? DOWN : DIM)
      text(b, 16, y, 110, 22, _INTL(label), TXT)
      text(b, 118, y, 30, 22, stage > 0 ? "+#{stage}" : stage.to_s, col, PF::TEXT, 1)
      text(b, 156, y, 50, 22, bi.mult_text(m), col)
      text(b, 200, y, 42, 22, value.to_s, TXT, PF::TEXT, 1) if value
      y += 25
    end
    rbox(b, 256, 62, W - 6, H - 30, 6, PANEL)
    ab = bi.ability_known?(@battle, bt) ? bt.abilityName : "???"
    it = bi.item_text(@battle, bt) || "???"
    heading(b, 264, W - 14, 68, _INTL("Ability"))
    text(b, 266, 82, 236, 22, PF.fit(PF::TEXT, ab, 232), ab == "???" ? DIM : TXT)
    heading(b, 264, W - 14, 110, _INTL("Held item"))
    text(b, 266, 124, 236, 22, PF.fit(PF::TEXT, it, 232), it == "???" ? DIM : TXT)
    heading(b, 264, W - 14, 152, _INTL("Effects"))
    effects = bi.battler_effects(@battle, bt)
    effects = [_INTL("None")] if effects.empty?
    max = 8
    shown = effects.first(max)
    shown[-1] = _INTL("...and {1} more", effects.length - max + 1) if effects.length > max
    y = 166
    shown.each do |l|
      text(b, 266, y, 236, 22, PF.fit(PF::TEXT, l, 232), effects == [_INTL("None")] ? DIM : TXT)
      y += 21
    end
  end

  def draw_abilities(b, bt)
    rbox(b, 6, 62, W - 6, H - 30, 6, PANEL)
    list = KIF::BattleInfo.ability_entries(@battle, bt)
    room = (H - 30 - 66) / 64
    shown = list.first(room)
    y = 66
    shown.each do |e|
      rbox(b, 12, y, W - 12, y + 60, 5, PANEL2)
      text(b, 22, y + 3, 200, 13, e[:label], e[:main] ? ACC : INNATE, PF::TINY)
      if e[:worked]
        pill(b, W - 22, y + 5, _INTL("WORKED THIS BATTLE"), Color.new(70, 120, 90), true)
      elsif e[:known] && !KIF::BattleInfo.own?(bt) && !e[:main]
        pill(b, W - 22, y + 5, _INTL("REVEALED"), Color.new(70, 120, 90), true)
      end
      text(b, 22, y + 13, 400, 26, e[:name], e[:known] ? TXT : DIM, PF::ROW)
      text(b, 22, y + 37, W - 46, 22, PF.fit(PF::TEXT, e[:desc], W - 46), e[:known] ? TXT : DIM)
      y += 64
    end
    if list.length > shown.length
      text(b, W - 18, H - 46, 0, 13, _INTL("+{1} more", list.length - shown.length), DIM, PF::TINY, 1)
    end
  end

  def draw_moves(b, bt)
    own = KIF::BattleInfo.own?(bt)
    rbox(b, 6, 62, W - 6, H - 30, 6, PANEL)
    [[_INTL("MOVE"), 22, 0], [_INTL("TYPE"), 200, 0], [_INTL("CAT"), 280, 0], [_INTL("POW"), 350, 1],
     [_INTL("ACC"), 396, 1], [own ? _INTL("PP") : _INTL("SEEN"), W - 22, 1]].each do |label, x, al|
      text(b, x, 67, 0, 13, label, ACC, PF::TINY, al)
    end
    y = 84
    KIF::BattleInfo.move_entries(@battle, bt).each do |m|
      rbox(b, 12, y, W - 12, y + 60, 5, PANEL2)
      if m.nil?
        text(b, 22, y + 17, 100, 26, "???", DIM, PF::ROW)
        text(b, W - 22, y + 19, 0, 22, _INTL("not used yet"), DIM, PF::TEXT, 1)
      else
        text(b, 22, y + 17, 176, 26, PF.fit(PF::ROW, m[:name], 172), TXT, PF::ROW)
        pill(b, 200, y + 23, type_name(m[:type]).upcase, type_color(m[:type]))
        text(b, 280, y + 19, 60, 22, m[:cat], TXT)
        text(b, 350, y + 19, 0, 22, m[:power], TXT, PF::TEXT, 1)
        text(b, 396, y + 19, 0, 22, m[:acc], TXT, PF::TEXT, 1)
        text(b, W - 22, y + 19, 0, 22, m[:pp], TXT, PF::TEXT, 1)
      end
      y += 66
    end
  end

  #---------------------------------------------------------------------------
  def draw_field(b)
    bi = KIF::BattleInfo
    rbox(b, 6, 36, W - 6, 136, 6, PANEL)
    heading(b, 14, W - 14, 42, _INTL("Field"))
    y = 56
    bi.field_lines(@battle).first(4).each { |l| text(b, 16, y, W - 32, 22, l, TXT); y += 19 }
    [[_INTL("Your side"), 0, 6, 252], [_INTL("Foe's side"), 1, 260, W - 6]].each do |label, idx, x0, x1|
      rbox(b, x0, 142, x1, H - 30, 6, PANEL)
      heading(b, x0 + 8, x1 - 8, 148, label)
      lines = bi.side_effects(@battle.sides[idx])
      none = lines.empty?
      lines = [_INTL("Nothing")] if none
      ly = 162
      lines.first(8).each do |l|
        text(b, x0 + 10, ly, x1 - x0 - 16, 22, PF.fit(PF::TEXT, l, x1 - x0 - 20), none ? DIM : TXT)
        ly += 21
      end
    end
  end

  def draw_speed(b)
    bi = KIF::BattleInfo
    rbox(b, 6, 36, W - 6, H - 30, 6, PANEL)
    text(b, 16, 38, W - 32, 22, PF.fit(PF::TEXT, _INTL("Turn order (priority moves still go first)"), W - 32), DIM)
    y = 64
    order = bi.speed_order(@battle)
    rows = order.first(6)
    rh = rows.length > 4 ? 38 : 44
    rows.each_with_index do |(bt, spd), i|
      own = bi.own?(bt)
      rbox(b, 12, y, W - 12, y + rh - 4, 5, PANEL2)
      cy = y + (rh - 4 - 26) / 2
      text(b, 22, cy, 20, 26, (i + 1).to_s, ACC, PF::ROW)
      rrect(b, 44, cy + 10, 49, cy + 15, 2, own ? OWN : FOE)
      text(b, 56, cy, 180, 26, PF.fit(PF::ROW, bt.name.to_s, 170), TXT, PF::ROW)
      # foes too: their Speed this turn, so you can plan around it (a foe's
      # Choice Scarf is only named once revealed - speed_note checks own?)
      note = bi.speed_note(bt)
      text(b, 236, cy + 2, 150, 22, note, WARN) unless note.empty?
      text(b, W - 22, cy + 2, 0, 22, _INTL("Speed {1}", spd), TXT, PF::TEXT, 1)
      y += rh
    end
    tr = bi.trick_room(@battle)
    if tr > 0
      w = pill(b, 14, y + 4, _INTL("TRICK ROOM: {1}", bi.turns(tr).upcase), Color.new(150, 90, 200))
      text(b, 14 + w + 8, y, 260, 22, _INTL("slower Pokémon go first"), DIM)
    end
  end
end

#-------------------------------------------------------------------------------
# Hooks: the key in the command menu (PIF's and EBDX's), and what the battle
# reveals about foes
#-------------------------------------------------------------------------------
module KIF
  module BattleInfo
    def self.check_key(scene)
      return unless scene.instance_variable_get(:@kif_bi_command)
      return unless on? && Input.trigger?(Input::ACTION)
      battle = scene.instance_variable_get(:@battle)
      return unless battle
      scene.instance_variable_set(:@kif_bi_command, false)   # no reopening from inside
      pbPlayDecisionSE
      begin
        KifBattleInfoScreen.new(battle).run
      rescue StandardError => e
        KIF.log("Battle Info failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      ensure
        scene.instance_variable_set(:@kif_bi_command, true)
      end
      Input.update
    end
  end
end

module KIF
  module BattleInfo
    TAB_W = 92
    TAB_H = 26

    # text centred in a box (draw_text centres it vertically for any font;
    # pbDrawTextPositions placed the small font low and the box cut it off)
    def self.tab_text(bmp, x, w, text, base, shadow)
      bmp.font.color = shadow
      bmp.draw_text(x + 1, 1, w, TAB_H - 2, text, 1)
      bmp.font.color = base
      bmp.draw_text(x, 0, w, TAB_H - 2, text, 1)
    end

    # PIF's command box: a small tab sitting on its top edge, left end
    def self.tab_bitmap
      w, h = TAB_W, TAB_H
      bmp = Bitmap.new(w, h)
      border = Color.new(88, 88, 96)
      top = Color.new(232, 232, 240)
      low = Color.new(200, 200, 212)
      bmp.fill_rect(2, 0, w - 4, h, border)
      bmp.fill_rect(0, 2, w, h - 4, border)
      bmp.fill_rect(1, 1, w - 2, h - 2, border)
      bmp.fill_rect(2, 2, w - 4, h - 4, top)
      bmp.fill_rect(2, h / 2 + 1, w - 4, h / 2 - 3, low)
      bmp.fill_rect(6, 5, 18, h - 10, Color.new(72, 120, 200))
      pbSetSmallFont(bmp)
      tab_text(bmp, 6, 18, KIF::Keys.short(Input::ACTION), Color.new(255, 255, 255), Color.new(32, 64, 120))
      tab_text(bmp, 26, w - 30, _INTL("INFO"), Color.new(64, 64, 72), Color.new(176, 176, 184))
      return bmp
    end

    def self.show_tab
      return nil unless button?
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 99_999 + 2
      spr = Sprite.new(vp)
      spr.bitmap = tab_bitmap
      spr.x = 4
      spr.y = Graphics.height - 96 - TAB_H   # ends where the command box starts
      return [vp, spr]
    rescue StandardError => e
      KIF.log("Battle Info tab failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      return nil
    end

    def self.hide_tab(tab)
      return unless tab
      vp, spr = tab
      spr.bitmap.dispose if spr.bitmap && !spr.bitmap.disposed?
      spr.dispose
      vp.dispose
    rescue StandardError
    end

    # EBDX: the command index the INFO button answers with
    EBDX_INFO = 50
  end
end

class PokeBattle_Scene
  alias kif_bi_pbCommandMenu pbCommandMenu unless method_defined?(:kif_bi_pbCommandMenu)
  alias kif_bi_pbUpdate pbUpdate unless method_defined?(:kif_bi_pbUpdate)

  def pbCommandMenu(*args)
    @kif_bi_command = true
    tab = KIF::BattleInfo.show_tab
    return kif_bi_pbCommandMenu(*args)
  ensure
    KIF::BattleInfo.hide_tab(tab)
    @kif_bi_command = false
  end

  def pbUpdate(*args)
    ret = kif_bi_pbUpdate(*args)
    KIF::BattleInfo.check_key(self) if @kif_bi_command
    return ret
  end
end

if defined?(PokeBattle_SceneEBDX)
  class PokeBattle_SceneEBDX
    alias kif_bi_ebdx_pbCommandMenu pbCommandMenu unless method_defined?(:kif_bi_ebdx_pbCommandMenu)
    alias kif_bi_ebdx_pbUpdate pbUpdate unless method_defined?(:kif_bi_ebdx_pbUpdate)

    # The INFO button answers EBDX_INFO: open the screen, then the menu again
    def pbCommandMenu(*args)
      loop do
        @kif_bi_command = true
        ret = kif_bi_ebdx_pbCommandMenu(*args)
        @kif_bi_command = false
        return ret unless ret == KIF::BattleInfo::EBDX_INFO
        begin
          KifBattleInfoScreen.new(@battle).run
        rescue StandardError => e
          KIF.log("Battle Info failed (#{e.class}: #{e.message})") if defined?(KIF.log)
        end
        Input.update
      end
    ensure
      @kif_bi_command = false
    end

    def pbUpdate(*args)
      ret = kif_bi_ebdx_pbUpdate(*args)
      KIF::BattleInfo.check_key(self) if @kif_bi_command
      return ret
    end
  end
end

if defined?(CommandWindowEBDX)
  class CommandWindowEBDX
    alias kif_bi_compileCommands compileCommands unless method_defined?(:kif_bi_compileCommands)

    def compileCommands(index)
      cmds = kif_bi_compileCommands(index)
      if KIF::BattleInfo.button? && !@safaribattle && cmds.length == 4 && @indexes.length == 4
        cmds.push(_INTL("INFO"))
        @indexes.push(KIF::BattleInfo::EBDX_INFO)
      end
      return cmds
    end
  end
end

class PokeBattle_Battle
  alias kif_bi_pbDisplay pbDisplay unless method_defined?(:kif_bi_pbDisplay)
  alias kif_bi_pbDisplayBrief pbDisplayBrief unless method_defined?(:kif_bi_pbDisplayBrief)
  alias kif_bi_pbDisplayPaused pbDisplayPaused unless method_defined?(:kif_bi_pbDisplayPaused)

  def pbDisplay(msg, &block)
    KIF::BattleInfo.note_message(self, msg)
    return kif_bi_pbDisplay(msg, &block)
  end

  def pbDisplayBrief(msg)
    KIF::BattleInfo.note_message(self, msg)
    return kif_bi_pbDisplayBrief(msg)
  end

  def pbDisplayPaused(msg, &block)
    KIF::BattleInfo.note_message(self, msg)
    return kif_bi_pbDisplayPaused(msg, &block)
  end
end
