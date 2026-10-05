#===============================================================================
# F-SHINY-02 – PC shiny actions: Gamble, Sell Shininess, debug colour tools
# Source: KIF 0.20.7 016_UI/017_UI_PokemonStorage.rb
#   :1839-1841  menu labels          :2118-2154 pbShinySell
#   :2156-2228  pbKuraShinify        :2239-2416 pbDefineShinycolor (debug)
#   :2419-2447  pbRerollShiny (debug, 4 variants)
#   016_UI/015_UI_Options.rb:2076-2083 "Shiny Gamble Odds" slider (default 100)
#
# Gamble (P1000, free with Streamer's Dream): 1 in <odds> to become shiny
# (0 = always). On a shiny Pokémon it rolls new KIF colours instead, with
# twice the chance (KIF: roll 0 or 1). It loops until "Nevermind" or the
# money runs out, like KIF.
# Sell Shininess: +P1000, the Pokémon stops being shiny.
#
# 6.8.2 adaptation: unfusing restores the two Pokémon cloned at fusion time
# (Unfusing.rb unfuseCore), so changing only the fused Pokémon would be undone
# (or exploited: sell a fusion's shininess, unfuse, get the shiny parts back).
# The shiny state is therefore mirrored onto original_head / original_body
# for the parts marked head_shiny / body_shiny.
#===============================================================================
KIF::Options.define(:kuraygambleodds, 100, :save)

KIF::Options.add(:shinies, :save) {
  SliderOption.new(_INTL("Shiny Gamble Odds"), 0, 1000, KIF::Options.slider_step,
                   proc { $PokemonSystem.kuraygambleodds },
                   proc { |value| $PokemonSystem.kuraygambleodds = value },
                   _INTL("1 out of <x> | Choose the odds of Shinies from Gamble | 0 = Always"))
}

module KIF
  module ShinyActions
    GAMBLE_PRICE = 1000
    SELL_PRICE   = 1000

    def self.fusion?(pkmn)
      return (pkmn.isFusion? rescue false)
    end

    # Fusion parts kept for unfusing (6.8.2 only)
    def self.parts(pkmn)
      return [] unless fusion?(pkmn) && pkmn.respond_to?(:original_head)
      return [[pkmn.original_head, :head], [pkmn.original_body, :body]].select { |p, _| p }
    end

    def self.make_shiny(pkmn)
      pkmn.shiny = true
      KIF.ensure_fusion_shiny_parts(pkmn)
      parts(pkmn).each do |part, side|
        flag = (side == :head) ? pkmn.head_shiny : pkmn.body_shiny
        part.shiny = true if flag
      end
    end

    def self.remove_shiny(pkmn)
      pkmn.shiny = false
      pkmn.debug_shiny = false if pkmn.respond_to?(:debug_shiny=)
      if fusion?(pkmn)
        pkmn.head_shiny = false
        pkmn.body_shiny = false
        parts(pkmn).each do |part, _|
          part.shiny = false
          part.debug_shiny = false if part.respond_to?(:debug_shiny=)
        end
      end
    end

    def self.gamble_odds
      odds = $PokemonSystem.kuraygambleodds
      odds = 100 if odds.nil?
      return (odds <= 0) ? 1 : odds
    end
  end
end

