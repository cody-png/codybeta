#===============================================================================
# F-BATTLE-04 – DemICE's Endgame Challenge ("Dem's Hard Mode")
# Source: KIF 0.20.7 101_DemICE's Endgame Challenge/ChallengeMode.rb and
#   KIF's map edits (Map314, 315-318, 328, 546, 783, 784) +
#   Data/trainers_challenge.dat
#
# How it plays (as KIF): after beating the champion a third time, "Dem"
# waits in the Pokémon League lobby. Beat his sample team to turn the
# challenge on (switch 850, PIF's own "DEM'S HARD MODE" switch). While on,
# on the League maps, the Fighting Arena and Mt. Silver's summit:
#   * the Elite Four, Blue, the 16 Fighting Arena gym leaders, Gold, Cynthia
#     and Dem use the challenge teams (Lv100 fusions, tuned to your party:
#     your highest level (min 60), heavy EVs, moves against Wonder Guard –
#     003_ChallengeTeams.rb);
#   * foes have double PP; singles only; no items in trainer battles;
#     switch style "Set"; no damage roll (F-BATTLE-03 Damage Variance);
#     accuracy x1.2 for your damaging moves, x1.3 for the foe's;
#     2-5-hit moves hit 3-5 times (Cody: challenge only – KIF did this in
#     every battle);
#   * beating Blue gives the next emblem (Bronze/Silver/Gold, PIF common
#     event 42) once; the Silver Emblem opens Cynthia's fight in the Mt.
#     Silver vortex, the Gold battle in the future summit; Dem's own final
#     team ends with a Hall of Fame entry "You completed the challenge!".
#   Talk to Dem again to turn it off/on or spar.
#
# Port structure (modular, Cody 2026-10-05):
#   * No base map files change: the KIF events/pages are added when a map
#     loads (KIF::MapPatches, 000_Core/008). Data: 001_EndgameEvents_data.rb,
#     generated from KIF's maps.
#   * No GameData.load_all copy: the challenge trainers load through
#     KIF::DataLoad (000_Core/007) from Data/KIF/trainers_challenge.dat.
#   * Texts through KIF::TextSwap (000_Core/006).
#
# 6.8.2 adaptations:
#   * 6.8.2's own Fighting Arena hard-mode pages call createTrainer and the
#     old customTrainerBattle(trainer, ...), which 6.8.2 no longer has (they
#     would crash); KIF's pages (challenge teams) replace them.
#   * 6.8.2 moved the champion cutscene to its own event (Map328 event 7);
#     KIF's emblem check is inserted there after Blue's "Darn it!" line.
#   * 6.8.2's future-Gold page also unlocks League rematch tiers
#     (unlock_new_league_tiers); the challenge Gold page does the same.
#   * 6.8.2's pbTrainerBattle (Hoenn rematch system) looks trainers up in
#     GameData::Trainer before battling; challenge-only trainers (Dem) and
#     versions (100-102) are found in the challenge data instead.
#   * Hall of Fame: game mode reads "Endgame Challenge" (6.8.2 adds the
#     difficulty in brackets).
#   * Not ported: KIF's TrainerType skill override (only ran when the data
#     was compiled, so it never did anything) and TrainerChallenge#to_trainer
#     (the data file holds plain Trainer entries, so KIF never called it).
#===============================================================================
module KIF
  module Endgame
    SWITCH    = 850                     # PIF "DEM'S HARD MODE"
    MAPS      = [314, 315, 316, 317, 318, 328, 546, 783, 784]
    DATA_FILE = "Data/KIF/trainers_challenge.dat"

    def self.on?
      return !!($game_switches && $game_switches[SWITCH])
    end

    def self.challenge_map?
      return on? && $game_map && MAPS.include?($game_map.map_id)
    end
  end

  def self.endgame_challenge_active?
    return KIF::Endgame.on?
  end
end

