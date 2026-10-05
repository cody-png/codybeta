#===============================================================================
# F-UI-04 – Summary "Skills" page with IV / EV / base stat columns (Luminatron)
# Source: KIF 0.20.7 016_UI/006_UI_Summary.rb:724-793 (drawPageThree) and
#         Graphics/Pictures/Summary/bg_3.PNG (wider stat panel with a header).
#
# Columns: stat value, IV (orange), EV (green), base stat (blue, header "BST").
# No-EVs mode shows 0 EVs and Max-IVs mode shows 31 IVs, as in KIF.
#
# 6.8.2 adaptations:
#   * The KIF background is a new file, Graphics/Pictures/KIF/summary_bg_3.png;
#     the base Summary/bg_3.PNG is untouched. (Assets can't live in
#     Data/Scripts: the script loader evals every file it finds there.)
#   * Option "Summary IVs/EVs" (default On) gives back the vanilla page.
#   * The Hoenn contest lobby summary (053_PIF_Hoenn/.../014_Summary.rb, which
#     aliases drawPageThree) keeps its condition page.
#   * Stat values use 6.8.2's dark-mode aware text colours.
#   * Small +/- marks for the nature's raised/lowered stat (Cody, 2026-10-05).
#===============================================================================
KIF::Options.define(:summary_ivev, 1, :global)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Summary IVs/EVs"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.summary_ivev },
                 proc { |value| $PokemonSystem.summary_ivev = value },
                 [_INTL("The Skills page shows stats only."),
                  _INTL("The Skills page shows IVs, EVs and base stats.")])
}

KIF.guard_base("016_UI/006_UI_Summary.rb", 724498068, "PokemonSummary_Scene#drawPageThree")

class PokemonSummary_Scene
  KIF_SUMMARY_BG = "Graphics/Pictures/KIF/summary_bg_3"

  alias kif_ivev_drawPageThree drawPageThree unless method_defined?(:kif_ivev_drawPageThree)

  def drawPageThree
    if @contestpage || $PokemonSystem.summary_ivev != 1 || !pbResolveBitmap(KIF_SUMMARY_BG)
      return kif_ivev_drawPageThree
    end
    kif_draw_page_three_ivev
  end

  # Copy of 6.8.2 drawPageThree (006_UI_Summary.rb:692-745) with KIF's
  # stat table.
  def kif_draw_page_three_ivev
    @sprites["background"].setBitmap(KIF_SUMMARY_BG)
    overlay = @sprites["overlay"].bitmap
    base = Color.new(248, 248, 248)
    shadow = Color.new(104, 104, 104)
    # Determine which stats are boosted and lowered by the Pokémon's nature
    statshadows = {}
    GameData::Stat.each_main { |s| statshadows[s.id] = shadow }
    if !@pokemon.shadowPokemon? || @pokemon.heartStage > 3
      @pokemon.nature_for_stats.stat_changes.each do |change|
        statshadows[change[0]] = Color.new(136, 96, 72) if change[1] > 0
        statshadows[change[0]] = Color.new(64, 120, 152) if change[1] < 0
      end
    end
    # KIF stat table
    stats = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]
    values = [@pokemon.totalhp, @pokemon.attack, @pokemon.defense, @pokemon.spatk, @pokemon.spdef, @pokemon.speed]
    names = [_INTL("HP"), _INTL("Attack"), _INTL("Defense"), _INTL("Sp. Atk"), _INTL("Sp. Def"), _INTL("Speed")]
    ys = [70, 114, 146, 178, 210, 242]
    no_evs = $PokemonSystem.respond_to?(:noevsmode) && $PokemonSystem.noevsmode.to_i > 0
    max_ivs = $PokemonSystem.respond_to?(:maxivsmode) && $PokemonSystem.maxivsmode.to_i > 0
    base_stats = @pokemon.respond_to?(:kif_effective_base_stats) ? @pokemon.kif_effective_base_stats : @pokemon.baseStats
    textpos = []
    stats.each_with_index do |stat, i|
      y = ys[i]
      iv = max_ivs ? Pokemon::IV_STAT_LIMIT : @pokemon.iv[stat]
      ev = no_evs ? 0 : @pokemon.ev[stat]
      textpos.push([names[i], 236, y, 0, base, statshadows[stat]])
      textpos.push([sprintf("%d", values[i]), 380, y, 1, @text_color_base, @text_color_shadow])
      textpos.push([sprintf("%d", iv), 420, y, 1, Color.new(84, 64, 44), Color.new(248, 148, 0)])
      textpos.push([sprintf("%d", ev), 460, y, 1, Color.new(54, 84, 54), Color.new(24, 192, 32)])
      textpos.push([sprintf("%d", base_stats[stat]), 500, y, 1, Color.new(36, 60, 80), Color.new(88, 152, 248)])
      next if i != 0
      textpos.push([sprintf("%d", @pokemon.hp), 326, y, 1, base, shadow])
      textpos.push([_INTL("IVs"), 420, y - 23, 1, Color.new(64, 44, 24), Color.new(228, 128, 0)])
      textpos.push([_INTL("EVs"), 460, y - 23, 1, Color.new(34, 64, 34), Color.new(4, 172, 12)])
      textpos.push([_INTL("BST"), 500, y - 23, 1, Color.new(36, 60, 80), Color.new(88, 152, 248)])
    end
    textpos.push([_INTL("Ability"), 224, 278, 0, base, shadow])
    # Draw ability name and description
    ability = @pokemon.ability
    if ability
      textpos.push([ability.name, 362, 278, 0, @text_color_base, @text_color_shadow])
      drawTextEx(overlay, 224, 320, 282, 2, ability.description, @text_color_base, @text_color_shadow)
    end
    pbDrawTextPositions(overlay, textpos)
    kif_draw_nature_marks(overlay, stats, ys)
    # Draw HP bar
    if @pokemon.hp > 0
      w = @pokemon.hp * 96 * 1.0 / @pokemon.totalhp
      w = 1 if w < 1
      w = ((w / 2).round) * 2
      hpzone = 0
      hpzone = 1 if @pokemon.hp <= (@pokemon.totalhp / 2).floor
      hpzone = 2 if @pokemon.hp <= (@pokemon.totalhp / 4).floor
      pbDrawImagePositions(overlay, [["Graphics/Pictures/Summary/overlay_hp", 360, 110, 0, hpzone * 6, w, 6]])
    end
  end

  # Small "+" (raised) / "-" (lowered) left of the stat names, for the
  # nature (Cody's request 2026-10-05; mock-up in the play-test notes).
  def kif_draw_nature_marks(overlay, stats, ys)
    return if @pokemon.shadowPokemon? && @pokemon.heartStage <= 3
    nature = @pokemon.nature_for_stats
    return unless nature
    up = Color.new(224, 56, 48)
    down = Color.new(56, 96, 200)
    nature.stat_changes.each do |stat, change|
      i = stats.index(stat)
      next if i.nil? || change == 0
      cy = ys[i] + 21
      if change > 0
        overlay.fill_rect(229, cy, 5, 1, up)
        overlay.fill_rect(231, cy - 2, 1, 5, up)
      else
        overlay.fill_rect(229, cy, 5, 1, down)
      end
    end
  end
end
