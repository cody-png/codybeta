#===============================================================================
# F-POKE-06 (part) – Evolution tree in the Pokédex entry box (port addition,
# Cody 2026-10-05, from a friend's suggestion; mock-ups: Bulbapedia's
# Poliwag and Eevee charts)
#
# Option "Dex Evolutions" (Others, global):
#   Credits Box (default) – the text lines of DexEvolutions.rb replace the
#                           sprite/entry credits (unchanged).
#   Entry Box             – Run (ACTION) cycles the Pokédex entry box:
#                           entry text -> evolution chart -> entry text.
#                           For a fusion: entry -> head's line -> body's line.
# The chart shows the whole family from its first stage, with the species
# you're viewing outlined in green. Arrows carry how the evolution happens
# with the item's icon (Rare Candy for levels, Soothe Bell for friendship, the
# stone / held item for item methods).
#   Up to two end branches (Poliwag: Poliwrath / Politoed): left to right.
#   More branches (Eevee): the first stage on top, its evolutions in a row
#   below, four per page; Confirm (C) turns the page (shown in the title bar).
#===============================================================================
KIF::Options.define(:dexevoview, 0, :global)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Dex Evolutions"), [_INTL("Credits Box"), _INTL("Entry Box")],
                 proc { $PokemonSystem.dexevoview },
                 proc { |value| $PokemonSystem.dexevoview = value },
                 [_INTL("Run on the Pokédex info page swaps the credits for evolution lines"),
                  _INTL("Run on the Pokédex info page shows an evolution chart in the entry box")])
}

