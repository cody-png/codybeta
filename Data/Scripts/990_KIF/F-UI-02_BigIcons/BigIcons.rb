#===============================================================================
# F-UI-02 – Big Pokémon Icons (Sylvi, "Pokemons' Sprites as Icons")
# Source: KIF 0.20.7
#   014_Pokemon/001_Pokemon-related/003_Pokemon_Sprites.rb:121-245
#     PokemonIconSprite (party, summary, naming, ... icons)
#   016_UI/017_UI_PokemonStorage.rb:10-48, :205-242, :969-985, :1077-1609
#     PokemonBoxIcon (PC) and the party tab
#   016_UI/005_UI_Party.rb:224-253 (no Poké Ball behind a big icon)
#   016_UI/024_UI_TextEntry.rb:143-145, :451-453 (no offset on naming screens)
#   016_UI/015_UI_Options.rb:2506-2512
#
# Graphics > "Big Pokémon Icons" (all saves):
#   Off     – normal icons
#   Limited – icons use the Pokémon's battle sprite at 1/3 size, except in
#             the PC boxes
#   All     – also in the PC boxes (and the PC party tab)
# Eggs use the egg battle sprite at 1/2 size. With KIF shiny icons Off
# (F-SHINY-01), a shiny's big icon is shown without shiny colours (KIF).
#
# 6.8.2 adaptations:
#   * KIF's version also handled its "Individual Custom Sprites"
#     (kuraycustomfile); 6.8.2's own per-Pokémon sprite (pif_sprite) is used
#     instead (Cody: ICS is covered by PIF).
#   * KIF hid the PC party icons whenever the party tab was closed (big icons
#     stick out above it); here they hide whenever the tab is off screen.
#
# Icon offsets (KIF 003_Pokemon_Sprites.rb:137-138, 155-180): a big icon moves
# 16 px left (8 for eggs), not up. No offset on the Summary and naming
# screens (KIF 006_UI_Summary.rb:137-138, :200-201; 024_UI_TextEntry.rb).
# PC box icons move 16 px left and up (8 for eggs) – KIF 017:237-242.
#===============================================================================
KIF::Options.define(:kuraybigicons, 0, :global)

KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Big Pokémon Icons"), [_INTL("Off"), _INTL("Limited"), _INTL("All")],
                 proc { $PokemonSystem.kuraybigicons },
                 proc { |value| $PokemonSystem.kuraybigicons = value },
                 [_INTL("Pokémon will use their small box sprites for icons"),
                  _INTL("Pokémon icons will use their full-size battle sprites (except in boxes)"),
                  _INTL("Pokémon icons will use their full-size battle sprites")])
}

module KIF
  module BigIcons
    def self.mode
      return $PokemonSystem ? $PokemonSystem.kuraybigicons.to_i : 0
    end

    # Battle sprite scaled down to icon size (a private copy)
    def self.bitmap_for(pkmn)
      plain = defined?(KIF::Shiny) && pkmn.shiny? && !KIF::Shiny.icons_on?
      anim = if plain
               KIF::Shiny.without_shiny(pkmn) { GameData::Species.sprite_bitmap_from_pokemon(pkmn) }
             else
               GameData::Species.sprite_bitmap_from_pokemon(pkmn)
             end
      return nil unless anim
      scale = pkmn.egg? ? 0.5 : 1.0 / 3
      src = anim.bitmap
      w = [(src.width * scale).floor, 1].max
      h = [(src.height * scale).floor, 1].max
      small = Bitmap.new(w, h)
      small.stretch_blt(Rect.new(0, 0, w, h), src, Rect.new(0, 0, src.width, src.height))
      anim.bitmap = small
      return anim
    rescue => e
      KIF.log("Big icon failed: #{e.message}")
      return nil
    end
  end
end

