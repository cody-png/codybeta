#===============================================================================
# F-BATTLE-07 – KIF battle UI (Trapstarr; GUI art by Mirasein, type icons by
# Lolpy1 and FairyGodmother)
# Source: KIF 0.20.7
#   011_Battle/005_Battle scene/004_PokeBattle_SceneElements.rb
#     :50-105   initializeDataBoxGraphic – BattleGUI databox swap (_M, _M2,
#               _M_darkmode)
#     :107-174  initializeOtherGraphics  – BattleGUI HP/Exp bars, Type Display
#               bitmap, separate status icon sprite
#     :189-238  x= / y= / z=             – GUI 2 bar offsets, status icon
#     :312-376  drawtypeDisplay          – Type Display
#     :418-423  refresh                  – "Show Lv. in BSM"
#     :509-540  refreshExp               – Exp bar NaN guard
#     :542-562  refreshStatus            – status icon on its own sprite
#   011_Battle/005_Battle scene/005_PokeBattle_SceneMenus.rb:122-156  command
#     menu (dark / GUI art, text colour)
#   011_Battle/005_Battle scene/007_Scene_Initialize.rb:29-53  message box
#     (dark / GUI art, text colour)
#   016_UI/015_UI_Options.rb:2399 (Show Lv. in BSM), :2521-2545 (Type Display,
#     Swap BattleGUI, Dark Mode)
#
# Options
#   Graphics > "Type Display" (Off/Ico/TCG/Sqr/FGM/Txt, all saves): the foe's
#     types next to its battle box. While it is on it replaces PIF's own
#     "type icons" in the battle box.
#   Graphics > "Swap BattleGUI" (Off/Type 1/Type 2, all saves): Mirasein's
#     battle boxes, HP/Exp bars, message box and command menu.
#   Battles > "Show Lv. in BSM" (per save): levels stay visible in battle in
#     Base Stats Mode (6.8.2's No-Levels switch).
#   Graphics > "Dark Mode" (F-UI-11, PIF's own dark mode setting) now also
#     gives battles KIF's dark message box and command menu (KIF's
#     dark mode only applied to battles).
#
# Always on (as KIF): the status icon is its own sprite, drawn over the bars
# and moved up (foe 49, player 52) so it's no longer cut off at the bottom of
# the foe's box; the Exp bar can't crash on a NaN fraction.
#
# 6.8.2 adaptations:
#   * Wrappers, no copies. The base refresh still draws everything; the status
#     icon is left out of its image list (PokemonDataBox#pbDrawImagePositions
#     filter) and PIF's type icons are skipped while Type Display is on.
#   * KIF drew the Type Display on a full-screen sprite redrawn every frame;
#     here it is drawn into the battle box when the box refreshes (same spot).
#   * "Txt" uses 6.8.2's Graphics/Pictures/types (same art as KIF's
#     types_display plus the two triple-fusion types). The four icon sheets
#     have no icons for those two types, so nothing is drawn for them.
#   * 6.8.2 swaps the battle text colours in dark mode; with KIF's dark art the
#     KIF colours are used (light grey on dark).
#   * Type Display shows the in-battle types (Soak, Transform...), like PIF's
#     icons; KIF showed the Pokémon's own types.
#   * GUI 2's Exp bar isn't stretched x1.5 as in KIF, which filled it at ~67%
#     Exp.
#   * Assets copied to Graphics/Pictures/KIF/{BattleGUI,Battle,TypeIcons}.
#===============================================================================
KIF::Options.define(:typedisplay, 0, :global)
KIF::Options.define(:battlegui, 0, :global)
KIF::Options.define(:showlevel_nolevelmode, 0, :save)

KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Type Display"),
                 [_INTL("Off"), _INTL("Ico"), _INTL("TCG"), _INTL("Sqr"), _INTL("FGM"), _INTL("Txt")],
                 proc { $PokemonSystem.typedisplay },
                 proc { |value| $PokemonSystem.typedisplay = value },
                 [_INTL("Don't draw the type indicator in battle"),
                  _INTL("Draws handmade custom type icons in battle | By Lolpy1"),
                  _INTL("Draws TCG themed type icons in battle"),
                  _INTL("Draws the square type icons in battle | Triple Fusion by Lolpy1"),
                  _INTL("Draws handmade custom type icons in battle | By FairyGodmother"),
                  _INTL("Draws the text type display in battle")])
}
KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Swap BattleGUI"), [_INTL("Off"), _INTL("Type 1"), _INTL("Type 2")],
                 proc { $PokemonSystem.battlegui },
                 proc { |value| $PokemonSystem.battlegui = value },
                 [_INTL("Default battle interface"),
                  _INTL("Swaps the HP/Exp bar to v1 | created by Mirasein"),
                  _INTL("Swaps the HP/Exp bar to v2 | created by Mirasein")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Show Lv. in BSM"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.showlevel_nolevelmode },
                 proc { |value| $PokemonSystem.showlevel_nolevelmode = value },
                 [_INTL("Base Stats Mode hides the level of Pokemons in battle."),
                  _INTL("Base Stats Mode shows the level of Pokemons (level don't reflect stats!).")])
}

module KIF
  module BattleUI
    DIR          = "Graphics/Pictures/KIF/"
    STATUS_ICONS = "Graphics/Pictures/Battle/icon_statuses"
    PIF_TYPES    = "Graphics/Pictures/Battle/typesSmall"
    TYPE_SHEETS  = [nil,
                    DIR + "TypeIcons/TypeIcons_Lolpy1",
                    DIR + "TypeIcons/TypeIcons_TCG",
                    DIR + "TypeIcons/TypeIcons_Square",
                    DIR + "TypeIcons/TypeIcons_FairyGodmother",
                    "Graphics/Pictures/types"]
    DARK_TEXT_BASE = Color.new(200, 200, 200)   # KIF DARKMODE_MESSAGE_BASE_COLOR
    GUI2_TEXT_BASE = Color.new(40, 40, 44)

    def self.gui
      v = $PokemonSystem ? $PokemonSystem.battlegui.to_i : 0
      return (0..2).include?(v) ? v : 0
    end

    def self.type_display
      v = $PokemonSystem ? $PokemonSystem.typedisplay.to_i : 0
      return (0..5).include?(v) ? v : 0
    end

    def self.dark?
      return defined?(KIF::DarkMode) ? KIF::DarkMode.on? : !!(defined?(isDarkMode) && isDarkMode)
    end

    # PIF's boxes leave the level out in Base Stats Mode (6.8.2's No-Levels
    # switch); "Show Lv. in BSM" puts it back (EBDX's boxes ask this)
    def self.show_level?
      return true unless $game_switches && $game_switches[SWITCH_NO_LEVELS_MODE]
      return $PokemonSystem.showlevel_nolevelmode.to_i == 1
    end

    def self.path(sub)
      p = DIR + sub
      return pbResolveBitmap(p) ? p : nil
    end

    # Message box art (KIF 007_Scene_Initialize.rb:30-38)
    def self.message_box
      return path("Battle/overlay_message_darkmode") if dark?
      return path("Battle/overlay_message_M2") if gui != 0
      return nil
    end

    # Command menu art (KIF 005_PokeBattle_SceneMenus.rb:136-156)
    def self.command_background
      return path("Battle/overlay_command_darkmode") if dark?
      return path("Battle/overlay_command_M2") if gui != 0
      return nil
    end

    def self.command_buttons
      return path("Battle/cursor_command_M2") if gui == 2
      return path("Battle/cursor_command_darkmode") if dark? || gui == 1
      return nil
    end
  end
end

