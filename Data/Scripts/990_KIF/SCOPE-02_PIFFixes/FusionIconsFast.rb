#===============================================================================
# SCOPE-02 – PIF fixes: faster PC box switching (switching between two full
# boxes stuttered)
#
# 1. Fusion icons the first time they're shown. PIF builds a fusion's icon
#    (head icon's top half + body icon's bottom half) pixel by pixel:
#    about 2,000 get_pixel/set_pixel calls per icon, each slow in mkxp-z, and
#    a box full of fusions not seen before builds them all in one frame. The
#    same picture is now made with one clear and one blt (copy) of the body's
#    half. The result is the same image; it is still saved under
#    Graphics/Pokemon/FusionIcons and loaded from there afterwards.
#    (052_InfiniteFusion/ImprovedShinies/Shinies_PokemonStorage.rb and
#    Shinies_PokemonIcons.rb, both copied here with the loop replaced.)
# 2. Shiny fusion icons: the party version named its saved files the wrong
#    way round (a head-shiny icon was saved as "_bodyShiny"), so the PC could
#    later show a party-made icon with the shiny colours on the wrong half.
#    Both now use one naming, under new names (_kif_b / _kif_h) so a wrong
#    file saved earlier is never picked up again.
# 3. A box switch built all 30 icons for the new box, slid it in, and then
#    built all 30 again (pbSwitchBoxToRight/Left call refreshAllBoxSprites on
#    the box they just made). That second pass is skipped: nothing can have
#    changed in between (the new box isn't updated during the slide).
#===============================================================================
KIF.guard_base("052_InfiniteFusion/ImprovedShinies/Shinies_PokemonStorage.rb", 2968950341, "PokemonBoxIcon#createFusionIcon")
KIF.guard_base("052_InfiniteFusion/ImprovedShinies/Shinies_PokemonIcons.rb", 3870949157, "PokemonIconSprite#createFusionIcon")

module KIF
  module FusionIcon
    DIR = "Graphics/Pokemon/FusionIcons"

    module_function

    def path(dex_num, body_shiny, head_shiny)
      suffix = ""
      suffix += "_kif_b" if body_shiny
      suffix += "_kif_h" if head_shiny
      return sprintf("%s/icon%03d%s.png", DIR, dex_num, suffix)
    end

    # head icon on top, the body icon's lower part (from the middle plus PIF's
    # offset) over it - what PIF's pixel loop made
    def build(head_file, body_file, out_path)
      head = AnimatedBitmap.new(head_file)
      body = AnimatedBitmap.new(body_file)
      fused = Bitmap.new(head.width, head.height)
      fused.blt(0, 0, head.bitmap, Rect.new(0, 0, head.width, head.height))
      y0 = (body.height / 2) + Settings::FUSION_ICON_SPRITE_OFFSET
      h = [body.height, fused.height].min - y0
      w = [body.width, fused.width].min
      if h > 0 && w > 0
        fused.fill_rect(0, y0, w, h, Color.new(0, 0, 0, 0))   # set_pixel replaced, blt blends
        fused.blt(0, y0, body.bitmap, Rect.new(0, y0, w, h))
      end
      dir = File.dirname(out_path)
      begin
        Dir.mkdir(dir) unless File.directory?(dir)
      rescue SystemCallError
        nil   # save_to_png reports it, as PIF's version would
      end
      fused.save_to_png(out_path)
      fused.dispose
      return AnimatedBitmap.new(out_path)
    end

    def for_species(species, form_head, form_body, body_shiny, head_shiny)
      body_num = getBodyID(species)
      head_num = getHeadID(species, body_num)
      body_sp = GameData::Species.get(body_num).species
      head_sp = GameData::Species.get(head_num).species
      out = path(getDexNumberForSpecies(species), body_shiny, head_shiny)
      return AnimatedBitmap.new(out) if File.exist?(out)
      return build(GameData::Species.icon_filename(head_sp, form_head, nil, head_shiny),
                   GameData::Species.icon_filename(body_sp, form_body, nil, body_shiny), out)
    end
  end
end

class PokemonBoxIcon
  def createFusionIcon(species, spriteform_head = nil, spriteform_body = nil, bodyShiny = false, headShiny = false)
    return KIF::FusionIcon.for_species(species, spriteform_head, spriteform_body, bodyShiny, headShiny)
  end
end

class PokemonIconSprite
  def createFusionIcon()
    pk = @pokemon
    return KIF::FusionIcon.for_species(pk.species, pk.spriteform_head, pk.spriteform_body,
                                       pk.bodyShiny?, pk.headShiny?)
  end
end

#-------------------------------------------------------------------------------
# 3. No second pass over a box that was just built for a box switch
#    (016_UI/PokemonStorage/PokemonStorageScene.rb pbSwitchBoxToRight/Left).
#    Only skipped inside a switch, only for the box made in it, and only while
#    its filter is the one it was built with.
#-------------------------------------------------------------------------------
KIF.guard_base("016_UI/PokemonStorage/PokemonStorageScene.rb", 2394998757, "pbSwitchBoxToRight/Left")

module KIF
  module BoxSwitch
    @active = false
    class << self; attr_accessor :active; end

    def self.during
      old = @active
      @active = true
      begin
        return yield
      ensure
        @active = old
      end
    end
  end
end

class PokemonStorageScene
  alias kif_bf_pbSwitchBoxToRight pbSwitchBoxToRight unless method_defined?(:kif_bf_pbSwitchBoxToRight)
  alias kif_bf_pbSwitchBoxToLeft pbSwitchBoxToLeft unless method_defined?(:kif_bf_pbSwitchBoxToLeft)

  def pbSwitchBoxToRight(*args)
    return KIF::BoxSwitch.during { kif_bf_pbSwitchBoxToRight(*args) }
  end

  def pbSwitchBoxToLeft(*args)
    return KIF::BoxSwitch.during { kif_bf_pbSwitchBoxToLeft(*args) }
  end
end

class PokemonBoxSprite
  alias kif_bf_initialize initialize unless method_defined?(:kif_bf_initialize)
  alias kif_bf_refreshAllBoxSprites refreshAllBoxSprites unless method_defined?(:kif_bf_refreshAllBoxSprites)
  alias kif_bf_update update unless method_defined?(:kif_bf_update)

  def initialize(*args)
    kif_bf_initialize(*args)
    @kif_just_built = KIF::BoxSwitch.active
    @kif_built_filter = @filterProc
  end

  def refreshAllBoxSprites(*args)
    skip = @kif_just_built && KIF::BoxSwitch.active && @filterProc.equal?(@kif_built_filter)
    @kif_just_built = false
    return if skip   # every icon was made a moment ago, with this filter
    return kif_bf_refreshAllBoxSprites(*args)
  end

  def update(*args)
    @kif_just_built = false
    return kif_bf_update(*args)
  end
end