#-------------------------------------------------------------------------------
# Icons (party, summary, naming...): Limited and All
#-------------------------------------------------------------------------------
class PokemonIconSprite
  attr_accessor :kif_big_offset   # false on Summary/naming screens (KIF)

  alias kif_big_pokemon_set pokemon= unless method_defined?(:kif_big_pokemon_set)
  alias kif_big_x_set x= unless method_defined?(:kif_big_x_set)
  def kif_big?
    return @kif_big == true
  end

  def kif_big_shift
    return 0 if !kif_big? || @kif_big_offset == false
    return (@pokemon && @pokemon.egg?) ? -8 : -16
  end

  def pokemon=(value)
    kif_big_pokemon_set(value)
    @kif_big = false
    return unless value.is_a?(Pokemon) && KIF::BigIcons.mode >= 1
    anim = KIF::BigIcons.bitmap_for(value)
    return unless anim
    @animBitmap.dispose if @animBitmap
    @animBitmap = anim
    @kif_big = true
    self.bitmap = @animBitmap.bitmap
    self.src_rect.width = @animBitmap.height
    self.src_rect.height = @animBitmap.height
    @numFrames = [@animBitmap.width / @animBitmap.height, 1].max
    @currentFrame = 0
    changeOrigin
    self.x = @logical_x if @logical_x
    self.y = @logical_y if @logical_y
  end

  def x=(value)
    kif_big_x_set(value)
    super(@logical_x + (@adjusted_x || 0) + kif_big_shift) if kif_big_shift != 0
  end

end

# Summary and naming screens: no offset (KIF 006_UI_Summary.rb:137-138,
# :200-201; 024_UI_TextEntry.rb:143-145, :451-453)
{ :PokemonEntryScene    => [["subject"], [:pbStartScene]],
  :PokemonEntryScene2   => [["subject"], [:pbStartScene]],
  :PokemonSummary_Scene => [["pokeicon"], [:pbStartScene, :pbStartForgetScene]]
}.each do |cls, (keys, methods)|
  next unless Object.const_defined?(cls)
  Object.const_get(cls).class_eval do
    methods.each do |m|
      next unless method_defined?(m)
      orig = "kif_big_#{m}".to_sym
      alias_method orig, m unless method_defined?(orig)
      define_method(m) do |*args, &block|
        ret = send(orig, *args, &block)
        keys.each do |k|
          s = @sprites && @sprites[k]
          next unless s.is_a?(PokemonIconSprite)
          s.kif_big_offset = false
          s.x = s.x
        end
        ret
      end
    end
  end
end

# Party: no Poké Ball under a big icon (KIF 005_UI_Party.rb:224-229)
class PokemonPartyPanel
  alias kif_big_refresh refresh unless method_defined?(:kif_big_refresh)

  def refresh
    kif_big_refresh
    if @ballsprite && !@ballsprite.disposed? && @pokemon && KIF::BigIcons.mode >= 1
      @ballsprite.visible = false
    end
  end
end

#-------------------------------------------------------------------------------
# PC boxes: All
#-------------------------------------------------------------------------------
class PokemonBoxIcon
  alias kif_big_refresh refresh unless method_defined?(:kif_big_refresh)

  def kif_big_shift
    return 0 unless @kif_big
    return (@pokemon && @pokemon.egg?) ? -8 : -16
  end

  def refresh(*args)
    ret = kif_big_refresh(*args)
    @kif_big = false
    if @pokemon && KIF::BigIcons.mode == 2
      anim = KIF::BigIcons.bitmap_for(@pokemon)
      if anim
        self.setBitmapDirectly(anim)
        self.src_rect = Rect.new(0, 0, self.bitmap.width, self.bitmap.height)
        @kif_big = true
      end
    end
    self.x = @kif_logical_x if @kif_logical_x
    self.y = @kif_logical_y if @kif_logical_y
    return ret
  end

  def x
    return @kif_logical_x || super
  end

  def y
    return @kif_logical_y || super
  end

  def x=(value)
    @kif_logical_x = value
    super(value + kif_big_shift)
  end

  def y=(value)
    @kif_logical_y = value
    super(value + kif_big_shift)
  end
end

# PC party tab: big icons hidden while the tab is off screen (KIF hid them
# when the tab closed)
class PokemonBoxPartySprite
  alias kif_big_y_set y= unless method_defined?(:kif_big_y_set)

  def y=(value)
    kif_big_y_set(value)
    return unless KIF::BigIcons.mode == 2 && @pokemonsprites
    show = value < Graphics.height
    @pokemonsprites.each { |s| s.visible = show if s && !s.disposed? }
  end
end