#-------------------------------------------------------------------------------
# Challenge trainer data
#-------------------------------------------------------------------------------
module GameData
  class TrainerChallenge < Trainer
    DATA = {}
    DATA_FILENAME = "KIF/trainers_challenge.dat"

    # Plain Marshal file (KIF's), not 6.8.2's encrypted format
    def self.load
      file = KIF::Endgame::DATA_FILE
      if File.exist?(file)
        const_set(:DATA, File.open(file, "rb") { |f| Marshal.load(f) })
      else
        KIF.log("Endgame Challenge: #{file} is missing")
      end
    end

    # A trainer the challenge has no team for keeps its normal team (KIF
    # failed with "trainer not found" here) – KIF port
    def self.try_get(tr_type, tr_name, tr_version = 0)
      return super || GameData::Trainer.kif_egc_try_get(tr_type, tr_name, tr_version)
    end
  end

  class Trainer
    class << self
      alias kif_egc_get get unless method_defined?(:kif_egc_get)
      alias kif_egc_try_get try_get unless method_defined?(:kif_egc_try_get)

      # Teams only the challenge has (Dem, versions 100-102)
      def get(tr_type, tr_name, tr_version = 0)
        if equal?(GameData::Trainer) && !kif_egc_try_get(tr_type, tr_name, tr_version)
          ret = GameData::TrainerChallenge.kif_egc_try_get(tr_type, tr_name, tr_version)
          return ret if ret
        end
        return kif_egc_get(tr_type, tr_name, tr_version)
      end

      def try_get(tr_type, tr_name, tr_version = 0)
        ret = kif_egc_try_get(tr_type, tr_name, tr_version)
        if !ret && equal?(GameData::Trainer)
          ret = GameData::TrainerChallenge.kif_egc_try_get(tr_type, tr_name, tr_version)
        end
        return ret
      end
    end

    # KIF ChallengeMode.rb:545-2411: tune the team on the challenge maps
    alias kif_egc_to_trainer to_trainer unless method_defined?(:kif_egc_to_trainer)

    def to_trainer
      return kif_egc_to_trainer unless KIF::Endgame.challenge_map?
      saved = [$game_switches[987], $game_switches[47], $game_switches[SWITCH_IS_REMATCH]]
      $game_switches[987] = false                 # randomized trainers
      $game_switches[47] = false                  # reversed mode
      $game_switches[SWITCH_IS_REMATCH] = false
      begin
        trainer = kif_egc_to_trainer
        KIF::Endgame.tune_team(trainer, @pokemon)
      ensure
        $game_switches[987], $game_switches[47], $game_switches[SWITCH_IS_REMATCH] = saved
      end
      return trainer
    end
  end
end

KIF::DataLoad.after_load_all("Endgame Challenge trainers") { GameData::TrainerChallenge.load }

# KIF ChallengeMode.rb:2-18
alias kif_egc_getTrainersDataMode getTrainersDataMode unless defined?(kif_egc_getTrainersDataMode)

def getTrainersDataMode
  return GameData::TrainerChallenge if KIF::Endgame.challenge_map?
  return kif_egc_getTrainersDataMode
end

#-------------------------------------------------------------------------------
# Battle rules
#-------------------------------------------------------------------------------
class PokeBattle_Battler
  alias kif_egc_pbInitPokemon pbInitPokemon unless method_defined?(:kif_egc_pbInitPokemon)

  # KIF :20-38 – foes have double PP
  def pbInitPokemon(pkmn, idxParty)
    kif_egc_pbInitPokemon(pkmn, idxParty)
    if KIF::Endgame.challenge_map? && !pbOwnedByPlayerSerious?
      @moves.each { |move| move.pp *= 2 }
    end
  end
end

