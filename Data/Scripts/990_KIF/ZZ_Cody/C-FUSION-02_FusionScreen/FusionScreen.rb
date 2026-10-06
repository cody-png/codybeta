#===============================================================================
# C-FUSION-02 – Fusion Screen (Cody)
# Cody Settings > Interface > "Fusion Screen" (Off/On, all saves, default On)
#
# The DNA Splicer preview (052_InfiniteFusion/Fusion/Menus/FusionPreviewScreen.rb)
# gets a new layout (Cody's approved mockup, 2026-10-06). For each side:
#   * the fusion's name, level and types;
#   * the stats it will really have: built from a copy of the Pokémon the
#     splicers would make (body keeps its EVs/nature/type override, IVs
#     averaged or the higher of the two with Super Splicers, fused level), so
#     No-EVs / Max IVs modes, custom fusion base stats, self-fusion boost,
#     Dominant Fusion Types and Type Override all show as they will be;
#   * the higher number of each stat pair (left vs right) is green;
#   * bars show the base stats (same colours as the Summary), plus the base
#     total.
# A (USE) on a fusion opens Change Body / Change Head / Confirm (Cody's
# mockup, 2026-10-06). Change Body/Head lists the part's current form and every
# later one (branches included) tagged Stage 1 / Stage 2 / Final; the preview
# follows the cursor and shows that fusion's sprite, name, types and stats at
# the fused level. The other side mirrors the choice (same pair, swapped).
# Confirm always fuses the current forms ("Fuse <name>" while previewing).
# The nature is the body's (the first choice on the next screen).
# Off = PIF's original screen.
#===============================================================================
KIF::Options.define(:cody_fusionscreen, 1, :global)

KIF::Options.add(:cody_interface, :global) {
  EnumOption.new(_INTL("Fusion Screen"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.cody_fusionscreen },
                 proc { |value| $PokemonSystem.cody_fusionscreen = value },
                 [_INTL("The DNA Splicers show PIF's original preview"),
                  _INTL("The DNA Splicers show names, real stats and evolution previews")])
}

module KIF
  module FusionScreen
    BOX_X     = [40, 296]
    BOX_Y     = 32
    BOX_W     = 176
    BOX_H     = 160
    SPRITE    = 144
    NAME_Y    = 192
    TYPES_Y   = 220
    STATS_Y   = 252
    STATS_H   = 78
    CANCEL_Y  = 326
    ARROW_Y   = -18
    ARROW_CANCEL_Y = 276
    STATS     = [[:HP, "HP"], [:ATTACK, "Atk"], [:DEFENSE, "Def"],
                 [:SPECIAL_ATTACK, "SpA"], [:SPECIAL_DEFENSE, "SpD"], [:SPEED, "Spe"]]
    WHITE     = Color.new(248, 248, 248)
    GREY      = Color.new(104, 104, 104)
    LABEL     = Color.new(216, 216, 216)
    DARK      = Color.new(64, 64, 64)
    BETTER    = Color.new(160, 248, 144)
    TOTAL     = Color.new(248, 248, 200)
    LV_BASE   = Color.new(96, 96, 96)
    LV_SHADOW = Color.new(208, 208, 208)
    PANEL     = Color.new(24, 40, 32, 170)
    BAR_BG    = Color.new(56, 56, 56)
    CHIP      = Color.new(64, 120, 200)
    CHIP_SH   = Color.new(32, 64, 120)
    HINT_BG   = Color.new(16, 24, 24, 235)
    MENU_TEXT = Color.new(80, 80, 88)
    MENU_SH   = Color.new(160, 160, 168)
    MENU_TITLE = Color.new(48, 96, 160)
    MENU_TITLE_SH = Color.new(176, 200, 224)
    MENU_BORDER = Color.new(72, 72, 80)
    MENU_FILL = Color.new(248, 248, 248)
    DIM       = Color.new(0, 0, 0, 110)
    MENU_ROW  = 30
    MENU_ROWS = 8

    def self.on?
      return $PokemonSystem && $PokemonSystem.cody_fusionscreen.to_i == 1
    end

    def self.bar_color(v)
      return Color.new(240, 80, 48)  if v < 60
      return Color.new(248, 192, 48) if v < 90
      return Color.new(120, 200, 80) if v < 120
      return Color.new(48, 168, 224)
    end

    # The species and every later evolution (breadth-first, branches included)
    def self.forward_line(species)
      out = [species]
      i = 0
      while i < out.size
        begin
          GameData::Species.get(out[i]).get_evolutions(true).each do |e|
            out << e[0] if GameData::Species.exists?(e[0]) && !out.include?(e[0])
          end
        rescue
        end
        i += 1
      end
      return out
    end

    # [[dex number, species], ...]: the Pokémon's form, then every later
    # evolution that can be fused
    def self.line(pkmn)
      cur = pkmn.species_data
      ret = [[cur.id_number, cur.species]]
      return ret if cur.id_number > NB_POKEMON
      forward_line(pkmn.species)[1..-1].each do |sp|
        n = GameData::Species.get(sp).id_number
        ret << [n, sp] if n <= NB_POKEMON
      end
      return ret
    end

    # "Stage 1", "Stage 2", ... or "Final" when nothing evolves from it
    def self.stage_tag(species)
      data = GameData::Species.get(species)
      return [_INTL("Final"), 0] if data.get_evolutions(true).empty?
      n = 1
      seen = [data.species]
      loop do
        prev = data.get_previous_species
        break if prev.nil? || seen.include?(prev)
        seen << prev
        data = GameData::Species.get(prev)
        n += 1
      end
      return [_INTL("Stage {1}", n), n]
    end

    TAG_COLORS = { 0 => Color.new(200, 72, 72), 1 => Color.new(120, 168, 88),
                   2 => Color.new(216, 152, 48), 3 => Color.new(152, 104, 200) }

    # The Pokémon the splicers would make (PokemonFusion#pbFusionScreen:
    # setFusionIVs, species change, owner, setPokemonLevel), with dex = the
    # fused species to show.
    def self.ghost(body, head, dex, level, supersplicers)
      g = body.clone
      GameData::Stat.each_main do |s|
        a = body.iv[s.id] || 0
        b = head.iv[s.id] || 0
        g.iv[s.id] = supersplicers ? [a, b].max : ((a + b) / 2).floor
      end
      g.species = dex
      g.level = level
      g.owner = Pokemon::Owner.new_from_trainer($Trainer) if $Trainer
      g.obtain_method = 0
      g.calc_stats
      return g
    end
  end