class PokemonDataBox
  alias kif_bui_initializeDataBoxGraphic initializeDataBoxGraphic unless method_defined?(:kif_bui_initializeDataBoxGraphic)
  alias kif_bui_initializeOtherGraphics initializeOtherGraphics unless method_defined?(:kif_bui_initializeOtherGraphics)
  alias kif_bui_dispose dispose unless method_defined?(:kif_bui_dispose)
  alias kif_bui_x= x= unless method_defined?(:kif_bui_x=)
  alias kif_bui_y= y= unless method_defined?(:kif_bui_y=)
  alias kif_bui_z= z= unless method_defined?(:kif_bui_z=)
  alias kif_bui_refresh refresh unless method_defined?(:kif_bui_refresh)
  alias kif_bui_refreshExp refreshExp unless method_defined?(:kif_bui_refreshExp)
  alias kif_bui_drawEnemyTypeIcons drawEnemyTypeIcons unless method_defined?(:kif_bui_drawEnemyTypeIcons)

  def initializeDataBoxGraphic(sideSize)
    kif_bui_initializeDataBoxGraphic(sideSize)
    @kif_sideSize = sideSize
    @kif_gui = KIF::BattleUI.gui
    return if @kif_gui == 0
    name = (sideSize == 1) ? ["databox_normal", "databox_normal_foe"][@battler.index % 2] :
                             ["databox_thin", "databox_thin_foe"][@battler.index % 2]
    name += (@kif_gui == 1) ? "_M" : "_M2"
    name += "_darkmode" if @kif_gui == 1 && KIF::BattleUI.dark?
    file = KIF::BattleUI.path("BattleGUI/" + name)
    return unless file
    @databoxBitmap.dispose
    @databoxBitmap = AnimatedBitmap.new(file)
  end

  def initializeOtherGraphics(viewport)
    kif_bui_initializeOtherGraphics(viewport)
    if @kif_gui && @kif_gui != 0
      suffix = (@kif_gui == 1) ? "_M" : "_M2"
      hp  = KIF::BattleUI.path("BattleGUI/overlay_hp" + suffix)
      exp = KIF::BattleUI.path("BattleGUI/overlay_exp" + suffix)
      if hp
        @hpBarBitmap.dispose
        @hpBarBitmap = AnimatedBitmap.new(hp)
        @hpBar.bitmap = @hpBarBitmap.bitmap
        @hpBar.src_rect.height = @hpBarBitmap.height / 3
      end
      if exp
        @expBarBitmap.dispose
        @expBarBitmap = AnimatedBitmap.new(exp)
        @expBar.bitmap = @expBarBitmap.bitmap
      end
    end
    # Trapstarr's status icon fix: its own sprite, above the bars
    @kif_statusBitmap = AnimatedBitmap.new(KIF::BattleUI::STATUS_ICONS)
    @kif_statusIcon = SpriteWrapper.new(viewport)
    @kif_statusIcon.bitmap = @kif_statusBitmap.bitmap
    @kif_statusIcon.src_rect.set(0, 0, 0, 0)
    @sprites["kif_statusIcon"] = @kif_statusIcon
    # The base method already set the box's z and hid it before this sprite
    # existed: give it the box's layer, visibility and place now (it was left
    # at z 0 - behind the HP/Exp bars - and visible during the intro, 2026-10-14)
    @kif_statusIcon.z = kif_status_z(self.z)
    @kif_statusIcon.visible = self.visible
    @kif_statusIcon.x = self.x + @spriteBaseX + 24
    @kif_statusIcon.y = self.y + (@battler.opposes?(0) ? 49 : 52)
  end

  def dispose
    kif_bui_dispose
    @kif_statusBitmap.dispose if @kif_statusBitmap && !@kif_statusBitmap.disposed?
    @kif_typeBitmap.dispose if @kif_typeBitmap && !@kif_typeBitmap.disposed?
  end

  def kif_gui2_hp_offset
    return (@kif_sideSize.to_i > 1 || @battler.opposes?(0)) ? [31, 37 + (@kif_sideSize.to_i > 1 ? 0 : 1)] : [12, 38]
  end

  def x=(value)
    self.kif_bui_x = value
    if @kif_gui == 2
      @hpBar.x  = value + @spriteBaseX + kif_gui2_hp_offset[0]
      @expBar.x = value + @spriteBaseX - 25
    end
    @kif_statusIcon.x = value + @spriteBaseX + 24 if @kif_statusIcon
  end

  def y=(value)
    self.kif_bui_y = value
    if @kif_gui == 2
      @hpBar.y  = value + kif_gui2_hp_offset[1]
      @expBar.y = value + 60
    end
    @kif_statusIcon.y = value + (@battler.opposes?(0) ? 49 : 52) if @kif_statusIcon
  end

  def z=(value)
    self.kif_bui_z = value
    @kif_statusIcon.z = kif_status_z(value) if @kif_statusIcon
  end

  # the lower player-side box sits on the command box, which covered its tag's
  # bottom 4 px: that tag is drawn over the menu's edge (Cody picked B, 2026-10-26)
  def kif_status_z(box_z)
    return box_z + 2 if @battler.opposes?(0) || @battler.index < 2
    return [box_z + 2, 300].max
  end

  # PIF's own type icons give way to the Type Display. A foe disguised by
  # Illusion shows the types of the Pokémon it copies, as Battle Info and the
  # Fight menu's hints do (the base reads @battler's types).
  def drawEnemyTypeIcons(imagePos)
    return if KIF::BattleUI.type_display != 0
    real = @battler
    @battler = KIF::BattleInfo.face(real) unless real.is_a?(PokeBattle_FakeBattler)
    kif_bui_drawEnemyTypeIcons(imagePos)
  ensure
    @battler = real if real
  end

  # The base refresh draws its image list through this; the status icon is
  # left out while it runs (it has its own sprite here).
  def pbDrawImagePositions(bitmap, textpos)
    if @kif_skip_images && textpos.is_a?(Array)
      textpos = textpos.reject { |i| i.is_a?(Array) && @kif_skip_images.include?(i[0]) }
    end
    super(bitmap, textpos)
  end

  def refresh
    @kif_skip_images = [KIF::BattleUI::STATUS_ICONS]
    begin
      kif_bui_refresh
    ensure
      @kif_skip_images = nil
    end
    return if !@battler || !@battler.pokemon
    kif_draw_level_bsm
    kif_refresh_status
    kif_draw_type_display
  end

  # "Show Lv. in BSM" (base refresh skips the level in No-Levels mode)
  def kif_draw_level_bsm
    return unless $game_switches && $game_switches[SWITCH_NO_LEVELS_MODE]
    return unless $PokemonSystem.showlevel_nolevelmode.to_i == 1
    pbDrawImagePositions(self.bitmap, [["Graphics/Pictures/Battle/overlay_lv", @spriteBaseX + 140, 16]])
    pbDrawNumber(@battler.level, self.bitmap, @spriteBaseX + 162, 16)
  end

  # KIF refreshStatus (same row choice as the base refresh)
  def kif_refresh_status
    return unless @kif_statusIcon
    if !@battler.respond_to?(:status) || @battler.status == :NONE
      @kif_statusIcon.src_rect.set(0, 0, 0, 0)
      return
    end
    s = GameData::Status.get(@battler.status).id_number
    if s == :POISON && @battler.statusCount > 0 # Badly poisoned (as the base code)
      s = GameData::Status::DATA.keys.length / 2
    end
    @kif_statusIcon.src_rect.set(0, (s - 1) * STATUS_ICON_HEIGHT, @kif_statusBitmap.width, STATUS_ICON_HEIGHT)
  end

  # KIF drawtypeDisplay, drawn into the box (foes only)
  def kif_draw_type_display
    mode = KIF::BattleUI.type_display
    return if mode == 0
    return unless @battler.opposes?(0)
    return if @battler.is_a?(PokeBattle_FakeBattler)
    return if @battler.fainted?
    sheet = KIF::BattleUI::TYPE_SHEETS[mode]
    return unless sheet
    if !@kif_typeBitmap || @kif_typeBitmap.disposed? || @kif_typeSheet != sheet
      return unless pbResolveBitmap(sheet)   # disk probe only when the sheet changes
      @kif_typeBitmap.dispose if @kif_typeBitmap && !@kif_typeBitmap.disposed?
      @kif_typeBitmap = AnimatedBitmap.new(sheet)
      @kif_typeSheet = sheet
    end
    bmp = @kif_typeBitmap.bitmap
    # In-battle types like PIF's icons (KIF used the Pokémon's own
    # types); a foe disguised by Illusion: the Pokémon it copies
    shown = KIF::BattleInfo.face(@battler)
    type1 = shown.type1
    type2 = shown.type2
    text = (mode == 5)
    w, h = text ? [64, 28] : [24, 20]
    dw = text ? (w * 0.65).to_i : w
    dh = text ? (h * 0.65 * 1.2).to_i : h
    # KIF: x = spriteBaseX + hpBar.x + 185, y = hpBar.y + bar height - 43 (-40 text)
    hp_x, hp_y = (@kif_gui == 2) ? kif_gui2_hp_offset : [12, 40]
    x = @spriteBaseX + @spriteBaseX + hp_x + 185
    y = hp_y + @hpBar.src_rect.height - (text ? 40 : 43)
    [type1, type2].uniq.each_with_index do |t, i|
      n = GameData::Type.get(t).id_number
      next if (n + 1) * h > bmp.height
      dy = (i == 0) ? y : (text ? y + dh : y + 5 + dh)
      self.bitmap.stretch_blt(Rect.new(x, dy, dw, dh), bmp, Rect.new(0, n * h, w, h))
    end
  rescue => e
    KIF.log("Type Display failed: #{e.message}")
  end

  # Trapstarr's Exp bar patch: no crash on a NaN/infinite fraction.
  # KIF also stretched the GUI 2 bar x1.5 (full at ~67% Exp); not ported.
  def refreshExp
    f = @showExp ? exp_fraction : 0
    return kif_bui_refreshExp unless f.is_a?(Float) && (f.nan? || f.infinite?)
    @expBar.src_rect.width = 0
  end