module KIF
  module DexTree
    BOX_X = 36
    BOX_Y = 242
    BOX_W = 440
    BOX_H = 124
    GREEN = [32, 168, 64]
    PER_PAGE = 4

    @state = 0    # 0 entry text, 1 chart (head line), 2 body line (fusions)
    @page = 0
    class << self
      attr_accessor :state, :page
    end

    def self.entry_mode?
      return $PokemonSystem && $PokemonSystem.dexevoview.to_i == 1
    end

    def self.showing?
      return entry_mode? && @state > 0
    end

    #---------------------------------------------------------------------------
    # Family data
    #---------------------------------------------------------------------------
    def self.root_of(species)
      sp = species
      10.times do
        prev = GameData::Species.get(sp).get_previous_species
        break if prev.nil? || prev == sp
        sp = prev
      end
      return sp
    end

    # { :sp => Symbol, :kids => [[node, method, param], ...] }
    def self.tree(species, depth = 0)
      data = GameData::Species.get(species)
      node = { :sp => data.species, :kids => [] }
      return node if depth > 3
      data.get_evolutions(true).each do |evo|
        next unless (GameData::Species.get(evo[0]) rescue nil)
        node[:kids] << [tree(evo[0], depth + 1), evo[1], evo[2]]
      end
      return node
    end

    def self.leaves(node)
      return 1 if node[:kids].empty?
      return node[:kids].sum { |k| leaves(k[0]) }
    end

    def self.depth(node)
      return 1 if node[:kids].empty?
      return 1 + node[:kids].map { |k| depth(k[0]) }.max
    end

    WHEN = { "Day" => "day", "Night" => "night", "Morning" => "morning",
             "Afternoon" => "afternoon", "Evening" => "evening", "Male" => "♂", "Female" => "♀" }

    def self.when_word(method)
      WHEN.each { |k, v| return v if method.to_s.end_with?(k) }
      return nil
    end

    # [[up to 2 short lines], item icon or nil] for an evolution method
    def self.method_label(method, param)
      m = method.to_s
      w = when_word(method)
      if m.start_with?("Level")
        extra = w || ((method == :Level) ? nil : _INTL("special"))
        return [[_INTL("Lv {1}", param), extra].compact, :RARECANDY]
      elsif method == :HappinessMoveType
        type = (GameData::Type.get(param).name rescue param.to_s)
        return [[type], :SOOTHEBELL]
      elsif m.start_with?("Happiness") || method == :MaxHappiness
        return [[w].compact, :SOOTHEBELL]
      elsif method == :TradeItem
        return [[_INTL("Trade")], param]
      elsif m.start_with?("Trade")
        return [[_INTL("Trade"), w].compact, nil]
      elsif m.start_with?("Item")
        return [[w].compact, param]
      elsif m.include?("HoldItem")
        return [[_INTL("Hold"), w].compact, param]
      elsif method == :HasMove
        return [[_INTL("Knows"), KIF::DexEvolutions.move_name(param)], nil]
      end
      # Other methods with a level (Wurmple's Silcoon/Cascoon, ...)
      level_based = [:Silcoon, :Cascoon, :AttackGreater, :DefenseGreater, :AtkDefEqual, :Ninjask, :Shedinja]
      return [[_INTL("Lv {1}", param)], :RARECANDY] if level_based.include?(method) && param.is_a?(Integer)
      return [[KIF::DexEvolutions.method_text(method, param)], nil]
    end

    #---------------------------------------------------------------------------
    # Layout: returns [commands, page count]. Commands:
    #   [:icon, species, x, y, size]   [:item, item, x, y, size]
    #   [:text, string, x, y, align]   [:arrow, x1, y1, x2, y2]
    #   [:rect, x, y, w, h]            (green outline)
    # width: proc { |string| pixel width in the small font }
    #---------------------------------------------------------------------------
    def self.layout(root, current, page, width)
      if leaves(root) <= 2 && depth(root) <= 3
        return [horizontal(root, current, width), 1]
      end
      return vertical(root, current, page, width)
    end

    def self.fit(text, max, width)
      return text if width.call(text) <= max
      t = text.dup
      t = t[0...-1] while t.length > 1 && width.call(t + "..") > max
      return t + ".."
    end

    def self.node_cmds(cmds, sp, x, y, size, node_w, current, width)
      cmds << [:icon, sp, x + (node_w - size) / 2, y, size]
      name = fit(GameData::Species.get(sp).name, node_w, width)
      cmds << [:text, name, x + node_w / 2, y + size - 2, 2]
      cmds << [:rect, x - 2, y - 1, node_w + 4, size + 18] if sp == current
    end

    def self.horizontal(root, current, width)
      cmds = []
      cols = depth(root)
      node_w = 100
      if cols == 1
        node_cmds(cmds, root[:sp], BOX_X + (BOX_W - node_w) / 2, BOX_Y + 12, 48, node_w, current, width)
        cmds << [:text, _INTL("Does not evolve"), BOX_X + BOX_W / 2, BOX_Y + 88, 2]
        return cmds
      end
      gap = (BOX_W - cols * node_w) / (cols - 1)
      two_rows = leaves(root) == 2
      size = two_rows ? 44 : 48
      row_y = two_rows ? [BOX_Y, BOX_Y + 62] : [BOX_Y + 29]
      place = lambda do |node, col, first_leaf|
        rows = (first_leaf...(first_leaf + leaves(node))).to_a
        y = rows.map { |r| row_y[r] }.sum / rows.length
        x = BOX_X + col * (node_w + gap)
        node_cmds(cmds, node[:sp], x, y, size, node_w, current, width)
        leaf = first_leaf
        node[:kids].each do |kid, method, param|
          kn = leaves(kid)
          krows = (leaf...(leaf + kn)).to_a
          ky = krows.map { |r| row_y[r] }.sum / krows.length
          x1 = x + node_w / 2 + size / 2 + 2
          y1 = y + size / 2
          x2 = x + node_w + gap + node_w / 2 - size / 2 - 4
          y2 = ky + size / 2
          cmds << [:arrow, x1, y1, x2, y2]
          lines, icon = method_label(method, param)
          lines = lines.map { |l| fit(l, x2 - x1 + 20, width) }
          mx = (x1 + x2) / 2
          my = (y1 + y2) / 2
          if y1 == y2 && !two_rows
            cmds << [:item, icon, mx - 12, my - 26, 24] if icon
            lines.each_with_index { |l, i| cmds << [:text, l, mx, my + 2 + i * 18, 2] }
          else
            # diagonal (or two-row): icon and text side by side, outside the line
            up = y2 < y1
            straight = (y1 == y2)
            isz = straight ? 20 : 24   # two-row straight arrows: label just above the line
            tw = lines.map { |l| width.call(l) }.max || 0
            rowh = [icon ? isz : 0, lines.length * 18].max
            top = straight ? my - 2 - rowh : (up ? my - 8 - rowh : my + 6)
            top = [[top, BOX_Y].max, BOX_Y + BOX_H - rowh].min
            lx = mx + (straight ? 0 : 4) - ((icon ? isz + 2 : 0) + tw) / 2
            if icon
              cmds << [:item, icon, lx, top + (rowh - isz) / 2, isz]
              lx += isz + 2
            end
            lines.each_with_index { |l, i| cmds << [:text, l, lx, top + (rowh - lines.length * 18) / 2 + i * 18, 0] }
          end
          place.call(kid, col + 1, leaf)
          leaf += kn
        end
      end
      place.call(root, 0, 0)
      return cmds
    end

    def self.vertical(root, current, page, width)
      cmds = []
      kids = root[:kids]
      pages = [(kids.length + PER_PAGE - 1) / PER_PAGE, 1].max
      page = page % pages
      size = 40
      # first stage: icon with its name to the right
      name = GameData::Species.get(root[:sp]).name
      nw = width.call(name)
      x = BOX_X + (BOX_W - (size + 4 + nw)) / 2
      cmds << [:icon, root[:sp], x, BOX_Y, size]
      cmds << [:text, name, x + size + 4, BOX_Y + 10, 0]
      cmds << [:rect, x - 2, BOX_Y - 1, size + 8 + nw, size + 2] if root[:sp] == current
      slot = BOX_W / PER_PAGE
      kids[page * PER_PAGE, PER_PAGE].each_with_index do |(kid, method, param), i|
        sx = BOX_X + i * slot
        lines, icon = method_label(method, param)
        label = fit(lines.join(" "), slot - (icon ? 26 : 6), width)
        lw = width.call(label) + (icon ? 22 : 0)
        lx = sx + (slot - lw) / 2
        if icon
          cmds << [:item, icon, lx, BOX_Y + 42, 20]
          lx += 22
        end
        cmds << [:text, label, lx, BOX_Y + 43, 0] if label != ""
        node_cmds(cmds, kid[:sp], sx + 2, BOX_Y + 63, size, slot - 4, current, width)
      end
      return [cmds, pages]
    end

    #---------------------------------------------------------------------------
    # Which family to show for the current state
    #---------------------------------------------------------------------------
    def self.subject(species_data)
      if species_data.is_a?(GameData::FusedSpecies) && species_data.head_pokemon && species_data.body_pokemon
        part = (@state == 2) ? species_data.body_pokemon : species_data.head_pokemon
        return [part.species, (@state == 2) ? _INTL("Body") : _INTL("Head")]
      end
      return [species_data.species, nil]
    end

    def self.fusion?(species_data)
      return species_data.is_a?(GameData::FusedSpecies) && species_data.head_pokemon && species_data.body_pokemon
    end

    # Run: entry -> chart (-> body chart for fusions) -> entry
    def self.advance(species_data)
      @page = 0
      if @state == 0
        @state = 1
      elsif @state == 1 && fusion?(species_data)
        @state = 2
      else
        @state = 0
      end
    end

    #---------------------------------------------------------------------------
    # Drawing
    #---------------------------------------------------------------------------
    @bitmaps = {}

    def self.bitmap(path)
      return nil unless path
      return @bitmaps[path] if @bitmaps[path] && !@bitmaps[path].disposed?
      @bitmaps[path] = Bitmap.new(path) rescue nil
      return @bitmaps[path]
    end

    def self.draw_line(bmp, x1, y1, x2, y2, color)
      steps = [(x2 - x1).abs, (y2 - y1).abs, 1].max
      (0..steps).each do |i|
        x = x1 + (x2 - x1) * i / steps
        y = y1 + (y2 - y1) * i / steps
        bmp.fill_rect(x, y, 2, 2, color)
      end
    end

    def self.draw_arrow(bmp, x1, y1, x2, y2, color)
      draw_line(bmp, x1, y1, x2, y2, color)
      len = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
      return if len <= 0
      ux = (x2 - x1) / len
      uy = (y2 - y1) / len
      [[-0.5, 1], [0.5, 1]].each do |side, _|
        hx = x2 - (ux * 8) + (-uy * 5 * (side < 0 ? -1 : 1))
        hy = y2 - (uy * 8) + (ux * 5 * (side < 0 ? -1 : 1))
        draw_line(bmp, x2, y2, hx.round, hy.round, color)
      end
    end

    def self.draw(bmp, species_data, current, base, shadow)
      sp, part_label = subject(species_data)
      root = tree(root_of(sp))
      pbSetSmallFont(bmp)
      width = proc { |t| bmp.text_size(t).width }
      cmds, pages = layout(root, sp, @page, width)
      @pages = pages
      green = Color.new(*GREEN)
      line = Color.new(base.red, base.green, base.blue)
      texts = []
      cmds.each do |c|
        case c[0]
        when :icon
          src = bitmap(GameData::Species.icon_filename(c[1]))
          # icons are 64x64 frames with empty margins: use the middle 48x48
          bmp.stretch_blt(Rect.new(c[2], c[3], c[4], c[4]), src, Rect.new(8, 8, 48, 48)) if src
        when :item
          src = bitmap(GameData::Item.icon_filename(c[1]))
          bmp.stretch_blt(Rect.new(c[2], c[3], c[4], c[4]), src, Rect.new(0, 0, src.width, src.height)) if src
        when :arrow
          draw_arrow(bmp, c[1], c[2], c[3], c[4], line)
        when :rect
          x, y, w, h = c[1], c[2], c[3], c[4]
          bmp.fill_rect(x, y, w, 2, green)
          bmp.fill_rect(x, y + h - 2, w, 2, green)
          bmp.fill_rect(x, y, 2, h, green)
          bmp.fill_rect(x + w - 2, y, 2, h, green)
        when :text
          texts << [c[1], c[2], c[3], c[4], base, shadow]
        end
      end
      pbDrawTextPositions(bmp, texts)
      pbSetSystemFont(bmp)
      return [part_label, pages]
    end

    def self.pages
      return @pages || 1
    end
  end
