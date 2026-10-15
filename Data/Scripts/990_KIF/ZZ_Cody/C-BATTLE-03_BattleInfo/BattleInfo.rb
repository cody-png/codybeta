#===============================================================================
# C-BATTLE-03 – Battle Info (Cody, 2026-10-14)
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
# Works the same in PIF's battle screen and EBDX's. Information module;
# "Battle Info" setting, On by default (Off for Classic KIF).
# On also shows how to open it (Cody liked both mockups, "so long as they
# aren't in the way"): a small "Z INFO" tab above the left end of PIF's
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
                  _INTL("In battle, INFO (or Z/Shift) shows stat changes, effects and the field"),
                  _INTL("Battle info with Z/Shift only, no INFO button on screen")])
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
# The screen
#-------------------------------------------------------------------------------
class KifBattleInfoScreen
  W = 512
  H = 384
  BG       = Color.new(28, 36, 48, 235)
  PANEL    = Color.new(255, 255, 255, 22)
  TEXT     = Color.new(240, 240, 240)
  SHADOW   = Color.new(40, 40, 48)
  DIMTEXT  = Color.new(168, 176, 188)
  TITLE    = Color.new(255, 216, 96)
  UP       = Color.new(112, 216, 112)
  DOWN     = Color.new(240, 112, 96)

  def initialize(battle)
    @battle = battle
    @pages = KIF::BattleInfo.battlers(battle) + [:field]
    @page = 0
  end

  def run
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 999_999
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    refresh
    loop do
      Graphics.update
      Input.update
      if Input.trigger?(Input::LEFT)
        @page = (@page - 1) % @pages.length
        pbPlayCursorSE
        refresh
      elsif Input.trigger?(Input::RIGHT)
        @page = (@page + 1) % @pages.length
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

  def text(bmp, list)
    pbDrawTextPositions(bmp, list)
  end

  def refresh
    bmp = @sprite.bitmap
    bmp.clear
    bmp.fill_rect(0, 0, bmp.width, bmp.height, BG)
    pbSetSystemFont(bmp)
    cur = @pages[@page]
    title = cur == :field ? _INTL("Field") : cur.name
    text(bmp, [[_INTL("Battle Info"), 16, 8, 0, TITLE, SHADOW],
               ["< #{title} >", W / 2, 8, 2, TEXT, SHADOW],
               ["#{@page + 1}/#{@pages.length}", W - 16, 8, 1, DIMTEXT, SHADOW]])
    if cur == :field
      draw_field(bmp)
    else
      draw_battler(bmp, cur)
    end
    pbSetSmallFont(bmp)
    text(bmp, [[_INTL("Left/Right: other Pokémon and the field    Back: close"), W / 2, H - 26, 2, DIMTEXT, SHADOW]])
    pbSetSystemFont(bmp)
  end

  def draw_battler(bmp, b)
    bi = KIF::BattleInfo
    own = bi.own?(b)
    side = !own ? _INTL("Foe") : ((b.pbOwnedByPlayer? rescue true) ? _INTL("Yours") : _INTL("Ally"))
    hp = own ? "#{b.hp}/#{b.totalhp}" : "#{(100.0 * b.hp / [b.totalhp, 1].max).ceil}%"
    status = b.status && b.status != :NONE ? (GameData::Status.get(b.status).name rescue b.status.to_s) : _INTL("No status")
    text(bmp, [[_INTL("Lv. {1}  ·  {2}", b.level, side), 16, 40, 0, DIMTEXT, SHADOW],
               [_INTL("HP {1}  ·  {2}", hp, status), 16, 64, 0, TEXT, SHADOW]])
    # types as they are now (Soak, Roost, Forest's Curse...)
    x = W - 16 - 64
    types = (b.pbTypes(true) rescue [b.type1, b.type2]).compact.uniq.reverse
    imagepos = []
    types.each do |t|
      n = (GameData::Type.get(t).id_number rescue nil)
      next unless n
      imagepos << ["Graphics/Pictures/types", x, 44, 0, n * 28, 64, 28]
      x -= 68
    end
    pbDrawImagePositions(bmp, imagepos) unless imagepos.empty?
    # stat changes
    bmp.fill_rect(12, 96, 236, 238, KifBattleInfoScreen::PANEL)
    rows = [[_INTL("Stat changes"), 20, 100, 0, TITLE, SHADOW]]
    mults = []
    y = 128
    bi.stage_rows(b).each do |label, stage, m, value|
      col = stage > 0 ? UP : (stage < 0 ? DOWN : DIMTEXT)
      rows << [_INTL(label), 20, y, 0, TEXT, SHADOW]
      rows << [(stage > 0 ? "+#{stage}" : stage.to_s), 140, y, 1, col, SHADOW]
      mults << [bi.mult_text(m), 196, y + 3, 1, col, SHADOW]
      rows << [value.to_s, 242, y, 1, TEXT, SHADOW] if value
      y += 28
    end
    text(bmp, rows)
    pbSetSmallFont(bmp)
    text(bmp, mults)
    pbSetSystemFont(bmp)
    # ability, item, effects
    bmp.fill_rect(256, 96, 244, 238, KifBattleInfoScreen::PANEL)
    ab = bi.ability_known?(@battle, b) ? b.abilityName : "???"
    it = bi.item_text(@battle, b) || "???"
    lines = [[_INTL("Ability"), 264, 100, 0, DIMTEXT, SHADOW], [ab.to_s, 492, 100, 1, TEXT, SHADOW],
             [_INTL("Item"), 264, 126, 0, DIMTEXT, SHADOW], [it.to_s, 492, 126, 1, TEXT, SHADOW],
             [_INTL("Effects"), 264, 156, 0, TITLE, SHADOW]]
    effects = bi.battler_effects(@battle, b)
    effects = [_INTL("None")] if effects.empty?
    pbSetSmallFont(bmp)
    text(bmp, lines.first(4))
    pbSetSystemFont(bmp)
    text(bmp, [lines[4]])
    pbSetSmallFont(bmp)
    ey = 182
    shown = effects.first(7)
    shown[-1] = _INTL("...and {1} more", effects.length - 6) if effects.length > 7
    text(bmp, shown.map { |l| y0 = ey; ey += 21; [l, 264, y0, 0, TEXT, SHADOW] })
    pbSetSystemFont(bmp)
  end

  def draw_field(bmp)
    bi = KIF::BattleInfo
    bmp.fill_rect(12, 40, W - 24, 92, KifBattleInfoScreen::PANEL)
    rows = []
    y = 44
    bi.field_lines(@battle).first(4).each { |l| rows << [l, 20, y, 0, TEXT, SHADOW]; y += 22 }
    pbSetSmallFont(bmp)
    text(bmp, rows)
    pbSetSystemFont(bmp)
    [[_INTL("Your side"), 0, 12], [_INTL("Foe's side"), 1, 256]].each do |label, idx, x|
      bmp.fill_rect(x, 140, 244, 194, KifBattleInfoScreen::PANEL)
      text(bmp, [[label, x + 8, 144, 0, TITLE, SHADOW]])
      lines = bi.side_effects(@battle.sides[idx])
      lines = [_INTL("Nothing")] if lines.empty?
      pbSetSmallFont(bmp)
      ly = 172
      text(bmp, lines.first(7).map { |l| y0 = ly; ly += 21; [l, x + 8, y0, 0, TEXT, SHADOW] })
      pbSetSystemFont(bmp)
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
    TAB_H = 24

    # PIF's command box: a small tab on its top edge, left end
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
      bmp.fill_rect(6, 4, 18, h - 8, Color.new(72, 120, 200))
      pbSetSmallFont(bmp)
      pbDrawTextPositions(bmp, [["Z", 15, 2, 2, Color.new(255, 255, 255), Color.new(32, 64, 120)],
                                [_INTL("INFO"), 58, 2, 2, Color.new(64, 64, 72), Color.new(176, 176, 184)]])
      return bmp
    end

    def self.show_tab
      return nil unless button?
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 99_999 + 2
      spr = Sprite.new(vp)
      spr.bitmap = tab_bitmap
      spr.x = 4
      spr.y = Graphics.height - 96 - TAB_H + 2
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
