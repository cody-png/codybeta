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