end

class FusionPreviewScreen
  alias cody_fs_initialize initialize unless method_defined?(:cody_fs_initialize)

  def initialize(poke1, poke2, usingSuperSplicers = false)
    if KIF::FusionScreen.on?
      begin
        cody_fs_build(poke1, poke2, usingSuperSplicers)
        return
      rescue => e
        KIF.log("Fusion Screen failed, using PIF's: #{e.class}: #{e.message}")
        cody_fs_teardown
      end
    end
    cody_fs_initialize(poke1, poke2, usingSuperSplicers)
  end

  #-----------------------------------------------------------------------------
  # Building
  #-----------------------------------------------------------------------------
  def cody_fs_build(poke1, poke2, ss)
    @cody_fs = { :bitmaps => {}, :ghosts => {} }
    DoublePreviewScreen.instance_method(:initialize).bind(self).call(poke1, poke2)
    fs = KIF::FusionScreen
    @poke1 = poke1
    @poke2 = poke2
    @fusedPokemon = nil
    @cody_ss = ss
    @cody_level = calculateFusedPokemonLevel(poke1.level, poke2.level, ss)
    @cody_lines = [fs.line(poke1), fs.line(poke2)]   # [poke1 forms, poke2 forms]
    @cody_pick = [0, 0]                               # index in each line
    @cody_vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @cody_vp.z = 100000
    @viewport_evo = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport_evo.z = 100001
    @cody_mon = []
    [0, 1].each do |pos|
      box = Sprite.new(@cody_vp)
      box.bitmap = cody_fs_box_bitmap
      box.x = fs::BOX_X[pos]
      box.y = fs::BOX_Y
      pos == 0 ? @picture1 = box : @picture2 = box
      mon = Sprite.new(@cody_vp)
      mon.z = 1
      @cody_mon[pos] = mon
      # Selection sprite + UP-hold evolution icons: the current fusion
      dex = cody_fs_dex(pos)
      body_id = getBodyID(dex)
      head_id = getHeadID(dex, body_id)
      pif = BattleSpriteLoader.new.obtain_fusion_pif_sprite(head_id, body_id)
      pos == 0 ? @sprite_left = pif : @sprite_right = pif
      drawEvolutionIcons(dex, @viewport_evo, fs::BOX_X[pos] + 4, fs::BOX_Y + 6, pos)
    end
    @cody_overlay = BitmapSprite.new(Graphics.width, Graphics.height, @cody_vp)
    @cody_overlay.z = 2
    @cody_types = AnimatedBitmap.new("Graphics/Pictures/types")
    @cody_hint = BitmapSprite.new(92, 28, @cody_vp)
    @cody_hint.y = 4
    @cody_hint.z = 3
    cody_fs_hint
    @cody_dim = Sprite.new(@cody_vp)
    @cody_dim.bitmap = Bitmap.new(256, Graphics.height)
    @cody_dim.bitmap.fill_rect(0, 0, 256, Graphics.height, fs::DIM)
    @cody_dim.z = 5
    @cody_dim.visible = false
    @cody_menu = BitmapSprite.new(Graphics.width, Graphics.height, @cody_vp)
    @cody_menu.z = 6
    @cody_sel = IconSprite.new(0, 0, @cody_vp)
    @cody_sel.setBitmap("Graphics/Pictures/selarrow")
    @cody_sel.z = 7
    @cody_sel.visible = false
    @sprites["cancel"].y = fs::CANCEL_Y
    @sprites["arrow"].y = fs::ARROW_Y
    cody_fs_refresh
    hideAllEvoIcons
  end

  def cody_fs_box_bitmap
    fs = KIF::FusionScreen
    return cody_fs_frame(fs::BOX_W, fs::BOX_H)
  end

  # White frame like the mockups (dark border, rounded corners)
  def cody_fs_frame(w, h, bmp = nil, x = 0, y = 0)
    fs = KIF::FusionScreen
    bmp ||= Bitmap.new(w, h)
    border = fs::MENU_BORDER
    bmp.fill_rect(x + 4, y, w - 8, h, border)
    bmp.fill_rect(x, y + 4, w, h - 8, border)
    bmp.fill_rect(x + 2, y + 2, w - 4, h - 4, border)
    bmp.fill_rect(x + 4, y + 4, w - 8, h - 8, fs::MENU_FILL)
    return bmp
  end

  #-----------------------------------------------------------------------------
  # Which fusion each side shows
  #   side 0 = body poke1 / head poke2, side 1 = body poke2 / head poke1
  #-----------------------------------------------------------------------------
  def cody_fs_form(which, pick = nil)
    pick ||= @cody_pick
    return @cody_lines[which][pick[which]]
  end

  def cody_fs_dex(pos, pick = nil)
    a = cody_fs_form(0, pick)[0]
    b = cody_fs_form(1, pick)[0]
    return pos == 0 ? a * NB_POKEMON + b : b * NB_POKEMON + a
  end

  def cody_fs_previewing?
    return @cody_pick != [0, 0]
  end

  def cody_fs_parents(pos)
    return pos == 0 ? [@poke1, @poke2] : [@poke2, @poke1]
  end

  # Line index (0 = poke1, 1 = poke2) of a side's body / head
  def cody_fs_part(pos, part)
    return (pos == 0) == (part == :body) ? 0 : 1
  end

  def cody_fs_ghost(pos)
    dex = cody_fs_dex(pos)
    key = [pos, dex]
    return @cody_fs[:ghosts][key] if @cody_fs[:ghosts][key]
    body, head = cody_fs_parents(pos)
    g = KIF::FusionScreen.ghost(body, head, dex, @cody_level, @cody_ss)
    @cody_fs[:ghosts][key] = g
    return g
  end

  # Fusion sprite with the colours it will have (same rules as the preview:
  # F-FUSION-03 KIF colours or PIF's palette)
  def cody_fs_bitmap(pos)
    dex = cody_fs_dex(pos)
    key = [pos, dex]
    return @cody_fs[:bitmaps][key] if @cody_fs[:bitmaps].key?(key)
    body, head = cody_fs_parents(pos)
    shiny = body.isShiny? || head.isShiny?
    look = nil
    if shiny && defined?(KIF::Shiny) && defined?(KIF::FusionPreview)
      look = KIF::FusionPreview.look_for(dex, body, head)
      look = nil if look && !KIF::Shiny.decide(look)[1]
    end
    if look
      old = KIF::FusionPreview.color
      KIF::FusionPreview.color = [dex, look]
      begin
        ab = GameData::Species.front_sprite_bitmap(dex)
      ensure
        KIF::FusionPreview.color = old
      end
    else
      ab = GameData::Species.front_sprite_bitmap(dex)
      ab.shiftAllColors(dex, body.isShiny?, head.isShiny?) if ab
    end
    @cody_fs[:bitmaps][key] = ab
    return ab
  end

  def cody_fs_tint(dex)
    revealed = defined?(KIF::FusionPreview) && KIF::FusionPreview.on?
    return nil if revealed || $Trainer.seen?(dex)
    body_id = getBodyID(dex)
    head_id = getHeadID(dex, body_id)
    pif = BattleSpriteLoader.new.obtain_fusion_pif_sprite(head_id, body_id)
    return Color.new(170, 200, 250, 200) if pif && pif.local_path
    return Color.new(150, 255, 150, 200) if customSpriteExists(body_id, head_id)
    return Color.new(255, 255, 255, 200)
  end

  #-----------------------------------------------------------------------------
  # Drawing
  #-----------------------------------------------------------------------------
  def cody_fs_refresh
    fs = KIF::FusionScreen
    ov = @cody_overlay.bitmap
    ov.clear
    ghosts = [cody_fs_ghost(0), cody_fs_ghost(1)]
    [0, 1].each do |pos|
      g = ghosts[pos]
      bx = fs::BOX_X[pos]
      ox = pos * 256
      # Sprite
      ab = cody_fs_bitmap(pos)
      mon = @cody_mon[pos]
      if ab && ab.bitmap
        mon.bitmap = ab.bitmap
        zoom = fs::SPRITE.to_f / [ab.bitmap.width, 1].max
        mon.zoom_x = mon.zoom_y = zoom
        mon.x = bx + (fs::BOX_W - (ab.bitmap.width * zoom).round) / 2
        mon.y = fs::BOX_Y + (fs::BOX_H - (ab.bitmap.height * zoom).round) / 2
        tint = cody_fs_tint(cody_fs_dex(pos))
        mon.color = tint || Color.new(0, 0, 0, 0)
      else
        mon.bitmap = nil
      end
      # Level, preview tag, name
      pbSetSystemFont(ov)
      text = [[_INTL("Lv. {1}", @cody_level), bx + 12, fs::BOX_Y + 4, 0, fs::LV_BASE, fs::LV_SHADOW],
              [g.speciesName, ox + 128, fs::NAME_Y - 8, 2, fs::WHITE, fs::GREY]]
      pbDrawTextPositions(ov, text)
      if cody_fs_previewing?
        ov.fill_rect(bx + 84, fs::BOX_Y + fs::BOX_H - 26, 84, 18, fs::CHIP)
        pbSetSmallFont(ov)
        pbDrawTextPositions(ov, [[_INTL("Preview"), bx + 126, fs::BOX_Y + fs::BOX_H - 32, 2,
                                  fs::WHITE, fs::CHIP_SH]])
      end
      # Types
      t1 = g.type1
      t2 = g.type2
      n1 = GameData::Type.get(t1).id_number
      if t2.nil? || t1 == t2
        ov.blt(ox + 32 + 33, fs::TYPES_Y, @cody_types.bitmap, Rect.new(0, n1 * 28, 64, 28))
      else
        n2 = GameData::Type.get(t2).id_number
        ov.blt(ox + 32, fs::TYPES_Y, @cody_types.bitmap, Rect.new(0, n1 * 28, 64, 28))
        ov.blt(ox + 32 + 66, fs::TYPES_Y, @cody_types.bitmap, Rect.new(0, n2 * 28, 64, 28))
      end
      cody_fs_stats(ov, ox + 16, g, ghosts[1 - pos])
    end
  end

  def cody_fs_stat_values(g)
    return { :HP => g.totalhp, :ATTACK => g.attack, :DEFENSE => g.defense,
             :SPECIAL_ATTACK => g.spatk, :SPECIAL_DEFENSE => g.spdef, :SPEED => g.speed }
  end

  def cody_fs_stats(ov, x, g, other)
    fs = KIF::FusionScreen
    y = fs::STATS_Y
    ov.fill_rect(x + 2, y, 220, fs::STATS_H, fs::PANEL)
    ov.fill_rect(x, y + 2, 2, fs::STATS_H - 4, fs::PANEL)
    ov.fill_rect(x + 222, y + 2, 2, fs::STATS_H - 4, fs::PANEL)
    mine = cody_fs_stat_values(g)
    theirs = cody_fs_stat_values(other)
    base = g.respond_to?(:kif_effective_base_stats) ? g.kif_effective_base_stats : g.baseStats
    pbSetSmallFont(ov)
    text = []
    total = 0
    fs::STATS.each_with_index do |(id, label), i|
      cx = x + 8 + (i / 3) * 110
      cy = y + 3 + (i % 3) * 18
      v = mine[id]
      text << [label, cx, cy - 7, 0, fs::LABEL, fs::DARK]
      text << [v.to_s, cx + 68, cy - 7, 1, (v > theirs[id]) ? fs::BETTER : fs::WHITE, fs::DARK]
      b = base[id] || 0
      total += b
      ov.fill_rect(cx + 72, cy + 5, 31, 6, fs::BAR_BG)
      w = [[b * 30 / 150, 30].min, 1].max
      ov.fill_rect(cx + 72, cy + 5, w, 6, fs.bar_color(b))
    end
    text << [_INTL("Base total {1}", total), x + 112, y + 47, 2, fs::TOTAL, fs::DARK]
    pbDrawTextPositions(ov, text)
  end

  def cody_fs_hint
    bmp = @cody_hint.bitmap
    bmp.clear
    bmp.fill_rect(0, 0, bmp.width, bmp.height, KIF::FusionScreen::HINT_BG)
    pbSetSmallFont(bmp)
    pbDrawTextPositions(bmp, [[_INTL("A: Options"), 6, -4, 0,
                               KIF::FusionScreen::LABEL, Color.new(48, 48, 48)]])
  end

  #-----------------------------------------------------------------------------
  # Menus
  #-----------------------------------------------------------------------------
  # rows: [[text, tag text or nil, tag colour key, current?], ...]
  # Returns the chosen index or -1. on_move is called with the cursor index.
  def cody_fs_list(pos, rows, index, title = nil, w = 196, y = 60, &on_move)
    fs = KIF::FusionScreen
    x = (pos == 0) ? 256 + (256 - w) / 2 : (256 - w) / 2
    @cody_dim.x = (pos == 0) ? 256 : 0
    @cody_dim.visible = true
    visible = [rows.size, fs::MENU_ROWS].min
    top = 0
    draw = lambda do
      top = index - visible + 1 if index >= top + visible
      top = index if index < top
      bmp = @cody_menu.bitmap
      bmp.clear
      head = title ? 30 : 0
      h = 16 + head + visible * fs::MENU_ROW
      cody_fs_frame(w, h, bmp, x, y)
      if title
        pbSetSmallFont(bmp)
        pbDrawTextPositions(bmp, [[title, x + w / 2, y, 2, fs::MENU_TITLE, fs::MENU_TITLE_SH]])
        bmp.fill_rect(x + 10, y + 32, w - 20, 2, Color.new(200, 200, 208))
      end
      visible.times do |i|
        r = rows[top + i]
        ry = y + 8 + head + i * fs::MENU_ROW
        pbSetSystemFont(bmp)
        pbDrawTextPositions(bmp, [[r[0], x + 32, ry - 6, 0, fs::MENU_TEXT, fs::MENU_SH]])
        if r[1]
          col = fs::TAG_COLORS[r[2]] || fs::TAG_COLORS[3]
          tx = x + w - 76
          bmp.fill_rect(tx, ry + 6, 64, 18, col)
          sh = Color.new(col.red / 2, col.green / 2, col.blue / 2)
          pbSetSmallFont(bmp)
          pbDrawTextPositions(bmp, [[r[1], tx + 32, ry - 1, 2, fs::WHITE, sh]])
          bmp.fill_rect(tx - 12, ry + 12, 6, 6, fs::MENU_TITLE) if r[3]
        end
      end
      # Scroll marks
      bmp.fill_rect(x + w / 2 - 6, y + head + 6, 12, 2, fs::MENU_BORDER) if top > 0
      bmp.fill_rect(x + w / 2 - 6, y + h - 8, 12, 2, fs::MENU_BORDER) if top + visible < rows.size
      @cody_sel.x = x + 10
      @cody_sel.y = y + 8 + head + (index - top) * fs::MENU_ROW + 4
      @cody_sel.visible = true
    end
    draw.call
    ret = -1
    loop do
      Graphics.update
      Input.update
      old = index
      if Input.repeat?(Input::UP)
        index = (index - 1) % rows.size
      elsif Input.repeat?(Input::DOWN)
        index = (index + 1) % rows.size
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        ret = index
        break
      elsif Input.trigger?(Input::BACK)
        pbPlayCancelSE
        break
      end
      if index != old
        pbPlayCursorSE
        on_move.call(index) if on_move
        draw.call
      end
    end
    @cody_menu.bitmap.clear
    @cody_sel.visible = false
    @cody_dim.visible = false
    return ret
  end

  # Change Body / Change Head / Confirm. Returns true to fuse.
  def cody_fs_menu(pos)
    index = 0
    loop do
      confirm = cody_fs_previewing? ? _INTL("Fuse {1}", cody_fs_current_name(pos)) : _INTL("Confirm")
      rows = [[_INTL("Change Body")], [_INTL("Change Head")], [confirm]]
      w = [196, @cody_menu.bitmap.text_size(confirm).width + 56].max rescue 196
      index = cody_fs_list(pos, rows, index, nil, [w, 248].min)
      case index
      when 0 then cody_fs_change(pos, :body)
      when 1 then cody_fs_change(pos, :head)
      when 2 then return true
      else return false
      end
    end
  end

  def cody_fs_current_name(pos)
    return GameData::Species.get(cody_fs_dex(pos, [0, 0])).real_name
  end

  def cody_fs_change(pos, part)
    fs = KIF::FusionScreen
    which = cody_fs_part(pos, part)
    line = @cody_lines[which]
    rows = line.map.with_index do |(dex, sp), i|
      tag, n = fs.stage_tag(sp)
      [GameData::Species.get(sp).real_name, tag, n, i == 0]
    end
    old = @cody_pick.dup
    title = (part == :body) ? _INTL("Body") : _INTL("Head")
    choice = cody_fs_list(pos, rows, @cody_pick[which], title, 240, 40) do |i|
      @cody_pick[which] = i
      cody_fs_safe_refresh(old)
    end
    if choice < 0
      @cody_pick = old
    else
      @cody_pick[which] = choice
    end
    cody_fs_safe_refresh(old)
  end

  def cody_fs_safe_refresh(fallback)
    cody_fs_refresh
  rescue => e
    KIF.log("Fusion Screen preview failed: #{e.class}: #{e.message}")
    @cody_pick = fallback.dup
    cody_fs_refresh
  end

  #-----------------------------------------------------------------------------
  # Selection
  #-----------------------------------------------------------------------------
  def startSelection
    return super unless @cody_fs
    loop do
      Graphics.update
      Input.update
      updateSelection
      if Input.trigger?(Input::USE)
        return @selected if @selected < 0
        pbPlayDecisionSE
        if cody_fs_menu(@selected)
          return @selected
        end
      elsif Input.trigger?(Input::BACK)
        return -1
      end
    end
  end

  def updateSelectionGraphics
    super
    return unless @cody_fs
    fs = KIF::FusionScreen
    @sprites["arrow"].y = (@selected == -1) ? fs::ARROW_CANCEL_Y : fs::ARROW_Y
  end

  def dispose
    return super unless @cody_fs
    cody_fs_teardown
  end

  def cody_fs_teardown
    fs = @cody_fs
    @cody_fs = nil
    return unless fs
    @cody_mon.each { |s| s.dispose if s && !s.disposed? } if @cody_mon
    [@cody_overlay, @cody_hint, @cody_menu, @cody_sel].each { |s| s.dispose if s && !s.disposed? }
    if @cody_dim && !@cody_dim.disposed?
      @cody_dim.bitmap.dispose if @cody_dim.bitmap
      @cody_dim.dispose
    end
    fs[:bitmaps].each_value { |ab| ab.dispose if ab rescue nil }
    @cody_types.dispose if @cody_types
    [@picture1, @picture2].each do |pic|
      next unless pic && !pic.disposed?
      pic.bitmap.dispose if pic.bitmap rescue nil
      pic.dispose
    end
    @picture1 = @picture2 = nil
    pbDisposeSpriteHash(@sprites) if @sprites
    @sprites = {}
    @typewindows = []
    @viewport_evo.dispose if @viewport_evo && !@viewport_evo.disposed?
    @cody_vp.dispose if @cody_vp && !@cody_vp.disposed?
    @cody_mon = @cody_overlay = @cody_hint = @cody_types = @viewport_evo = @cody_vp = nil
    @cody_menu = @cody_sel = @cody_dim = nil
  end
end
