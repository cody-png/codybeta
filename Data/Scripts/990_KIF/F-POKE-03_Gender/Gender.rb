#===============================================================================
# F-POKE-03 – Gender revamp (Reïzod)
# Source: KIF 0.20.7
#   014_Pokemon/001_Pokemon.rb:352-417, :1233-1340  kuraygender, pizza?,
#     forceMale/forceFemale/forceGenderless/force_gender=/makeGenderless,
#     predict_gender, head_gender
#   016_UI/006_UI_Summary.rb:370-392, 005_UI_Party.rb:428-449,
#   017_UI_PokemonStorage.rb:3059-3080, 004_PokeBattle_SceneElements.rb:392-415,
#   024_UI_TextEntry.rb:157-178                      symbols and colours
#   Graphics/Pictures/Storage/gender3.png (genderless), gender4.png (pizza)
#
# * ♂ / ♀ use KIF's colours everywhere (blue 55,148,229 / pink 229,55,203).
# * Genderless Pokémon get KIF's green genderless icon ("G" in the naming
#   screen) – PIF draws nothing.
# * "Pizza": each Pokémon has a hidden roll (kuraygender, 0-65535, made the
#   first time it's needed and saved); below 256 (1 in 256) its gender symbol
#   is shown as KIF's pizza icon ("P" when naming). Its real gender is unchanged.
#   (With KIF's Shenanigans, pizza Pokémon can attract anyone – F-UI-10.)
#
# 6.8.2 adaptations: no base method is copied. The colours are swapped where
# a lone "♂"/"♀" is drawn (pbDrawTextPositions); the extra icons are drawn
# after Summary, party, PC, battle databox and naming screen draw, at KIF's
# offsets from the gender symbol. Images are new files in Graphics/Pictures/KIF.
#===============================================================================
module KIF
  module Gender
    MALE   = [Color.new(55, 148, 229), Color.new(68, 98, 125)]
    FEMALE = [Color.new(229, 55, 203), Color.new(137, 73, 127)]
    GENDERLESS_TEXT = [Color.new(55, 229, 81), Color.new(68, 127, 76)]
    PIZZA_TEXT      = [Color.new(229, 127, 55), Color.new(135, 95, 69)]
    ICON_GENDERLESS = "Graphics/Pictures/KIF/gender_genderless"
    ICON_PIZZA      = "Graphics/Pictures/KIF/gender_pizza"

    @hide_symbols = false
    class << self
      attr_accessor :hide_symbols
    end

    # Runs the block with ♂/♀ suppressed when the Pokémon is a pizza.
    def self.drawing(pkmn)
      old = @hide_symbols
      @hide_symbols = pkmn.respond_to?(:pizza?) && !pkmn.egg? && pkmn.pizza?
      begin
        return yield
      ensure
        @hide_symbols = old
      end
    end

    # Icon for a Pokémon whose symbol PIF doesn't draw (or hides), placed
    # relative to where PIF draws ♂/♀ (KIF offsets).
    def self.draw_icon(bitmap, pkmn, symbol_x, symbol_y, genderless_kind = nil)
      return if pkmn.nil? || pkmn.egg?
      if pkmn.pizza?
        pbDrawImagePositions(bitmap, [[ICON_PIZZA, symbol_x - 18, symbol_y + 5]])
      elsif (genderless_kind.nil? ? pkmn.genderless? : genderless_kind)
        pbDrawImagePositions(bitmap, [[ICON_GENDERLESS, symbol_x - 14, symbol_y + 13]])
      end
    rescue => e
      KIF.log("Gender icon failed: #{e.message}")
    end
  end
end

alias kif_gender_pbDrawTextPositions pbDrawTextPositions unless defined?(kif_gender_pbDrawTextPositions)

def pbDrawTextPositions(bitmap, textpos)
  if textpos.is_a?(Array) && textpos.any? { |t| t.is_a?(Array) && (t[0] == "♂" || t[0] == "♀") }
    textpos = textpos.map do |t|
      next t unless t.is_a?(Array) && (t[0] == "♂" || t[0] == "♀")
      next nil if KIF::Gender.hide_symbols
      colors = (t[0] == "♂") ? KIF::Gender::MALE : KIF::Gender::FEMALE
      t2 = t.dup
      t2[4] = colors[0]
      t2[5] = colors[1]
      t2
    end.compact
  end
  return kif_gender_pbDrawTextPositions(bitmap, textpos)
end

class Pokemon
  attr_writer :kuraygender
  attr_accessor :head_gender

  def kuraygender
    return @kuraygender
  end

  # KIF: hidden 0-65535 roll, made once and saved
  def kuraygender?
    @kuraygender = rand(65536) if @kuraygender.nil?
    return @kuraygender
  end

  def pizza?
    return kuraygender? < 256
  end

  def genderless?
    return self.gender == 2
  end unless method_defined?(:genderless?)

  def forceMale;       @gender = 0; end
  def forceFemale;     @gender = 1; end
  def forceGenderless; @gender = 2; end
  def force_gender=(value); @gender = value; end
  def makeGenderless;  @gender = 2; end unless method_defined?(:makeGenderless)

  def predict_gender(ratio)
    case ratio
    when :AlwaysMale   then return 0
    when :AlwaysFemale then return 1
    when :Genderless   then return 2
    end
    female_chance = GameData::GenderRatio.get(ratio).female_chance
    return ((@personalID & 0xFF) < female_chance) ? 1 : 0
  end
