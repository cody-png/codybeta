#===============================================================================
# F-FUSION-03 – KIF fusion preview
# Source: KIF 0.20.7 048_Fusion/DoublePreviewScreen.rb:105-140,
#   048_Fusion/FusionPreviewScreen.rb:27-47, 016_UI/015_UI_Options.rb:2514
#
# Graphics > "Fusion Preview" (Off/On, all saves): On shows fusions you
# haven't seen yet with their real sprite instead of the blue / green /
# white silhouette.
# Always (with the KIF shiny engine, F-SHINY-01): the DNA Splicer preview of a
# shiny fusion shows the KIF colours the result will get (KIF passed the
# shiny channels into the preview). 6.8.2's preview only knew PIF's palette.
#
# 6.8.2 adaptations:
#   * The colours follow the port's fusion rule (F-SHINY-01 on_fused): the
#     fused Pokémon keeps the body's colours, or takes the head's when the
#     head is shiny and Shiny Fuse Dye is on (or both are shiny with Dye
#     Off). With Dye "Random" the result can't be known, so the preview
#     shows PIF's palette.
#   * KIF's other two changes need nothing: KIF *removed* the sprite credits
#     line on the fusion screen (6.8.2 keeps PIF's), and 6.8.2 already asks
#     a plain (not "serious") confirm before unfusing.
#===============================================================================
KIF::Options.define(:kurayfusepreview, 0, :global)

KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Fusion Preview"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kurayfusepreview },
                 proc { |value| $PokemonSystem.kurayfusepreview = value },
                 [_INTL("Don't preview what unknown fusions look like"),
                  _INTL("Preview what unknown fusions look like")])
}

module KIF
  module FusionPreview
    @reveal = false
    @color = nil      # [dex number, colour source]
    class << self
      attr_accessor :reveal, :color
    end

    def self.on?
      return $PokemonSystem && $PokemonSystem.kurayfusepreview.to_i == 1
    end

    # Stand-in for the fused Pokémon, for KIF::Shiny.colorize!
    class Look
      attr_reader :species, :body_shiny, :head_shiny
      def initialize(species, colors, body_shiny, head_shiny)
        @species = species; @c = colors
        @body_shiny = body_shiny; @head_shiny = head_shiny
      end
      def shinyValue?;      @c[:hue]; end
      def shinyimprovpif?;  @c[:pif]; end
      def shinyR?;          @c[:r];   end
      def shinyG?;          @c[:g];   end
      def shinyB?;          @c[:b];   end
      def shinyKRS?;        @c[:krs]; end
      def kif_filter_roll?; @c[:filter] || 0; end
      def shiny?;           true;     end
      def egg?;             false;    end
    end

    # Colours the fusion will get (F-SHINY-01 KIF::Shiny.on_fused)
    def self.look_for(dex, body, head)
      return nil unless body.respond_to?(:kif_shiny_colors) && head.respond_to?(:kif_shiny_colors)
      return nil unless body.shiny? || head.shiny?
      dye = $PokemonSystem ? $PokemonSystem.shinyfusedye.to_i : 0
      return nil if dye == 2
      colors = body.kif_shiny_colors
      colors = head.kif_shiny_colors if head.shiny? && (dye == 1 || (body.shiny? && dye == 0))
      species = GameData::Species.get(dex).id rescue dex
      return Look.new(species, colors, body.shiny?, head.shiny?)
    end
  end
end

class Player
  alias kif_fp_seen? seen? unless method_defined?(:kif_fp_seen?)

  def seen?(species)
    return true if KIF::FusionPreview.reveal
    return kif_fp_seen?(species)
  end
end

class DoublePreviewScreen
  alias kif_fp_draw_window draw_window unless method_defined?(:kif_fp_draw_window)

  def draw_window(dexNumber, level, x, y, isShiny = false, bodyShiny = false, headShiny = false, window_position = 0)
    old = KIF::FusionPreview.reveal
    KIF::FusionPreview.reveal = KIF::FusionPreview.on?
    begin
      return kif_fp_draw_window(dexNumber, level, x, y, isShiny, bodyShiny, headShiny, window_position)
    ensure
      KIF::FusionPreview.reveal = old
    end
  end
end

class FusionPreviewScreen
  def draw_window(dexNumber, level, x, y, isShiny = false, bodyShiny = false, headShiny = false, window_position = 0)
    look = nil
    if isShiny && defined?(KIF::Shiny) && @poke1 && @poke2
      body, head = (window_position == 0) ? [@poke1, @poke2] : [@poke2, @poke1]
      look = KIF::FusionPreview.look_for(dexNumber, body, head)
      look = nil if look && !KIF::Shiny.decide(look)[1]
    end
    return super unless look
    old = KIF::FusionPreview.color
    KIF::FusionPreview.color = [dexNumber, look]
    begin
      # PIF's palette (if this shiny also uses it) is applied by colorize!
      return super(dexNumber, level, x, y, false, false, false, window_position)
    ensure
      KIF::FusionPreview.color = old
    end
  end
end

module GameData
  class Species
    class << self
      alias kif_fp_front_sprite_bitmap front_sprite_bitmap unless method_defined?(:kif_fp_front_sprite_bitmap)

      def front_sprite_bitmap(species, *args)
        ret = kif_fp_front_sprite_bitmap(species, *args)
        c = KIF::FusionPreview.color
        if c && ret && c[0] == species
          begin
            KIF::Shiny.privatize(ret)
            KIF::Shiny.colorize!(ret, c[1], :sprite)
          rescue => e
            KIF.log("Fusion preview colours failed: #{e.message}")
          end
        end
        return ret
      end
    end
  end
end
