#===============================================================================
# F-BATTLE-09 – EV Allocation (2026-10-22, KIF 1.2.0)
#   EV Allocation (ev_alloc, per save, Off): EVs won in battle aren't put on
#   stats by themselves. They wait as EV points on the Pokémon, and you
#   spend them on the Summary's Skills page: USE there, Up/Down picks a
#   stat, Left/Right takes or gives 4 EVs, ACTION puts every EV back into
#   points (a free respec), USE again when done. PIF's limits stay: 252 in
#   one stat, 510 in all (spent and unspent together).
#   Vitamins, feathers and other items still raise their stat directly (you
#   already choose those). Points left over after turning it Off can still
#   be spent. No-EVs Mode: EVs don't count for stats, so there's nothing to
#   spend points on (they still pile up, for when it's turned off).
#   EVs Train Mode: foes yield 0 EVs (ExpEvIvModes.rb), so the only points
#   banked are a held Power item's +4 (doubled by Pokérus).
#   Mockups: Claude Docs/Base KIF/mockups/EV mockups.
#===============================================================================
KIF::Options.define(:ev_alloc, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("EV Allocation"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ev_alloc },
                 proc { |value| $PokemonSystem.ev_alloc = value },
                 [_INTL("EVs from battles go on stats as usual."),
                  _INTL("EVs from battles become points you spend yourself, on the Summary's Skills page.")])
}

class Pokemon
  attr_writer :kif_ev_pool

  # EV points waiting to be spent
  def kif_ev_pool
    return @kif_ev_pool || 0
  end
end

module KIF
  module EVAlloc
    STEP = 4
    STATS = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]

    def self.on?
      return $PokemonSystem && $PokemonSystem.respond_to?(:ev_alloc) && $PokemonSystem.ev_alloc == 1
    end

    def self.ev_total(pkmn)
      return STATS.sum { |s| pkmn.ev[s].to_i }
    end

    # Points still fitting under the 510 total
    def self.room(pkmn)
      return [Pokemon::EV_LIMIT - ev_total(pkmn) - pkmn.kif_ev_pool, 0].max
    end

    def self.add_points(pkmn, n)
      n = [n, room(pkmn)].min
      pkmn.kif_ev_pool = pkmn.kif_ev_pool + n if n > 0
      return n
    end

    # +STEP (or what's left) into a stat; returns how many moved
    def self.give(pkmn, stat)
      n = [STEP, pkmn.kif_ev_pool, Pokemon::EV_STAT_LIMIT - pkmn.ev[stat]].min
      return 0 if n <= 0
      pkmn.ev[stat] += n
      pkmn.kif_ev_pool -= n
      pkmn.calc_stats
      return n
    end

    def self.take(pkmn, stat)
      n = [STEP, pkmn.ev[stat]].min
      return 0 if n <= 0
      pkmn.ev[stat] -= n
      pkmn.kif_ev_pool += n
      pkmn.calc_stats
      return n
    end

    # Every EV back into points
    def self.reset(pkmn)
      total = ev_total(pkmn)
      STATS.each { |s| pkmn.ev[s] = 0 }
      pkmn.kif_ev_pool += total
      pkmn.calc_stats
      return total
    end

    # The Skills page offers spending when points wait or the option is on
    def self.available?(pkmn)
      return false if !pkmn || pkmn.egg?
      return on? || pkmn.kif_ev_pool > 0
    end
  end
end

# Battle EVs become points (Power items and Pokérus included, as PIF counts them)
class PokeBattle_Battle
  alias kif_eva_pbGainEVsOne pbGainEVsOne unless method_defined?(:kif_eva_pbGainEVsOne)

  def pbGainEVsOne(idxParty, defeatedBattler)
    return kif_eva_pbGainEVsOne(idxParty, defeatedBattler) unless KIF::EVAlloc.on?
    pkmn = pbParty(0)[idxParty]
    return kif_eva_pbGainEVsOne(idxParty, defeatedBattler) unless pkmn
    before = pkmn.ev.clone
    ret = kif_eva_pbGainEVsOne(idxParty, defeatedBattler)
    gained = KIF::EVAlloc::STATS.sum { |s| pkmn.ev[s].to_i - before[s].to_i }
    KIF::EVAlloc::STATS.each { |s| pkmn.ev[s] = before[s] }
    if gained > 0
      n = KIF::EVAlloc.add_points(pkmn, gained)
      (@kif_eva_gained ||= Hash.new(0))[pkmn] += n if n > 0
    end
    return ret
  end

  # One line per Pokémon at the end, so players know points are waiting
  # (not after every knockout). A win (or a catch) shows it in pbGainMoney,
  # after PIF's "You defeated ..." and the trainer's last words; anything
  # else before PIF's end-of-battle lines, while the battle is still shown.
  alias kif_eva_pbEndOfBattle pbEndOfBattle unless method_defined?(:kif_eva_pbEndOfBattle)
  alias kif_eva_pbGainMoney pbGainMoney unless method_defined?(:kif_eva_pbGainMoney)

  def pbEndOfBattle
    kif_eva_show_points unless @decision == 1 || @decision == 4
    return kif_eva_pbEndOfBattle
  end

  def pbGainMoney(*args)
    kif_eva_show_points
    return kif_eva_pbGainMoney(*args)
  end

  def kif_eva_show_points
    (@kif_eva_gained || {}).each do |pkmn, n|
      pbDisplayPaused(n == 1 ? _INTL("{1} got 1 EV point to spend (Summary, Skills).", pkmn.name) :
                               _INTL("{1} got {2} EV points to spend (Summary, Skills).", pkmn.name, n))
    end
    @kif_eva_gained = nil
  end
