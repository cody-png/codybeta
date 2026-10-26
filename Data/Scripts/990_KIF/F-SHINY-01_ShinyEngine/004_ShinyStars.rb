#===============================================================================
# F-SHINY-01 – KIF shiny stars (star colour = shiny type)
# Source: KIF 0.20.7 052_AddOns/GeneralUtils.rb:137-206 (#KurayX new ShinyStars)
#
# For Pokémon coloured by the KIF engine the shiny star shows which channel
# codes the shiny uses ("at least one channel", rarest type wins):
#   Normal mode:   Cyan (9-11 inv. C/M/Y) > Yellow (3-5 C/M/Y) >
#                  Black (6-8 inv. R/G/B) > Red (normal)
#   Advanced mode: Magenta (20-25 inv. blends) > Red (14-19 blends) >
#                  Yellow (13 inv. grey) > Grey (12) > Cyan (9-11) >
#                  Blue (3-5) > Black (6-8) > Green (normal)
#   Simple mode:   plain star.
# KIF ignored PIF's "debug shiny" black star; so does this for KIF-coloured
# shinies (all shinies made with custom odds are "debug" in PIF's sense,
# which is why every star showed black). Pokémon shown with PIF's palette only
# keep PIF's star logic.
#
# PIF bug fixed (always on): pbDrawImagePositions tinted the star by recolouring
# the bitmap returned by RPG::Cache in place, so one black (or blue) star
# turned every later star that colour. The tint is now applied to a copy.
#===============================================================================
module KIF
  module Shiny
    @star_pokemon = nil
    class << self
      attr_accessor :star_pokemon
    end

    NORMAL_STARS = [
      [[9, 10, 11], Color.new(0, 255, 255, 255)],    # Cyan: inverted C/M/Y
      [[3, 4, 5],   Color.new(255, 255, 0, 255)],    # Yellow: C/M/Y
      [[6, 7, 8],   Color.new(0, 0, 0, 255)]         # Black: inverted R/G/B
    ]
    NORMAL_DEFAULT = Color.new(255, 0, 0, 255)        # Red

    ADVANCED_STARS = [
      [[20, 21, 22, 23, 24, 25], Color.new(230, 34, 230, 255)],  # Magenta
      [[14, 15, 16, 17, 18, 19], Color.new(230, 34, 67, 255)],   # Red
      [[13],                     Color.new(230, 230, 34, 255)],  # Yellow: inv. grey
      [[12],                     Color.new(100, 100, 100, 255)], # Grey
      [[9, 10, 11],              Color.new(34, 230, 230, 255)],  # Cyan
      [[3, 4, 5],                Color.new(34, 67, 230, 255)],   # Blue
      [[6, 7, 8],                Color.new(0, 0, 0, 255)]        # Black
    ]
    ADVANCED_DEFAULT = Color.new(67, 230, 34, 255)    # Green

    # nil = plain star
    def self.star_color(pkmn)
      adv = $PokemonSystem ? $PokemonSystem.shinyadvanced : 1
      return nil if adv == 0
      codes = [pkmn.shinyR?, pkmn.shinyG?, pkmn.shinyB?]
      table, default = (adv == 2) ? [ADVANCED_STARS, ADVANCED_DEFAULT] : [NORMAL_STARS, NORMAL_DEFAULT]
      table.each do |set, color|
        return color.clone if codes.any? { |c| set.include?(c) }
      end
      return default.clone
    end
  end
end

class Pokemon
  # radarShiny? is evaluated as the last argument of every
  # addShinyStarsToGraphicsArray call in 6.8.2 (battle box, party, summary,
  # PC), so it is used to know which Pokémon the next star belongs to.
  alias kif_star_radarShiny? radarShiny? unless method_defined?(:kif_star_radarShiny?)

  def radarShiny?
    KIF::Shiny.star_pokemon = self
    return kif_star_radarShiny?
  end
end

alias kif_star_addShinyStarsToGraphicsArray addShinyStarsToGraphicsArray unless defined?(kif_star_addShinyStarsToGraphicsArray)

def addShinyStarsToGraphicsArray(imageArray, *args)
  # KIF 0.20.7's argument list (mods: Alpha Encounters, Counterfeit
  # Shinies): no radar flag after debugShiny, and fakeshiny + RGB at the end
  # (13 after the array; 6.8.2 takes at most 12). Turned into 6.8.2's.
  args = args[0, 5] + [false] + args[5, 6] if args.length > 12
  pkmn = KIF::Shiny.star_pokemon
  KIF::Shiny.star_pokemon = nil
  before = imageArray.length
  kif_star_addShinyStarsToGraphicsArray(imageArray, *args)
  if pkmn && KIF::Shiny.kif_render?(pkmn)
    color = KIF::Shiny.star_color(pkmn)
    (before...imageArray.length).each { |i| imageArray[i][7] = color }
  end
