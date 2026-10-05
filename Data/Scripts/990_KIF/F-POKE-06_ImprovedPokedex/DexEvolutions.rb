#===============================================================================
# F-POKE-06 (part) – How a species evolves, on the Pokédex info page
# Source: KIF 0.20.7 016_UI/004_UI_Pokedex_Entry.rb:309-326 ("Evolve" box:
#         "Lv X" lines, "Item", "Other"; owned species only).
#
# 6.8.2 redesigned the info page and uses KIF's box area for height/weight and
# the sprite/entry credits. Cody chose (2026-10-05): the ACTION button (same
# key as Run: Z/Shift, a face button on controllers) swaps the credits box for
# evolution lines; a small "RUN: Evolutions" / "RUN: Credits" hint sits in the
# title bar.
# The choice is remembered until the game closes.
#   Normal species: "Gloom (Lv 21)", several evolutions share the two lines.
#   Fusions: one line per part, by name: "Oddish > Gloom (Lv 21)" (head) and
#   "Ivysaur > Venusaur (Lv 32)" (body); shortened when a line is too wide.
# More detail than KIF (which only said Lv / Item / Other): item names,
# friendship, trade, held items, known moves, day/night/gender.
#===============================================================================
module KIF
  module DexEvolutions
    @show = false
    class << self
      attr_accessor :show
    end

    LEVEL_SUFFIX = { :LevelMale => " ♂", :LevelFemale => " ♀", :LevelDay => ", day",
                     :LevelNight => ", night", :LevelMorning => ", morning",
                     :LevelAfternoon => ", afternoon", :LevelEvening => ", evening" }

    def self.item_name(id)
      return GameData::Item.get(id).name
    rescue
      return id.to_s
    end

    def self.move_name(id)
      return GameData::Move.get(id).name
    rescue
      return id.to_s
    end

    # How one evolution happens, e.g. "Lv 21", "Leaf Stone", "Trade"
    def self.method_text(method, param)
      m = method.to_s
      if m.start_with?("Level")
        return _INTL("Lv {1}", param) + (LEVEL_SUFFIX[method] || (method == :Level ? "" : "+"))
      end
      return _INTL("Friendship") if m.start_with?("Happiness") || method == :MaxHappiness
      return _INTL("Trade") if [:Trade, :TradeMale, :TradeFemale, :TradeDay, :TradeNight].include?(method)
      return _INTL("Trade w/ {1}", item_name(param)) if method == :TradeItem
      return item_name(param) if m.start_with?("Item")
      if [:HoldItem, :HoldItemMale, :HoldItemFemale, :DayHoldItem, :NightHoldItem, :HoldItemHappiness].include?(method)
        return _INTL("Hold {1}", item_name(param))
      end
      return _INTL("Knows {1}", move_name(param)) if method == :HasMove
      return _INTL("Special")
    end

    def self.species_name(id)
      return GameData::Species.get(id).name
    rescue
      return id.to_s
    end

    def self.evo_texts(species_data)
      species_data.get_evolutions(true).map do |evo|
        _INTL("{1} ({2})", species_name(evo[0]), method_text(evo[1], evo[2]))
      end
    end

    # Fits items (joined by ", ") into at most `lines` lines of `width` px;
    # items that don't fit become "+N more" (whole items only).
    def self.pack(bitmap, items, width, lines)
      rows = [[]]
      fits = ->(row, suffix = "") { bitmap.text_size(row.join(", ") + suffix).width <= width }
      used = 0
      items.each do |item|
        if fits.call(rows[-1] + [item])
          rows[-1] << item
        elsif rows.length < lines && fits.call([item])
          rows << [item]
        else
          break
        end
        used += 1
      end
      left = items.length - used
      while left > 0
        more = _INTL(" +{1} more", left)
        break if fits.call(rows[-1], more)
        break if rows[-1].empty?
        rows[-1].pop
        left += 1
      end
      out = rows.map { |r| r.join(", ") }
      out[-1] = (out[-1] + _INTL(" +{1} more", left)).strip if left > 0
      return out
    end

    def self.part_line(bitmap, part, width)
      name = part.name
      evos = evo_texts(part)
      return _INTL("{1}: final form", name) if evos.empty?
      extra = (evos.length > 1) ? _INTL(" +{1}", evos.length - 1) : ""
      [_INTL("{1} > {2}{3}", name, evos[0], extra), evos[0] + extra].each do |t|
        return t if bitmap.text_size(t).width <= width
      end
      t = evos[0] + extra
      t = t[0...-1] while t.length > 1 && bitmap.text_size(t + "...").width > width
      return t + "..."
    end

    def self.lines(bitmap, species_data, width)
      if species_data.is_a?(GameData::FusedSpecies) && species_data.head_pokemon && species_data.body_pokemon
        return [part_line(bitmap, species_data.head_pokemon, width),
                part_line(bitmap, species_data.body_pokemon, width)]
      end
      evos = evo_texts(species_data)
      return [_INTL("Final form"), ""] if evos.empty?
      return pack(bitmap, evos, width, 2)
    end
  end