class PokeBattle_Battle
  alias kif_egc_pbEORSwitch pbEORSwitch unless method_defined?(:kif_egc_pbEORSwitch)
  alias kif_egc_pbItemMenu pbItemMenu unless method_defined?(:kif_egc_pbItemMenu)
  alias kif_egc_setBattleMode setBattleMode unless method_defined?(:kif_egc_setBattleMode)

  # KIF :43-47 – Set style
  def pbEORSwitch(favorDraws = false)
    @switchStyle = false if KIF::Endgame.on? && trainerBattle?
    return kif_egc_pbEORSwitch(favorDraws)
  end

  # KIF :49-56 – no items in trainer battles
  def pbItemMenu(idxBattler, firstAction)
    if KIF::Endgame.on? && trainerBattle?
      pbDisplay(_INTL("Items can't be used in this challenge."))
      return false
    end
    return kif_egc_pbItemMenu(idxBattler, firstAction)
  end

  # KIF :58-76 – singles on the challenge maps
  def setBattleMode(mode)
    if KIF::Endgame.challenge_map?
      @sideSizes = [1, 1]
      return
    end
    return kif_egc_setBattleMode(mode)
  end
end

class PokeBattle_Move
  alias kif_egc_pbCalcAccuracyModifiers pbCalcAccuracyModifiers unless method_defined?(:kif_egc_pbCalcAccuracyModifiers)

  # KIF :344-350 (pbAccuracyCheck copy) – "You can now hit your Focus Blasts
  # my dear AI": x1.2 for the player's damaging moves, x1.3 for the foe's.
  def pbCalcAccuracyModifiers(user, target, modifiers)
    kif_egc_pbCalcAccuracyModifiers(user, target, modifiers)
    if KIF::Endgame.on?
      if user.pbOwnedByPlayerSerious?
        modifiers[:accuracy_multiplier] *= 1.2 if @baseDamage > 0
      else
        modifiers[:accuracy_multiplier] *= 1.3
      end
    end
  end
end

# KIF :367-378 – 2-5 hits become 3-5 (challenge only, Cody)
class PokeBattle_Move_0C0 < PokeBattle_Move
  alias kif_egc_pbNumHits pbNumHits unless method_defined?(:kif_egc_pbNumHits)

  def pbNumHits(user, targets)
    return kif_egc_pbNumHits(user, targets) unless KIF::Endgame.on?
    if @id == :WATERSHURIKEN && user.isSpecies?(:GRENINJA) && user.form == 2
      return 3
    end
    hitChances = [3, 3, 4, 4, 5, 5]
    r = @battle.pbRandom(hitChances.length)
    r = hitChances.length - 1 if user.hasActiveAbility?(:SKILLLINK)
    return hitChances[r]
  end
end

#-------------------------------------------------------------------------------
# Hall of Fame (KIF :80-117)
#-------------------------------------------------------------------------------
class HallOfFame_Scene
  alias kif_egc_getCurrentGameMode getCurrentGameMode unless method_defined?(:kif_egc_getCurrentGameMode)

  def getCurrentGameMode
    if KIF::Endgame.on?
      return ($game_map && $game_map.map_id == 314) ? _INTL("Endgame Challenge Completed!") : _INTL("Endgame Challenge")
    end
    return kif_egc_getCurrentGameMode
  end
end

KIF::TextSwap.add("League champion!\nCongratulations!\\^") {
  (KIF::Endgame.on? && $game_map && $game_map.map_id == 314) ? "You completed the challenge!\nCongratulations!\\^" : nil
}

#-------------------------------------------------------------------------------
# Map events (KIF's map edits, added when the maps load)
#-------------------------------------------------------------------------------
module KIF
  module Endgame
    MP = KIF::MapPatches
    EV = KIF::EndgameEvents

    def self.beaten_page?(page)
      c = page.condition
      return c.variable_valid && c.variable_id == 134
    end

    # Elite Four: challenge page goes before the "already beaten" page
    def self.add_elite_page(map, graphic, id_hint, data)
      ev = MP.find_by_graphic(map, graphic, id_hint)
      return KIF.log("Endgame: #{graphic} not found on map") unless ev
      MP.insert_page(ev, MP.page(data)) { |p| beaten_page?(p) }
    end

    # "unlock_new_league_tiers" before every Return to Title (6.8.2 does it)
    def self.with_tier_unlock(page_data)
      list = []
      page_data[:list].each do |c|
        list << [355, c[1], ["unlock_new_league_tiers"]] if c[0] == 352   # KIF port
        list << c
      end
      return page_data.merge(:list => list)
    end
  end
