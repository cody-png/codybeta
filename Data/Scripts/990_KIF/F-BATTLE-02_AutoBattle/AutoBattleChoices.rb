#===============================================================================
# F-BATTLE-02 – Auto-Battle: the prompts it used to stop at (port addition,
# Cody 2026-10-09). KIF's Auto-Battle (and so this port) still waited for the
# player at three spots; each now has a setting under Battles:
#   * Auto-Battle Switching – Ask / AI decides / Stay in. The "<trainer> is
#     about to send in X. Will you switch?" offer (Shift style,
#     PokeBattle_Battle#pbEORSwitch). "AI decides": the offer is declined,
#     the new Pokémon comes in, and then the AI in use (PIF's or DemICE's,
#     Options > Battle AI) is asked whether your Pokémon should switch out
#     for it, and into whom - a free switch, judged with the new foe known.
#   * Auto-Battle Level Up – Show stats / Continue. The two stat windows
#     (PokeBattle_Scene#pbLevelUp) close by themselves.
#   * Auto-Battle New Moves – Ask / AI picks / Skip. When a Pokémon with four
#     moves wants a fifth (PokeBattle_Battle#pbLearnMove): "AI picks" scores
#     the five moves with the AI in use (its pbGetMoveScore) against every
#     Pokémon left in the opposing party and forgets the lowest - which may
#     be the new move; "Skip" never learns. Each pick goes to KIF_log.txt.
#   * Auto-Battle Evolutions – Watch / Automatic. The evolutions right after
#     a battle (pbEvolutionCheck, 001_Overworld_BattleStarting.rb:962) play
#     without waiting; a move the new form wants follows Auto-Battle New
#     Moves (AI picks scores against the party of the battle just fought).
#     B still stops an evolution, as always.
#   Only while Auto-Battle is on; with it off everything asks as before.
#===============================================================================
KIF::Options.define(:autobattle_switch, 1, :save)
KIF::Options.define(:autobattle_levelup, 1, :save)
KIF::Options.define(:autobattle_moves, 1, :save)
KIF::Options.define(:autobattle_evolve, 1, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Auto-Battle Switching"), [_INTL("Ask"), _INTL("AI decides"), _INTL("Stay in")],
                 proc { $PokemonSystem.autobattle_switch },
                 proc { |value| $PokemonSystem.autobattle_switch = value },
                 [_INTL("When a trainer is about to send in a Pokémon, you're asked if you want to switch"),
                  _INTL("The battle AI decides whether to switch, and into whom, once it sees the new Pokémon"),
                  _INTL("Your Pokémon stays in")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Auto-Battle Level Up"), [_INTL("Show stats"), _INTL("Continue")],
                 proc { $PokemonSystem.autobattle_levelup },
                 proc { |value| $PokemonSystem.autobattle_levelup = value },
                 [_INTL("The stat windows wait for you after a level up"),
                  _INTL("The battle goes on after a level up")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Auto-Battle New Moves"), [_INTL("Ask"), _INTL("AI picks"), _INTL("Skip")],
                 proc { $PokemonSystem.autobattle_moves },
                 proc { |value| $PokemonSystem.autobattle_moves = value },
                 [_INTL("You choose which move to forget, as usual"),
                  _INTL("The battle AI keeps the four moves it rates best against the opposing team"),
                  _INTL("New moves aren't learned while Auto-Battle is on")])
}

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Auto-Battle Evolutions"), [_INTL("Watch"), _INTL("Automatic")],
                 proc { $PokemonSystem.autobattle_evolve },
                 proc { |value| $PokemonSystem.autobattle_evolve = value },
                 [_INTL("Evolutions after a battle wait for you, as usual"),
                  _INTL("Evolutions after a battle play by themselves (B still stops one)")])
}