end

class PokemonPokedexInfo_Scene
  alias kif_evo_drawPageInfo drawPageInfo unless method_defined?(:kif_evo_drawPageInfo)

  def drawPageInfo(*args)
    # With evolutions shown, the Sprite:/Entry: credit lines (224,156 and
    # 224,188) are left out while the base page draws, instead of erasing
    # them afterwards (erasing cut into the weight text above).
    @kif_skip_credits = KIF::DexEvolutions.show && !@brief
    $kif_dex_scene_drawing = self
    begin
      ret = kif_evo_drawPageInfo(*args)
    ensure
      @kif_skip_credits = false
      $kif_dex_scene_drawing = nil
    end
    unless @brief
      kif_draw_evolutions if KIF::DexEvolutions.show
      kif_draw_evo_hint
    end
    return ret
  end

  def kif_draw_evolutions
    overlay = @sprites["overlay"].bitmap
    base = Color.new(88, 88, 80)
    shadow = Color.new(168, 184, 184)
    base, shadow = shadow, base if isDarkMode
    if $Trainer.owned?(@species)
      species_data = GameData::Species.get_species_form(@species, @form)
      lines = KIF::DexEvolutions.lines(overlay, species_data, 270)
    else
      lines = ["???", ""]
    end
    pbDrawTextPositions(overlay, [[lines[0] || "", 224, 156, 0, base, shadow],
                                  [lines[1] || "", 224, 188, 0, base, shadow]])
  rescue => e
    KIF.log("Dex evolutions failed: #{e.message}")
  end

  # Unobtrusive hint in the right end of the title bar, small font.
  # "Run" is the button players already know (Z/Shift, a face button on
  # controllers/Steam Deck/JoiPlay).
  def kif_draw_evo_hint
    overlay = @sprites["overlay"].bitmap
    label = KIF::DexEvolutions.show ? _INTL("RUN: Credits") : _INTL("RUN: Evolutions")
    pbSetSmallFont(overlay)
    pbDrawTextPositions(overlay, [[label, 502, 2, 1, Color.new(248, 248, 248), Color.new(160, 40, 48)]])
  rescue => e
    KIF.log("Dex evolution hint failed: #{e.message}")
  ensure
    pbSetSystemFont(overlay) if overlay
  end

  attr_reader :kif_skip_credits

  alias kif_evo_pbUpdate pbUpdate unless method_defined?(:kif_evo_pbUpdate)

  def pbUpdate(*args)
    ret = kif_evo_pbUpdate(*args)
    if @page == 1 && !@brief && Input.trigger?(Input::ACTION)
      KIF::DexEvolutions.show = !KIF::DexEvolutions.show
      pbPlayCursorSE
      drawPage(@page)
    end
    return ret
  end
end

# Leaves out the credit lines while drawPageInfo runs with evolutions shown.
alias kif_evo_pbDrawTextPositions pbDrawTextPositions unless defined?(kif_evo_pbDrawTextPositions)

def pbDrawTextPositions(bitmap, textpos)
  scene = $kif_dex_scene_drawing
  if scene && scene.kif_skip_credits && textpos.is_a?(Array)
    textpos = textpos.reject { |t| t.is_a?(Array) && t[1] == 224 && (t[2] == 156 || t[2] == 188) }
  end
  return kif_evo_pbDrawTextPositions(bitmap, textpos)
end