end

#-------------------------------------------------------------------------------
# EBDX battle boxes (DataBoxEBDX, F-BATTLE-12): the foe's types as in PIF's
# box. 661/003 drew only the Type Display, from the Pokémon's own types, on a
# screen-sized sprite redrawn every frame, its second icon over the foe's
# status tag ("PS"). Here: PIF's own small type icons too ("Type icons" On,
# Type Display Off), the in-battle types (Soak, Transform...), the two icons
# side by side where 661's first one sat (the box's right end, above the
# status tag), on a box sprite (it moves, hides and fades with the box),
# redrawn only when the types change.
#-------------------------------------------------------------------------------
if defined?(::DataBoxEBDX)
  class ::DataBoxEBDX
    alias kif_bui_setUp setUp unless method_defined?(:kif_bui_setUp) || private_method_defined?(:kif_bui_setUp)
    alias kif_bui_refresh refresh unless method_defined?(:kif_bui_refresh) || private_method_defined?(:kif_bui_refresh)
    alias kif_bui_update update unless method_defined?(:kif_bui_update) || private_method_defined?(:kif_bui_update)

    def setUp
      kif_bui_setUp
      # 661/003's own Type Display sprite and sheet: this one replaces them
      @typeDisplaySprite.dispose if @typeDisplaySprite && !@typeDisplaySprite.disposed?
      @typeDisplaySprite = nil
      @typeDisplayBitmap.dispose if @typeDisplayBitmap && !@typeDisplayBitmap.disposed?
      @typeDisplayBitmap = nil
      @kif_types_key = nil
      return if @playerpoke
      s = Sprite.new(@viewport)
      s.z = getMetric("name", :z)
      s.ex = @sprites["base"].bitmap.width
      s.ey = -14
      @sprites["kif_types"] = s
    end

    def refresh
      kif_bui_refresh
      kif_draw_types
    end

    def update
      kif_bui_update
      kif_draw_types
    end

    # [sheet, icon w, icon h, drawn w, drawn h] for the foe's types, or nil
    def kif_types_sheet
      mode = KIF::BattleUI.type_display
      if mode == 0
        return nil unless $PokemonSystem && $PokemonSystem.type_icons
        return [KIF::BattleUI::PIF_TYPES, 19, 19, 19, 19]   # PIF's typesSmall
      end
      sheet = KIF::BattleUI::TYPE_SHEETS[mode]
      return nil unless sheet
      return [sheet, 64, 28, (64 * 0.65).to_i, (28 * 0.65 * 1.2).to_i] if mode == 5   # 661's Txt size
      return [sheet, 24, 20, 24, 20]
    end

    def kif_draw_types
      spr = @sprites["kif_types"]
      return unless spr && !spr.disposed? && @battler && @battler.pokemon
      geo = kif_types_sheet
      geo = nil if @battler.fainted? || (defined?(PokeBattle_FakeBattler) && @battler.is_a?(PokeBattle_FakeBattler))
      types = geo ? [@battler.type1, @battler.type2].uniq : []
      key = [geo && geo[0]] + types
      # a foe disguised by Illusion: the types of the Pokémon it copies (as
      # Battle Info); the disguise is in the key so face() runs only when it
      # changes, not every frame
      disguise = geo && KIF::BattleInfo.disguised?(@battler) && @battler.effects[PBEffects::Illusion]
      key << disguise if disguise
      return if key == @kif_types_key
      @kif_types_key = key
      if disguise
        shown = KIF::BattleInfo.face(@battler)
        types = [shown.type1, shown.type2].uniq
      end
      spr.bitmap.dispose if spr.bitmap && !spr.bitmap.disposed?
      spr.bitmap = nil
      return unless geo && pbResolveBitmap(geo[0])
      path, w, h, dw, dh = geo
      sheet = AnimatedBitmap.new(path)
      begin
        spr.bitmap = Bitmap.new(dw * 2 + 2, dh)
        types.each_with_index do |t, i|
          n = GameData::Type.get(t).id_number
          next if (n + 1) * h > sheet.height   # the icon sheets lack the triple-fusion types
          spr.bitmap.stretch_blt(Rect.new(i * (dw + 2), 0, dw, dh), sheet.bitmap, Rect.new(0, n * h, w, h))
        end
      ensure
        sheet.dispose
      end
      base = @sprites["base"]
      spr.x = base.x + spr.ex
      spr.y = base.y + spr.ey
    rescue => e
      KIF.log("EBDX type icons failed: #{e.message}")
      @kif_types_key = key
    end
  end