module KIF
  module AutoBattle
    class << self
      attr_accessor :last_battle, :evolving

      def setting(key)
        return ($PokemonSystem.send(key) rescue 0).to_i
      end

      # A battler built from a Pokémon outside the battle (for scoring)
      def fake_battler(battle, pkmn, index, idxParty)
        b = PokeBattle_Battler.new(battle, index)
        b.pbInitPokemon(pkmn, idxParty)
        b.pbInitEffects(false)
        return b
      end

      # [move ids in the order kept (4)], [move id forgotten], scores
      # Scores each of the 5 moves against every opposing Pokémon still
      # able (or, after the last one fainted, the whole opposing party at
      # full health) and averages.
      def rate_moves(battle, pkmn, idxParty, new_move)
        ai = battle.battleAI
        user = (idxParty && battle.pbFindBattler(idxParty)) ||
               fake_battler(battle, pkmn, 0, idxParty || ($Trainer.party.index(pkmn) || 0))
        foes = battle.pbParty(1).each_with_index.select { |p, _| p && !p.egg? && p.hp > 0 }
        if foes.empty?
          foes = battle.pbParty(1).each_with_index.select { |p, _| p && !p.egg? }.map { |p, i|
            c = Marshal.load(Marshal.dump(p)); c.heal; [c, i]
          }
        end
        targets = foes.map { |p, i|
          live = battle.battlers.find { |b| b && b.opposes?(0) && b.pokemon.equal?(p) && !b.fainted? }
          live || fake_battler(battle, p, 1, i)
        }
        ids = pkmn.moves.map(&:id) + [new_move]
        scores = {}
        ids.each do |id|
          mv = PokeBattle_Move.from_pokemon_move(battle, Pokemon::Move.new(id))
          vals = targets.map { |t|
            begin
              ai.pbGetMoveScore(mv, user, t, 100).to_f
            rescue StandardError
              0.0
            end
          }
          scores[id] = vals.empty? ? 0.0 : vals.sum / vals.length
        end
        worst = ids.min_by { |id| [scores[id], id == new_move ? 0 : 1] }   # ties: keep what it knows
        return [ids - [worst], worst, scores]
      end
    end
  end
end

class PokeBattle_Battle
  attr_reader :battleAI unless method_defined?(:battleAI)

  alias kif_autoch_pbEORSwitch pbEORSwitch unless method_defined?(:kif_autoch_pbEORSwitch)
  alias kif_autoch_pbDisplayConfirm pbDisplayConfirm unless method_defined?(:kif_autoch_pbDisplayConfirm)
  alias kif_autoch_pbRecallAndReplace pbRecallAndReplace unless method_defined?(:kif_autoch_pbRecallAndReplace)
  alias kif_autoch_pbLearnMove pbLearnMove unless method_defined?(:kif_autoch_pbLearnMove)

  alias kif_autoch_pbStartBattle pbStartBattle unless method_defined?(:kif_autoch_pbStartBattle)

  def pbStartBattle(*args)
    KIF::AutoBattle.last_battle = self
    return kif_autoch_pbStartBattle(*args)
  end

  def pbEORSwitch(*args)
    @kif_in_eor = true
    return kif_autoch_pbEORSwitch(*args)
  ensure
    @kif_in_eor = false
    @kif_shift_check = false
  end

  # The Shift-style offer is the only yes/no pbEORSwitch asks in a trainer
  # battle ("Use next Pokémon?" is wild battles only)
  def pbDisplayConfirm(msg)
    if @kif_in_eor && trainerBattle? && KIF::AutoBattle.on?
      case KIF::AutoBattle.setting(:autobattle_switch)
      when 1
        @kif_shift_check = true
        return false
      when 2
        return false
      end
    end
    return kif_autoch_pbDisplayConfirm(msg)
  end

  def pbRecallAndReplace(idxBattler, idxParty, *args)
    ret = kif_autoch_pbRecallAndReplace(idxBattler, idxParty, *args)
    if @kif_shift_check && opposes?(idxBattler)
      @kif_shift_check = false
      kif_auto_free_switch(0)
    end
    return ret
  end

  # The AI looks at the new foe and may switch your Pokémon out for free
  def kif_auto_free_switch(idx)
    b = @battlers[idx]
    return if !b || b.fainted? || !pbCanSwitch?(idx)
    pbClearChoice(idx)
    begin
      @battleAI.pbEnemyShouldWithdraw?(idx)
    rescue StandardError => e
      KIF.log("Auto-Battle switch check failed (#{e.class}: #{e.message})") if defined?(KIF.log)
    end
    choice = @choices[idx]
    to = (choice && choice[0] == :SwitchOut) ? choice[1] : -1
    pbClearChoice(idx)
    return if to.nil? || to < 0
    pbMessageOnRecall(b)
    kif_autoch_pbRecallAndReplace(idx, to)
    @battlers[idx].pbEffectsOnSwitchIn(true)
  end

  def pbLearnMove(idxParty, newMove)
    pkmn = pbParty(0)[idxParty]
    mode = KIF::AutoBattle.setting(:autobattle_moves)
    if pkmn && KIF::AutoBattle.on? && mode != 0 &&
       pkmn.moves.length >= Pokemon::MAX_MOVES && pkmn.moves.none? { |m| m && m.id == newMove }
      moveName = GameData::Move.get(newMove).name
      if mode == 2
        pbDisplay(_INTL("{1} did not learn {2}.", pkmn.name, moveName))
        return
      end
      begin
        kept, worst, scores = KIF::AutoBattle.rate_moves(self, pkmn, idxParty, newMove)
      rescue StandardError => e
        KIF.log("Auto-Battle move pick failed (#{e.class}: #{e.message}); not learned") if defined?(KIF.log)
        pbDisplay(_INTL("{1} did not learn {2}.", pkmn.name, moveName))
        return
      end
      if defined?(KIF.log)
        KIF.log("Auto-Battle (#{KIF::PowerfulAI.on? ? 'DemICE' : 'PIF'} AI): #{pkmn.name} #{GameData::Move.get(newMove).name}? " +
                scores.map { |id, s| "#{GameData::Move.get(id).name} #{s.round}" }.join(", ") +
                " -> forgets #{GameData::Move.get(worst).name}") rescue nil
      end
      if worst == newMove
        pbDisplay(_INTL("{1} did not learn {2}.", pkmn.name, moveName))
        return
      end
      slot = pkmn.moves.index { |m| m && m.id == worst }
      oldName = pkmn.moves[slot].name
      pkmn.moves[slot] = Pokemon::Move.new(newMove)
      pkmn.add_learned_move(newMove)
      battler = pbFindBattler(idxParty)
      battler.moves[slot] = PokeBattle_Move.from_pokemon_move(self, pkmn.moves[slot]) if battler
      pbDisplay(_INTL("{1} forgot how to use {2}. And...", pkmn.name, oldName))
      pbDisplay(_INTL("{1} learned {2}!", pkmn.name, moveName)) { pbSEPlay("Pkmn move learnt") }
      battler.pbCheckFormOnMovesetChange if battler
      return
    end
    return kif_autoch_pbLearnMove(idxParty, newMove)
  end
