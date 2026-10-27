#===============================================================================
# F-BATTLE-06 – Level Up Stats (new in KIF, player request, 2026-10-27)
# Not in KIF 0.20.7 or PIF 6.8.2.
#
#   Battles > "Level Up Stats" Show / Skip (per save, Show): Skip leaves out
#     the two stat windows after a level up ("Max. HP +3" ..., then the new
#     totals; PokeBattle_Scene#pbLevelUp) in every battle. EBDX's scene calls
#     PIF's method (F-BATTLE-12 EBDXCompat), so it is skipped there too. The
#     "grew to Lv. N!" message is shown before and stays. Auto-Battle Level
#     Up (F-BATTLE-02) still makes the windows close by themselves with Show.
#===============================================================================
KIF::Options.define(:levelup_stats, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Level Up Stats"), [_INTL("Show"), _INTL("Skip")],
                 proc { $PokemonSystem.levelup_stats },
                 proc { |value| $PokemonSystem.levelup_stats = value },
                 [_INTL("The stat windows show after a level up."),
                  _INTL("No stat windows after a level up.")])
}

class PokeBattle_Scene
  alias kif_lvstats_pbLevelUp pbLevelUp unless method_defined?(:kif_lvstats_pbLevelUp) || private_method_defined?(:kif_lvstats_pbLevelUp)

  def pbLevelUp(*args)
    return if ($PokemonSystem.levelup_stats.to_i rescue 0) == 1
    return kif_lvstats_pbLevelUp(*args)
  end
end
