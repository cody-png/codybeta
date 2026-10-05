#===============================================================================
# F-SHINY-01 – where the KIF engine plugs into PIF 6.8.2
#
# Battlers / summary / PC preview / evolution etc.
#   GameData::Species.front_sprite_bitmap_pokemon (FusionSprites.rb) – every
#   Pokémon sprite goes through it (via sprite_bitmap_from_pokemon).
# Icons (option "Shiny Icons" On, as in KIF):
#   PokemonIconSprite#pokemon=   (party, summary, many menus)
#   PokemonBoxIcon#refresh       (PC boxes)
# Battle shiny animation ("Shiny Animation" On / Off / All):
#   PokeBattle_Scene#pbCommonAnimation("Shiny"), pbBattleIntroAnimation,
#   pbSendOutBattlers
# Fusing / reversing keep head and body colours (KIF PokemonFusion.rb:920-981,
# New Items effects.rb:616-622) and "Shiny Fuse Dye" (F-SHINY-02).
# Unfusing needs nothing: PIF 6.8.2 restores the original head/body Pokémon
# objects, which still hold their own colours.
#===============================================================================
module GameData
  class Species
    class << self
      alias kif_front_sprite_bitmap_pokemon front_sprite_bitmap_pokemon unless method_defined?(:kif_front_sprite_bitmap_pokemon)

      def front_sprite_bitmap_pokemon(pokemon)
        return kif_front_sprite_bitmap_pokemon(pokemon) unless KIF::Shiny.kif_render?(pokemon)
        begin
          KIF.ensure_fusion_shiny_parts(pokemon) if defined?(KIF.ensure_fusion_shiny_parts)
          sprite = KIF::Shiny.without_shiny(pokemon) { kif_front_sprite_bitmap_pokemon(pokemon) }
          return sprite unless sprite
          KIF::Shiny.privatize(sprite)
          return KIF::Shiny.colorize!(sprite, pokemon, :sprite)
        rescue => e
          KIF.log("KIF shiny engine failed (#{e.message}); using PIF shiny")
          return kif_front_sprite_bitmap_pokemon(pokemon)
        end
      end
    end
  end
end

module KIF
  module Shiny
    def self.icons_on?
      return $PokemonSystem && $PokemonSystem.shiny_icons_kuray == 1
    end

    # Builds an icon through the KIF engine. build: block returning an
    # AnimatedBitmap (PIF's icon for the Pokémon in its current state).
    def self.icon_for(pkmn)
      use_pif, _use_kif = decide(pkmn)
      if use_pif
        anim = yield                       # PIF shiny icon = PIF palette step
      else
        anim = without_shiny(pkmn) { yield }
      end
      return anim unless anim
      privatize(anim)
      return colorize!(anim, pkmn, :icon, true)
    end
  end
end

class PokemonIconSprite
  alias kif_shiny_pokemon_set pokemon= unless method_defined?(:kif_shiny_pokemon_set)

  def pokemon=(value)
    kif_shiny_pokemon_set(value)
    return unless value.is_a?(Pokemon) && KIF::Shiny.icons_on? && KIF::Shiny.kif_render?(value)
    begin
      anim = KIF::Shiny.icon_for(value) do
        if useRegularIcon(value.species) || value.egg?
          AnimatedBitmap.new(GameData::Species.icon_filename_from_pokemon(value))
        elsif useTripleFusionIcon(value.species)
          AnimatedBitmap.new(pbResolveBitmap(sprintf("Graphics/Icons/iconDNA")))
        else
          createFusionIcon()
        end
      end
      return unless anim
      @animBitmap.dispose if @animBitmap
      @animBitmap = anim
      self.bitmap = @animBitmap.bitmap
    rescue => e
      KIF.log("KIF shiny icon failed: #{e.message}")
    end
  end
end

class PokemonBoxIcon
  alias kif_shiny_refresh refresh unless method_defined?(:kif_shiny_refresh)

  def refresh(*args)
    kif_shiny_refresh(*args)
    return unless @pokemon && KIF::Shiny.icons_on? && KIF::Shiny.kif_render?(@pokemon)
    begin
      pkmn = @pokemon
      anim = KIF::Shiny.icon_for(pkmn) do
        if useRegularIcon(pkmn.species) || pkmn.egg?
          AnimatedBitmap.new(GameData::Species.icon_filename_from_pokemon(pkmn))
        else
          createFusionIcon(pkmn.species, pkmn.spriteform_head, pkmn.spriteform_body,
                           pkmn.bodyShiny?, pkmn.headShiny?)
        end
      end
      return unless anim
      self.setBitmapDirectly(anim)
      self.src_rect = Rect.new(0, 0, self.bitmap.height, self.bitmap.height)
    rescue => e
      KIF.log("KIF shiny box icon failed: #{e.message}")
    end
  end
end

#-------------------------------------------------------------------------------
# Shiny animation (KIF 009_Scene_Animations.rb:55-75, :155-166)
#-------------------------------------------------------------------------------
class PokeBattle_Scene
  alias kif_shiny_pbCommonAnimation pbCommonAnimation unless method_defined?(:kif_shiny_pbCommonAnimation)

  def pbCommonAnimation(animName, user = nil, target = nil)
    return if animName == "Shiny" && $PokemonSystem && $PokemonSystem.kurayshinyanim == 1
    kif_shiny_pbCommonAnimation(animName, user, target)
  end

  def kif_shiny_anim_for_all(indices)
    return unless $PokemonSystem && $PokemonSystem.kurayshinyanim == 2 && @battle.showAnims
    indices.each do |idx|
      b = @battle.battlers[idx]
      next if !b || b.fainted? || b.shiny?
      kif_shiny_pbCommonAnimation("Shiny", b)
    end
  end

  alias kif_shiny_pbBattleIntroAnimation pbBattleIntroAnimation unless method_defined?(:kif_shiny_pbBattleIntroAnimation)

  def pbBattleIntroAnimation(*args)
    kif_shiny_pbBattleIntroAnimation(*args)
    return if @battle.trainerBattle?
    kif_shiny_anim_for_all((0...@battle.sideSizes[1]).map { |i| 2 * i + 1 })
  end

  alias kif_shiny_pbSendOutBattlers pbSendOutBattlers unless method_defined?(:kif_shiny_pbSendOutBattlers)

  def pbSendOutBattlers(sendOuts, startBattle = false)
    kif_shiny_pbSendOutBattlers(sendOuts, startBattle)
    kif_shiny_anim_for_all(sendOuts.map { |s| s[0] })
  end