# Shared by the PC (PokemonStorageScreen) and the party menu (KIF::PartyActionHost).
module KIF::PCActionMethods
  # KIF pbKuraShinify
  def kif_shiny_gamble(pkmn, selected)
    price = KIF::PCActions.price(KIF::ShinyActions::GAMBLE_PRICE)
    loop do
      if $Trainer.money < price
        pbPlayBuzzerSE
        pbDisplay(_INTL("Not enough Money!"))
        break
      end
      text = pkmn.shiny? ? _INTL("Gamble for new Color (P{1})", price) : _INTL("Gamble for Shiny (P{1})", price)
      choice = pbShowCommands(_INTL("You have P{1}", $Trainer.money.to_s_formatted),
                              [text, _INTL("Nevermind")])
      break if choice != 0
      $Trainer.money -= price
      roll = rand(KIF::ShinyActions.gamble_odds)
      if roll == 0 || (pkmn.shiny? && roll == 1)
        if pkmn.shiny?
          pkmn.kif_reroll_shiny_colors
          kif_refresh(selected)
          pbDisplay(_INTL("Wait... Its shiny color changed!"))
        else
          KIF::ShinyActions.make_shiny(pkmn)
          kif_refresh(selected)
          pbDisplay(_INTL("Wait... It became shiny!"))
        end
      else
        pbDisplay(_INTL("Not this time :c Try again!"))
      end
    end
  end

  # KIF pbShinySell
  def kif_shiny_sell(pkmn, selected)
    unless pkmn.shiny?
      pbPlayBuzzerSE
      pbDisplay(_INTL("Not Shiny!"))
      return
    end
    choice = pbShowCommands(_INTL("Are you sure to unshiny?"),
                            [_INTL("Unshiny (+P{1})", KIF::ShinyActions::SELL_PRICE), _INTL("Nevermind")])
    return if choice != 0
    $Trainer.money += KIF::ShinyActions::SELL_PRICE
    KIF::ShinyActions.remove_shiny(pkmn)
    kif_refresh(selected)
    pbDisplay(_INTL("Shiny, no more!"))
  end

  # KIF pbRerollShiny (debug). variant: 0 random, 1 PIF palette only,
  # 2 PIF+KIF, 3 KIF only (shinyimprovpif 2 / 1 / 0).
  def kif_shiny_reroll(pkmn, selected, variant)
    pkmn.kif_reroll_shiny_colors
    case variant
    when 1 then pkmn.shinyimprovpif = 2
    when 2 then pkmn.shinyimprovpif = 1
    when 3 then pkmn.shinyimprovpif = 0
    end
    kif_refresh(selected)
    pbDisplay(_INTL("Re-rolled into {1};{2};{3};{4}!", pkmn.shinyValue, pkmn.shinyR, pkmn.shinyG, pkmn.shinyB))
  end

  # Number prompt used by "Set Shiny Color". Returns nil when cancelled.
  def kif_choose_number(text, min, max, current, digits)
    params = ChooseNumberParams.new
    params.setMaxDigits(digits)
    params.setRange(min, max)
    current = [[current.to_i, min].max, max].min
    params.setDefaultValue(current)
    params.setInitialValue(current)
    params.setCancelValue(-1)
    params.setNegativesAllowed(false)
    qty = pbMessageChooseNumber(text, params)
    return nil if qty.nil? || qty < min || qty > max
    return qty
  end

  # KIF pbDefineShinycolor (debug)
  def kif_shiny_define(pkmn, selected)
    rgb = %w[R G B]
    if (q = kif_choose_number(_INTL("Hue (0-360)"), 0, 360, pkmn.shinyValue? + 180, 3))
      pkmn.shinyValue = q - 180
      kif_refresh(selected)
      pbDisplay(_INTL("Changed Shiny Hue!"))
    end
    [[:shinyR?, :shinyR=, "Red"], [:shinyG?, :shinyG=, "Green"], [:shinyB?, :shinyB=, "Blue"]].each do |get, set, name|
      if (q = kif_choose_number(_INTL("{1}Channel (0-25)", name), 0, 25, pkmn.send(get), 2))
        pkmn.send(set, q)
        kif_refresh(selected)
        pbDisplay(_INTL("Changed {1} Channel!", name))
      end
    end
    krs = pkmn.shinyKRS?
    3.times do |i|
      if (q = kif_choose_number(_INTL("{1} Increment (0-400)", rgb[i]), 0, 400, krs[i] + 200, 3))
        krs[i] = q - 200
        kif_refresh(selected)
        pbDisplay(_INTL("Changed {1} Increment!", rgb[i]))
      end
    end
    3.times do |i|
      if (q = kif_choose_number(_INTL("{1} Semi-Inverted (0-4)", rgb[i]), 0, 4, krs[3 + i], 1))
        krs[3 + i] = q
        kif_refresh(selected)
        pbDisplay(_INTL("Changed {1} Semi-Inverted!", rgb[i]))
      end
    end
    3.times do |i|
      if (q = kif_choose_number(_INTL("{1} Timid-Black (0-2)", rgb[i]), 0, 2, krs[6 + i], 1))
        krs[6 + i] = q
        kif_refresh(selected)
        pbDisplay(_INTL("Changed {1} Timid-Black!", rgb[i]))
      end
    end
    if (q = kif_choose_number(_INTL("0 = Nrm Spr | 1-2-3 = Shiny Spr (1=Forced, 3=KIF only when hybrid)"),
                              0, 3, pkmn.shinyimprovpif?, 1))
      pkmn.shinyimprovpif = q
      kif_refresh(selected)
      pbDisplay(_INTL("Changed Spr!"))
    end
  end
end

KIF::PCActions.add(:shiny_gamble,
  proc { |pkmn| pkmn.shiny? ? _INTL("Gamble for new Color") : _INTL("Gamble for Shiny") },
  proc { |screen, pkmn, selected, _h| screen.kif_shiny_gamble(pkmn, selected) })

KIF::PCActions.add(:shiny_sell,
  proc { |pkmn| pkmn.shiny? ? _INTL("Sell Shininess") : nil },
  proc { |screen, pkmn, selected, _h| screen.kif_shiny_sell(pkmn, selected) })

[[0, "Re-roll Shiny Color"], [1, "Re-roll Shiny Color (PIF Classic)"],
 [2, "Re-roll Shiny Color (PIF+KIF)"], [3, "Re-roll Shiny Color (KIF)"]].each do |variant, label|
  KIF::PCActions.add(:"shiny_reroll_#{variant}",
    proc { |_pkmn| $DEBUG ? _INTL(label) : nil },
    proc { |screen, pkmn, selected, _h| screen.kif_shiny_reroll(pkmn, selected, variant) })
end

KIF::PCActions.add(:shiny_define,
  proc { |_pkmn| $DEBUG ? _INTL("Set Shiny Color") : nil },
  proc { |screen, pkmn, selected, _h| screen.kif_shiny_define(pkmn, selected) })