end

KIF::MapPatches.add(314, "Endgame: Dem") { |map|
  id = KIF::MapPatches.free_id(map, 850)
  map.events[id] = KIF::MapPatches.event(id, KIF::EndgameEvents::DEM)
}
KIF::MapPatches.add(315, "Endgame: Lorelei") { |map| KIF::Endgame.add_elite_page(map, "BW_Lorelei", 5, KIF::EndgameEvents::LORELEI_HARD) }
KIF::MapPatches.add(316, "Endgame: Bruno")   { |map| KIF::Endgame.add_elite_page(map, "Bruno_OW", 1, KIF::EndgameEvents::BRUNO_HARD) }
KIF::MapPatches.add(317, "Endgame: Agatha")  { |map| KIF::Endgame.add_elite_page(map, "Agatha_OW", 3, KIF::EndgameEvents::AGATHA_HARD) }
KIF::MapPatches.add(318, "Endgame: Lance")   { |map| KIF::Endgame.add_elite_page(map, "BW_Lance", 3, KIF::EndgameEvents::LANCE_HARD) }

KIF::MapPatches.add(328, "Endgame: Blue") { |map|
  mp = KIF::MapPatches
  blue = map.events[2]
  if blue && blue.pages[0].graphic.character_name == KIF::EndgameEvents::BLUE_HARD[:gfx][:character_name]
    blue.pages.push(mp.page(KIF::EndgameEvents::BLUE_HARD))
  else
    KIF.log("Endgame: Blue (Map328 event 2) not found")
  end
  # Emblem after the champion cutscene line "Darn it! ..."
  scene = map.events[7]
  page = scene && scene.pages.find { |p| p.condition.switch1_valid && p.condition.switch1_id == 425 }
  idx = page && page.list.index { |c| (t = mp.text_of(c)) && t.start_with?("Darn it!") }
  if idx
    idx += 1 while page.list[idx + 1] && page.list[idx + 1].code == 401
    page.list.insert(idx + 1, *mp.commands(KIF::EndgameEvents::EMBLEM_CHECK))
  else
    KIF.log("Endgame: champion cutscene (Map328 event 7) not found")
  end
}

KIF::MapPatches.add(546, "Endgame: Fighting Arena leaders") { |map|
  KIF::EndgameEvents::ARENA_HARD.each do |id, h|
    ev = map.events[id]
    pg = ev && ev.pages[h[:page]]
    if pg && pg.condition.switch1_id == KIF::Endgame::SWITCH && pg.graphic.character_name == h[:gfx]
      ev.pages[h[:page]] = KIF::MapPatches.page(h[:data])
    else
      KIF.log("Endgame: Fighting Arena event #{id} (#{h[:gfx]}) not found")
    end
  end
}

KIF::MapPatches.add(783, "Endgame: Cynthia and the vortex") { |map|
  mp = KIF::MapPatches
  if map.events[17]
    KIF.log("Endgame: Map783 event 17 is taken; Cynthia not added")   # her pages refer to event 17
  else
    map.events[17] = mp.event(17, KIF::EndgameEvents::CYNTHIA)
  end
  vortex = map.events[4]
  if vortex && vortex.pages.size >= 2
    KIF::EndgameEvents::VORTEX_HARD.each { |p| vortex.pages.push(mp.page(p)) }
  else
    KIF.log("Endgame: Mt. Silver vortex (Map783 event 4) not found")
  end
}

KIF::MapPatches.add(784, "Endgame: Gold") { |map|
  gold = map.events[5]
  if gold
    gold.pages.push(KIF::MapPatches.page(KIF::Endgame.with_tier_unlock(KIF::EndgameEvents::GOLD_HARD)))
  else
    KIF.log("Endgame: Gold (Map784 event 5) not found")
  end
}