end

#-------------------------------------------------------------------------------
# Message box (KIF 007_Scene_Initialize.rb:29-53)
#-------------------------------------------------------------------------------
class PokeBattle_Scene
  alias kif_bui_pbInitSprites pbInitSprites unless method_defined?(:kif_bui_pbInitSprites)

  def pbInitSprites
    kif_bui_pbInitSprites
    begin
      art = KIF::BattleUI.message_box
      @sprites["messageBox"].setBitmap(art) if art && @sprites["messageBox"]
      win = @sprites["messageWindow"]
      return unless win
      if KIF::BattleUI.dark?
        win.baseColor   = KIF::BattleUI::DARK_TEXT_BASE
        win.shadowColor = PokeBattle_SceneConstants::MESSAGE_SHADOW_COLOR
      elsif KIF::BattleUI.gui == 2
        win.baseColor = KIF::BattleUI::GUI2_TEXT_BASE
      end
    rescue => e
      KIF.log("Battle message box art failed: #{e.message}")
    end
  end
end

#-------------------------------------------------------------------------------
# Command menu (KIF 005_PokeBattle_SceneMenus.rb:122-156)
#-------------------------------------------------------------------------------
class CommandMenuDisplay
  alias kif_bui_initialize initialize unless method_defined?(:kif_bui_initialize) || private_method_defined?(:kif_bui_initialize)

  def initialize(*args)
    kif_bui_initialize(*args)
    begin
      if KIF::BattleUI.dark?
        @msgBox.baseColor   = KIF::BattleUI::DARK_TEXT_BASE
        @msgBox.shadowColor = PokeBattle_SceneConstants::MESSAGE_SHADOW_COLOR
      end
      return unless USE_GRAPHICS
      bg = KIF::BattleUI.command_background
      @sprites["background"].setBitmap(bg) if bg && @sprites["background"]
      buttons = KIF::BattleUI.command_buttons
      if buttons && @buttons
        @buttonBitmap.dispose if @buttonBitmap
        @buttonBitmap = AnimatedBitmap.new(buttons)
        @buttons.each do |button|
          button.bitmap = @buttonBitmap.bitmap
          button.src_rect.width  = @buttonBitmap.width / 2
          button.src_rect.height = BUTTON_HEIGHT
        end
        refreshButtons
      end
    rescue => e
      KIF.log("Battle command menu art failed: #{e.message}")
    end
  end
end