end

KIF.guard_base("007_Objects and windows/010_DrawText.rb", 2510589030, "pbDrawImagePositions")

# Copy of PIF 6.8.2 pbDrawImagePositions; the tint goes on a private copy.
def pbDrawImagePositions(bitmap, textpos)
  for i in textpos
    srcbitmap = AnimatedBitmap.new(pbBitmapName(i[0]))
    x = i[1]
    y = i[2]
    srcx = i[3] || 0
    srcy = i[4] || 0
    width = (i[5] && i[5] >= 0) ? i[5] : srcbitmap.width
    height = (i[6] && i[6] >= 0) ? i[6] : srcbitmap.height
    color = i[7] || nil
    srcrect = Rect.new(srcx, srcy, width, height)
    if color
      tinted = KIF::Shiny.copy_bitmap(srcbitmap.bitmap)        # KIF
      tinted_anim = AnimatedBitmap.from_bitmap(tinted)          # KIF
      tinted_anim.pbSetColorValue(color)                        # KIF
      bitmap.blt(x, y, tinted, srcrect)                         # KIF
      tinted.dispose                                            # KIF
    else
      bitmap.blt(x, y, srcbitmap.bitmap, srcrect)
    end
    srcbitmap.dispose
  end
end
#-------------------------------------------------------------------------------
# EBDX battle boxes (660/007 DataBoxEBDX) show a shiny only by a gold name.
# KIF's star (its colour = the shiny type) goes left of the name as on PIF's
# box (the second star of a double-shiny fusion further left), with the dark
# edge EBDX gives its box text; the gold name stays. A box sprite, so it
# moves, hides and fades with the box.
#-------------------------------------------------------------------------------
if defined?(::DataBoxEBDX)
  class ::DataBoxEBDX
    alias kif_star_setUp setUp unless method_defined?(:kif_star_setUp) || private_method_defined?(:kif_star_setUp)
    alias kif_star_refresh refresh unless method_defined?(:kif_star_refresh) || private_method_defined?(:kif_star_refresh)

    STAR_W = 33   # two 14 px stars 1 px apart, plus a 2 px edge each side

    def setUp
      kif_star_setUp
      s = Sprite.new(@viewport)
      s.z = getMetric("name", :z)
      s.ex = getMetric("name", :x) - STAR_W   # set again by each refresh (long names)
      s.ey = getMetric("name", :y) + 4        # the star level with the name's letters
      @sprites["kif_star"] = s
    end

    def refresh
      kif_star_refresh
      kif_draw_star
    end

    def kif_draw_star
      spr = @sprites && @sprites["kif_star"]
      return unless spr && !spr.disposed? && @pokemon && @battler
      spr.bitmap.dispose if spr.bitmap && !spr.bitmap.disposed?
      spr.bitmap = nil
      return unless @pokemon.shiny?
      pos = []
      addShinyStarsToGraphicsArray(pos, 15, 0, @pokemon.bodyShiny?, @pokemon.headShiny?, @pokemon.debugShiny?, @pokemon.radarShiny?)
      star = Bitmap.new(STAR_W - 4, 16)
      pbDrawImagePositions(star, pos)
      spr.bitmap = kif_star_edge(star)
      # EBDX's refresh moves a long name line left by o (same sum as there);
      # the name's letters start at name x + 2 - o, the star ends 2 px before
      line = @sprites["textName"].bitmap
      sym = (@pokemon.gender == 0 && !@hidden) ? "♂" : (@pokemon.gender == 1 && !@hidden) ? "♀" : ""
      w = line.text_size("#{@battler.name}#{sym}Lv.#{@pokemon.level}").width
      o = (w > @hpBarWidth + 4) ? ((w - (@hpBarWidth + 4)) / 2.0).ceil : 0
      spr.ex = getMetric("name", :x) - o - STAR_W
      base = @sprites["base"]
      spr.x = base.x + spr.ex
      spr.y = base.y + spr.ey
    rescue => e
      KIF.log("EBDX shiny star failed: #{e.message}")
    end

    # the star on EBDX's text edge: its shape in black at 125 alpha, drawn at
    # the 8 offsets of 2 px as pbDrawOutlineText draws the name's (consumes star)
    def kif_star_edge(star)
      shade = Bitmap.new(star.width, star.height)
      dark = Color.new(0, 0, 0, 125)
      star.height.times { |y| star.width.times { |x| shade.set_pixel(x, y, dark) if star.get_pixel(x, y).alpha > 0 } }
      out = Bitmap.new(star.width + 4, star.height + 4)
      [0, 2, 4].each { |y| [0, 2, 4].each { |x| out.blt(x, y, shade, shade.rect) unless x == 2 && y == 2 } }
      out.blt(2, 2, star, star.rect)
      return out
    ensure
      shade.dispose if shade
      star.dispose
    end
  end
end
