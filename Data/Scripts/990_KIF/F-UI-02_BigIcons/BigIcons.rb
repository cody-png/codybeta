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
                 proc { |value| $PokemonSystem.kuraybigicons = value; KIF::BigIcons.clear_cache },
                 [_INTL("Pokémon will use their small box sprites for icons"),
                  _INTL("Pokémon icons will use their full-size battle sprites (except in boxes)"),
                  _INTL("Pokémon icons will use their full-size battle sprites")])
}

module KIF
  module BigIcons
    def self.mode
      return $PokemonSystem ? $PokemonSystem.kuraybigicons.to_i : 0
    end

    # Scaled icons are cached (KIF rebuilt one from the full battle sprite on
    # every refresh: a PC page = 30 sprite loads + 30 shiny renders). The key
    # is everything that decides the picture; a hit costs one small blt.
    CACHE_LIMIT = 80
    @cache = {}

    # A still image standing in for the AnimatedBitmap the sprites expect
    class Icon
      attr_reader :bitmap
      def initialize(bitmap); @bitmap = bitmap; end
      def width;  @bitmap.width;  end
      def height; @bitmap.height; end
      def update; end
      def disposed?; @bitmap.disposed?; end
      def dispose; @bitmap.dispose unless @bitmap.disposed?; end
      def pbSetColor(*args); end   # IconSprite#setColor (unused for icons)
    end

    def self.clear_cache
      @cache.each_value { |b| b.dispose if b && !b.disposed? }
      @cache.clear
    end

    def self.cache_key(pkmn)
      ps = pkmn.pif_sprite rescue nil
      sprite = ps ? [ps.type, ps.head_id, ps.body_id, ps.alt_letter, ps.local_path] : nil
      shiny = nil
      if pkmn.shiny?
        shiny = [pkmn.head_shiny, pkmn.body_shiny, (pkmn.shinyValue? rescue nil),
                 (pkmn.shinyR? rescue nil), (pkmn.shinyG? rescue nil), (pkmn.shinyB? rescue nil),
                 (pkmn.shinyKRS? rescue nil), (pkmn.shinyimprovpif? rescue nil),
                 ($PokemonSystem.shinyadvanced rescue nil), ($PokemonSystem.pifimprovedshinies rescue nil),
                 (defined?(KIF::Shiny) ? [KIF::Shiny.icons_on?, (KIF::Shiny.filtered?(pkmn) rescue nil)] : nil)]
      end
      return [pkmn.species, pkmn.form, pkmn.egg?, sprite, shiny,
              (pkmn.hat rescue nil), (pkmn.sprite_scale rescue nil), mode >= 1]
    end

    # Battle sprite scaled down to icon size (a private copy)
    def self.bitmap_for(pkmn)
      key = cache_key(pkmn) rescue nil
      if key && (hit = @cache[key]) && !hit.disposed?
        @cache.delete(key); @cache[key] = hit
        copy = Bitmap.new(hit.width, hit.height)
        copy.blt(0, 0, hit, Rect.new(0, 0, hit.width, hit.height))
        return Icon.new(copy)
      end
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
      if key
        if @cache.length >= CACHE_LIMIT
          old_key, old = @cache.first
          @cache.delete(old_key)
          old.dispose if old && !old.disposed?
        end
        keep = Bitmap.new(w, h)
        keep.blt(0, 0, small, Rect.new(0, 0, w, h))
        @cache[key] = keep
      end
      return Icon.new(small)
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
#
# Party layout with big icons (port addition, Cody's mock-ups 2026-10-05):
#   * the icon sits 20 px lower;
#   * the level moves 52 px right, just before the HP numbers;
#   * the status badge (SLP/PSN/.../FNT) is drawn over the bottom of the icon;
#   * the EvoLock padlock sits over the icon's bottom-left (F-POKE-01).
# With an annotation ("ABLE"/"NOT ABLE") or for eggs the 6.8.2 layout is kept.
module KIF
  module BigIcons
    PARTY_ICON_DROP  = 20
    PARTY_LV_X       = 72     # 6.8.2: 20 (Lv image) / 42 (number)
    PARTY_STATUS_POS = [28, 70]
    PARTY_LOCK_POS   = [12, 64]

    def self.party_layout?(panel_pokemon, text)
      return false unless mode >= 1 && panel_pokemon && !panel_pokemon.egg?
      return text.nil? || text.length == 0
    end

    # Same status choice as 6.8.2 PokemonPartyPanel#refresh (row in statuses)
    def self.status_row(pkmn)
      status = 0
      if pkmn.fainted?
        status = GameData::Status::DATA.keys.length / 2
      elsif pkmn.status != :NONE
        status = GameData::Status.get(pkmn.status).id_number
      elsif pkmn.pokerusStage == 1
        status = GameData::Status::DATA.keys.length / 2 + 1
      end
      return status - 1
    end
  end
end

class PokemonPartyPanel
  alias kif_big_refresh refresh unless method_defined?(:kif_big_refresh)

  def refresh
    redraw = @refreshBitmap
    kif_big_refresh
    return if disposed?
    if @ballsprite && !@ballsprite.disposed? && @pokemon && KIF::BigIcons.mode >= 1
      @ballsprite.visible = false
    end
    kif_big_layout_refresh(redraw) if KIF::BigIcons.party_layout?(@pokemon, @text)
  rescue => e
    KIF.log("Big icon party layout failed: #{e.message}")
  end

  def kif_big_layout_refresh(redraw)
    if @pkmnsprite && !@pkmnsprite.disposed?
      @pkmnsprite.y = self.y + 40 + KIF::BigIcons::PARTY_ICON_DROP
    end
    return unless redraw && @overlaysprite && !@overlaysprite.disposed? && @overlaysprite.bitmap
    bmp = @overlaysprite.bitmap
    bmp.clear_rect(16, 56, 60, 30)   # 6.8.2's level (image 20,70 / number 42,57)
    bmp.clear_rect(78, 68, 44, 16)   # 6.8.2's status badge
    # Level, moved right
    lx = KIF::BigIcons::PARTY_LV_X
    pbDrawImagePositions(bmp, [["Graphics/Pictures/Party/overlay_lv", lx, 70, 0, 0, 22, 14]])
    pbSetSmallFont(bmp)
    pbDrawTextPositions(bmp, [[@pokemon.level.to_s, lx + 22, 57, 0,
                               Color.new(248, 248, 248), Color.new(40, 40, 40)]])
    pbSetSystemFont(bmp)
    # Status badge over the bottom of the icon
    row = KIF::BigIcons.status_row(@pokemon)
    if row >= 0 && @statuses && !@statuses.disposed?
      sx, sy = KIF::BigIcons::PARTY_STATUS_POS
      bmp.blt(sx, sy, @statuses.bitmap, Rect.new(0, 16 * row, 44, 16))
    end
    # EvoLock's padlock (drawn earlier at PARTY_LOCK_POS) was partly cleared
    if defined?(KIF.draw_evolock_icon) && @pokemon.respond_to?(:kif_evo_locked?) &&
       @pokemon.kif_evo_locked?
      KIF.draw_evolock_icon(bmp, *KIF::BigIcons::PARTY_LOCK_POS)
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