end

#-------------------------------------------------------------------------------
# Fusing: head/body colours and Shiny Fuse Dye
#-------------------------------------------------------------------------------
KIF::Options.define(:shinyfusedye, 0, :save)

KIF::Options.add(:shinies, :save) {
  EnumOption.new(_INTL("Shiny Fuse Dye"), [_INTL("Off"), _INTL("On"), _INTL("Random")],
                 proc { $PokemonSystem.shinyfusedye },
                 proc { |value| $PokemonSystem.shinyfusedye = value },
                 [_INTL("Don't use the shiny fusion color dye system"),
                  _INTL("Use the shiny fusion color dye system"),
                  _INTL("Re-roll shiny color after each fusion/unfusion")])
}

module KIF
  module Shiny
    # KIF PokemonFusion.rb:920-981. body = the fused Pokémon (still the body
    # object), head_c / body_c = colour data of head and body before fusing.
    def self.on_fused(fused, head_shiny, body_shiny, head_c, body_c)
      dye = $PokemonSystem.shinyfusedye
      if head_shiny
        fused.head_shinyhue = head_c[:hue]; fused.head_shinyimprovpif = head_c[:pif]
        fused.head_shinyr = head_c[:r]; fused.head_shinyg = head_c[:g]; fused.head_shinyb = head_c[:b]
        fused.head_shinykrs = head_c[:krs].clone
        fused.kif_set_shiny_colors(head_c) if dye == 1
      end
      if body_shiny
        fused.body_shinyhue = body_c[:hue]; fused.body_shinyimprovpif = body_c[:pif]
        fused.body_shinyr = body_c[:r]; fused.body_shinyg = body_c[:g]; fused.body_shinyb = body_c[:b]
        fused.body_shinykrs = body_c[:krs].clone
      end
      fused.kif_set_shiny_colors(head_c) if head_shiny && body_shiny && dye == 0
      if dye == 2
        fused.kif_reroll_shiny_colors
        fused.head_shinyimprovpif = rollimproveshiny(); fused.body_shinyimprovpif = rollimproveshiny()
        fused.body_shinyhue = rand(0..360) - 180; fused.head_shinyhue = rand(0..360) - 180
        fused.body_shinyr = kurayRNGforChannels; fused.body_shinyg = kurayRNGforChannels
        fused.body_shinyb = kurayRNGforChannels; fused.body_shinykrs = kurayKRSmake
        fused.head_shinyr = kurayRNGforChannels; fused.head_shinyg = kurayRNGforChannels
        fused.head_shinyb = kurayRNGforChannels; fused.head_shinykrs = kurayKRSmake
      end
    end
  end
end

class PokemonFusionScene
  alias kif_shiny_pbFusionScreen pbFusionScreen unless method_defined?(:kif_shiny_pbFusionScreen)

  def pbFusionScreen(*args)
    head = @pokemon2
    body = @pokemon1
    head_shiny = head && head.shiny?
    body_shiny = body && body.shiny?
    head_c = head ? head.kif_shiny_colors : nil
    body_c = body ? body.kif_shiny_colors : nil
    ret = kif_shiny_pbFusionScreen(*args)
    begin
      fused = @pokemon1
      if fused && head && fused.respond_to?(:original_head) && fused.original_head &&
         fused.original_head.personalID == head.personalID && fused.isFusion?
        KIF::Shiny.on_fused(fused, head_shiny, body_shiny, head_c, body_c)
      end
    rescue => e
      KIF.log("KIF fusion colours failed: #{e.message}")
    end
    return ret
  end
end

# DNA Reverser swaps head and body: swap the KIF head/body colours too
# (KIF New Items effects.rb:616-622).
alias kif_shiny_reverseFusion reverseFusion unless defined?(kif_shiny_reverseFusion)

def reverseFusion(pokemon, *args)
  before = pokemon.respond_to?(:original_head) ? pokemon.original_head : nil
  ret = kif_shiny_reverseFusion(pokemon, *args)
  if pokemon.respond_to?(:original_body) && before && pokemon.original_body.equal?(before)
    pokemon.head_shinyimprovpif, pokemon.body_shinyimprovpif = pokemon.body_shinyimprovpif, pokemon.head_shinyimprovpif
    pokemon.head_shinyr, pokemon.body_shinyr = pokemon.body_shinyr, pokemon.head_shinyr
    pokemon.head_shinyg, pokemon.body_shinyg = pokemon.body_shinyg, pokemon.head_shinyg
    pokemon.head_shinyb, pokemon.body_shinyb = pokemon.body_shinyb, pokemon.head_shinyb
    pokemon.head_shinyhue, pokemon.body_shinyhue = pokemon.body_shinyhue, pokemon.head_shinyhue
    pokemon.head_shinykrs, pokemon.body_shinykrs = pokemon.body_shinykrs, pokemon.head_shinykrs
  end
  return ret
end