end

class PokeBattle_Scene
  alias kif_autoch_pbLevelUp pbLevelUp unless method_defined?(:kif_autoch_pbLevelUp)

  def pbLevelUp(*args)
    return kif_autoch_pbLevelUp(*args) unless KIF::AutoBattle.on? && KIF::AutoBattle.setting(:autobattle_levelup) == 1
    old = KIF::AutoBattle.confirming
    KIF::AutoBattle.confirming = true
    begin
      return kif_autoch_pbLevelUp(*args)
    ensure
      KIF::AutoBattle.confirming = old
    end
  end
end

# Evolutions right after a battle (Auto-Battle Evolutions: Automatic)
class Object
  unless private_method_defined?(:kif_autoch_pbEvolutionCheck)
    alias kif_autoch_pbEvolutionCheck pbEvolutionCheck
    alias kif_autoch_pbLearnMove pbLearnMove
  end
  private

  def pbEvolutionCheck(*args)
    ab = KIF::AutoBattle
    return kif_autoch_pbEvolutionCheck(*args) unless ab.on? && ab.setting(:autobattle_evolve) == 1
    old = [ab.confirming, ab.evolving]
    ab.confirming = true
    ab.evolving = true
    begin
      return kif_autoch_pbEvolutionCheck(*args)
    ensure
      ab.confirming, ab.evolving = old
    end
  end

  # A move the evolved form wants: Auto-Battle New Moves decides
  def pbLearnMove(pkmn, move, *args, &block)
    ab = KIF::AutoBattle
    return kif_autoch_pbLearnMove(pkmn, move, *args, &block) unless ab.evolving && pkmn
    mode = ab.setting(:autobattle_moves)
    id = (GameData::Move.get(move).id rescue nil)
    full = id && pkmn.numMoves >= Pokemon::MAX_MOVES && !pkmn.hasMove?(id)
    if mode == 0 || !full
      old = ab.confirming
      ab.confirming = false if mode == 0 && full   # the player picks: no self-confirming
      begin
        return kif_autoch_pbLearnMove(pkmn, move, *args, &block)
      ensure
        ab.confirming = old
      end
    end
    name = GameData::Move.get(id).name
    battle = ab.last_battle
    if mode == 1 && battle
      begin
        kept, worst, scores = ab.rate_moves(battle, pkmn, nil, id)
        KIF.log("Auto-Battle evolution (#{KIF::PowerfulAI.on? ? 'DemICE' : 'PIF'} AI): #{pkmn.name} #{name}? " +
                scores.map { |m, sc| "#{GameData::Move.get(m).name} #{sc.round}" }.join(", ") +
                " -> forgets #{GameData::Move.get(worst).name}") if defined?(KIF.log)
        if worst != id
          slot = pkmn.moves.index { |m| m && m.id == worst }
          oldName = pkmn.moves[slot].name
          pkmn.moves[slot] = Pokemon::Move.new(id)
          pkmn.add_learned_move(id)
          pbMessage(_INTL("{1} forgot how to use {2}.\\nAnd...\1", pkmn.name, oldName), &block)
          pbMessage(_INTL("\\se[]{1} learned {2}!\\se[Pkmn move learnt]", pkmn.name, name), &block)
          return true
        end
      rescue StandardError => e
        KIF.log("Auto-Battle evolution move pick failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      end
    end
    pbMessage(_INTL("{1} did not learn {2}.", pkmn.name, name), &block)
    return false
  end
end