end

class PokeBattle_Battler
  def displayGenderPizza
    pkmn = @effects[PBEffects::Illusion] || @pokemon
    return pkmn.respond_to?(:pizza?) && pkmn.pizza?
  end
end

#-------------------------------------------------------------------------------
# Summary header (♂ at 178,56)
#-------------------------------------------------------------------------------
class PokemonSummary_Scene
  alias kif_gender_drawPage drawPage unless method_defined?(:kif_gender_drawPage)

  def drawPage(page)
    return kif_gender_drawPage(page) if @pokemon.nil?
    KIF::Gender.drawing(@pokemon) { kif_gender_drawPage(page) }
    KIF::Gender.draw_icon(@sprites["overlay"].bitmap, @pokemon, 178, 56) unless @pokemon.egg?
  end
end

#-------------------------------------------------------------------------------
# Party panel (♂ at 224,10)
#-------------------------------------------------------------------------------
class PokemonPartyPanel
  alias kif_gender_refresh refresh unless method_defined?(:kif_gender_refresh)

  def refresh
    redraw = @refreshBitmap
    return kif_gender_refresh if @pokemon.nil?
    KIF::Gender.drawing(@pokemon) { kif_gender_refresh }
    return unless redraw && @overlaysprite && !@overlaysprite.disposed?
    KIF::Gender.draw_icon(@overlaysprite.bitmap, @pokemon, 224, 10)
  end
end

#-------------------------------------------------------------------------------
# PC (♂ at 148,2 on the side panel)
#-------------------------------------------------------------------------------
class PokemonStorageScene
  alias kif_gender_pbUpdateOverlay pbUpdateOverlay unless method_defined?(:kif_gender_pbUpdateOverlay)

  def pbUpdateOverlay(selection, party = nil)
    pokemon = nil
    if @screen && @screen.pbHeldPokemon && !@screen.fusionMode
      pokemon = @screen.pbHeldPokemon
    elsif selection >= 0
      pokemon = (party) ? party[selection] : @storage[@storage.currentBox, selection]
    end
    return kif_gender_pbUpdateOverlay(selection, party) if pokemon.nil?
    ret = KIF::Gender.drawing(pokemon) { kif_gender_pbUpdateOverlay(selection, party) }
    KIF::Gender.draw_icon(@sprites["overlay"].bitmap, pokemon, 148, 2)
    return ret
  rescue => e
    KIF.log("PC gender icon failed: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# Battle databox (♂ at spriteBaseX + 126, 0)
#-------------------------------------------------------------------------------
class PokemonDataBox
  alias kif_gender_refresh refresh unless method_defined?(:kif_gender_refresh)

  def refresh
    return kif_gender_refresh if !@battler || !@battler.pokemon
    pizza = @battler.displayGenderPizza
    old = KIF::Gender.hide_symbols
    KIF::Gender.hide_symbols = pizza
    begin
      kif_gender_refresh
    ensure
      KIF::Gender.hide_symbols = old
    end
    x = @spriteBaseX + 126
    if pizza
      pbDrawImagePositions(self.bitmap, [[KIF::Gender::ICON_PIZZA, x - 18, 5]])
    elsif @battler.displayGender == 2
      pbDrawImagePositions(self.bitmap, [[KIF::Gender::ICON_GENDERLESS, x - 14, 14]])
    end
  rescue => e
    KIF.log("Databox gender icon failed: #{e.message}")
  end
end

#-------------------------------------------------------------------------------
# Naming screens: "G" / "P" text like KIF (subject = Pokémon)
#-------------------------------------------------------------------------------
[:PokemonEntryScene, :PokemonEntryScene2, :PokedexTextEntry].each do |cls|
  next unless Object.const_defined?(cls)
  Object.const_get(cls).class_eval do
    alias_method :kif_gender_pbStartScene, :pbStartScene unless method_defined?(:kif_gender_pbStartScene)

    define_method(:pbStartScene) do |helptext, minlength, maxlength, initialText, subject = 0, pokemon = nil|
      if subject == 2 && pokemon
        ret = KIF::Gender.drawing(pokemon) { kif_gender_pbStartScene(helptext, minlength, maxlength, initialText, subject, pokemon) }
      else
        ret = kif_gender_pbStartScene(helptext, minlength, maxlength, initialText, subject, pokemon)
      end
      if subject == 2 && pokemon && @sprites && @sprites["gender"] && !pokemon.egg?
        text = nil
        if pokemon.pizza?
          text, colors = "P", KIF::Gender::PIZZA_TEXT
        elsif pokemon.genderless?
          text, colors = "G", KIF::Gender::GENDERLESS_TEXT
        end
        if text
          pbSetSystemFont(@sprites["gender"].bitmap)
          pbDrawTextPositions(@sprites["gender"].bitmap, [[text, 0, -6, false, colors[0], colors[1]]])
        end
      end
      ret
    end
  end
end