end

#-------------------------------------------------------------------------------
# Summary, Skills page: the points line, and spending them
#-------------------------------------------------------------------------------
class PokemonSummary_Scene
  alias kif_eva_drawPageThree drawPageThree unless method_defined?(:kif_eva_drawPageThree)

  def drawPageThree
    kif_eva_drawPageThree
    kif_eva_page_three_points
  end

  # also called by the IV/EV Skills page (F-UI-04), which draws without this hook
  def kif_eva_page_three_points
    kif_eva_draw_points if @is_player && KIF::EVAlloc.available?(@pokemon) && !@contestpage
  end

  KIF_EVA_YS = [70, 114, 146, 178, 210, 242]

  # Below the ability's name: what's waiting, or (while spending) the keys
  def kif_eva_draw_points(cursor = nil)
    overlay = @sprites["overlay"].bitmap
    green = [Color.new(54, 84, 54), Color.new(24, 192, 32)]
    if cursor
      # blended over the row (fill_rect would replace its text with a flat bar)
      bar = Bitmap.new(292, 30)
      bar.fill_rect(0, 0, 292, 30, Color.new(248, 200, 72))
      overlay.blt(222, KIF_EVA_YS[cursor] + 2, bar, bar.rect, 110)
      bar.dispose
      overlay.fill_rect(220, 274, 292, 110, Color.new(0, 0, 0, 0))
      pbDrawTextPositions(overlay, [
        [_INTL("EV points left: {1}", @pokemon.kif_ev_pool), 224, 278, 0, Color.new(248, 248, 248), Color.new(104, 104, 104)],
        [_INTL("Left/Right: -/+ {1} EVs", KIF::EVAlloc::STEP), 224, 320, 0, @text_color_base, @text_color_shadow],
        [_INTL("USE: done   ACTION: reset"), 224, 350, 0, @text_color_base, @text_color_shadow]
      ])
    elsif @pokemon.kif_ev_pool > 0
      overlay.fill_rect(220, 316, 292, 68, Color.new(0, 0, 0, 0))
      pbDrawTextPositions(overlay, [
        [_INTL("EV points to spend: {1}", @pokemon.kif_ev_pool), 224, 320, 0, green[0], green[1]],
        [_INTL("USE: spend them"), 224, 352, 0, @text_color_base, @text_color_shadow]
      ])
    end
  end

  # USE on the Skills page spends points (the item menu stays on the others)
  alias kif_eva_pbOptions pbOptions unless method_defined?(:kif_eva_pbOptions)

  def pbOptions
    if @page == 3 && @is_player && !@inbattle && KIF::EVAlloc.available?(@pokemon)
      kif_eva_allocate
      return true
    end
    return kif_eva_pbOptions
  end

  def kif_eva_allocate
    cursor = 0
    redraw = proc { drawPage(@page); kif_eva_draw_points(cursor) }
    redraw.call
    loop do
      Graphics.update
      Input.update
      pbUpdate
      # mouse (F-UI-13): point at a stat; click its left half -, right half +
      m = defined?(KIF::Mouse) ? KIF::Mouse : nil
      if m && m.active?
        row = KIF_EVA_YS.index { |y| m.over_rect?(222, y + 2, 292, 30) }
        if row && row != cursor
          cursor = row
          pbPlayCursorSE
          redraw.call
        end
        if m.clicked?
          m.swallow!
          # given/taken here: at 60+ fps the Frame rate's repeat? doesn't see a pressed key
          if row
            st = KIF::EVAlloc::STATS[cursor]
            n = m.x >= 368 ? KIF::EVAlloc.give(@pokemon, st) : KIF::EVAlloc.take(@pokemon, st)
            n > 0 ? pbPlayCursorSE : pbPlayBuzzerSE
            redraw.call
          end
          next
        end
      end
      stat = KIF::EVAlloc::STATS[cursor]
      if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        break
      elsif Input.repeat?(Input::UP)
        cursor = (cursor - 1) % 6
        pbPlayCursorSE
        redraw.call
      elsif Input.repeat?(Input::DOWN)
        cursor = (cursor + 1) % 6
        pbPlayCursorSE
        redraw.call
      elsif Input.repeat?(Input::RIGHT)
        KIF::EVAlloc.give(@pokemon, stat) > 0 ? pbPlayCursorSE : pbPlayBuzzerSE
        redraw.call
      elsif Input.repeat?(Input::LEFT)
        KIF::EVAlloc.take(@pokemon, stat) > 0 ? pbPlayCursorSE : pbPlayBuzzerSE
        redraw.call
      elsif Input.trigger?(Input::ACTION)
        if KIF::EVAlloc.ev_total(@pokemon) > 0 && pbConfirmMessage(_INTL("Put all of {1}'s EVs back into points?", @pokemon.name))
          KIF::EVAlloc.reset(@pokemon)
        end
        redraw.call
      end
    end
    drawPage(@page)
  end
end