end

class PokemonPokedexInfo_Scene
  alias kif_tree_drawEntryText drawEntryText unless method_defined?(:kif_tree_drawEntryText)
  alias kif_tree_changeEntryPage changeEntryPage unless method_defined?(:kif_tree_changeEntryPage)

  # The chart replaces the entry text (and its page number)
  def drawEntryText(overlay, species_data, *args)
    if KIF::DexTree.showing? && !@brief
      begin
        base = Color.new(88, 88, 80)
        shadow = Color.new(168, 184, 184)
        base, shadow = shadow, base if isDarkMode
        @kif_tree_info = KIF::DexTree.draw(overlay, species_data, nil, base, shadow)
      rescue => e
        KIF.log("Dex evolution chart failed: #{e.message}")
        KIF::DexTree.state = 0
        return kif_tree_drawEntryText(overlay, species_data, *args)
      end
      return
    end
    @kif_tree_info = nil
    return kif_tree_drawEntryText(overlay, species_data, *args)
  end

  # Confirm turns the chart's pages while it is shown
  def changeEntryPage(*args)
    if KIF::DexTree.showing? && !@brief
      return if KIF::DexTree.pages <= 1
      pbSEPlay("GUI sel cursor")
      KIF::DexTree.page = (KIF::DexTree.page + 1) % KIF::DexTree.pages
      reloadDexEntry
      return
    end
    return kif_tree_changeEntryPage(*args)
  end

  attr_reader :kif_tree_info
end
