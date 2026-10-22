#===============================================================================
# F-BATTLE-05 – Nuzlocke (2026-10-22, Cody's rules)
#   * Only the first wild Pokémon met in each place can be caught. A place is
#     a map name without its floor ("Mt. Moon B1F" = "Mt. Moon"), so a whole
#     cave is one place. Dupes clause: a Pokémon whose evolution line you
#     already own (every half of a fusion) doesn't use up the place. Shiny
#     clause: a shiny can always be caught and doesn't use it up either.
#   * A Pokémon that faints is dead: it can't be healed or revived, fused or
#     unfused (a fusion that faints takes both halves with it). After the
#     battle it goes to the Graveyard (a list in Options), is released, or
#     stays fainted where it is (PIF's No reviving), by the setting.
#   * Whiteout (no Pokémon left standing): the run is over and the save
#     carries on with Nuzlocke Off, the run is over and the save is locked,
#     or a normal blackout (a Pokémon from the PC joins you).
#   Not covered: the Safari Zone (its own battle class), gift Pokémon.
#===============================================================================
KIF::Options.define(:ch_nuzlocke, 0, :save)
KIF::Options.define(:ch_nz_fainted, 0, :save)    # Graveyard / Released / Stays fainted
KIF::Options.define(:ch_nz_whiteout, 0, :save)   # Run over, keep playing / Run over, save locked / Normal blackout
KIF::Options.define(:ch_nz_dupes, 1, :save)
KIF::Options.define(:ch_nz_shiny, 1, :save)

class PokemonGlobalMetadata
  attr_writer :kif_nuzlocke
  def kif_nuzlocke
    @kif_nuzlocke ||= {}
  end
end

class Pokemon
  attr_accessor :kif_nz_dead
end

module KIF
  module Nuzlocke
    FAINTED_GRAVEYARD = 0
    FAINTED_RELEASED  = 1
    WHITEOUT_KEEP     = 0
    WHITEOUT_LOCK     = 1
    WHITEOUT_NORMAL   = 2

    class << self
      attr_accessor :lifted    # PIF's own no_reviving rule while a blackout heals the living
      attr_accessor :pending   # this wild battle: [place, counts?]
    end

    def self.on?
      return $PokemonSystem && $PokemonSystem.ch_nuzlocke == 1
    end

    def self.state
      return $PokemonGlobal ? $PokemonGlobal.kif_nuzlocke : {}
    end

    # "Mt. Moon B1F" -> "Mt. Moon", "Seafoam Islands B3" -> "Seafoam Islands"
    def self.place_name(map_id)
      name = (pbGetMapNameFromId(map_id) rescue nil).to_s
      name = name.sub(/\s*\(.*\)\s*\z/, "").sub(/\s+(B?\d+F|B\d+|\d+F)\z/i, "").strip
      return name.empty? ? "Map #{map_id}" : name
    end

    # Evolution lines of a Pokémon (both halves of a fusion)
    def self.lines(pkmn)
      dex = pkmn.species_data.id_number
      ids = dex > NB_POKEMON ? [getBodyID(dex), getHeadID(dex, getBodyID(dex))] : [dex]
      return ids.map { |n| (GameData::Species.get(n).get_baby_species rescue n) }
    end

    def self.owned_lines
      out = {}
      add = proc { |p| lines(p).each { |l| out[l] = true } if p && !p.egg? }
      $Trainer.party.each(&add)
      $PokemonStorage.maxBoxes.times { |b| $PokemonStorage.maxPokemon(b).times { |i| add.call($PokemonStorage[b, i]) } }
      (state[:graveyard] || []).each { |g| add.call(g[:pokemon]) }
      return out
    end

    # A wild battle starts: may its Pokémon be caught, and does it use up the place?
    #   :first (catchable, uses the place up), :free (catchable, doesn't),
    #   :used (the place's encounter is gone), :dupe (a line you already have)
    def self.judge(foes)
      place = place_name($game_map.map_id)
      return [place, :free] if $PokemonSystem.ch_nz_shiny == 1 && foes.any? { |p| p.shiny? }
      return [place, :used] if (state[:places] || {})[place]
      if $PokemonSystem.ch_nz_dupes == 1
        owned = owned_lines
        return [place, :dupe] if foes.all? { |p| lines(p).all? { |l| owned[l] } }
      end
      return [place, :first]
    end

    def self.use_place(place, foes)
      (state[:places] ||= {})[place] = foes.map { |p| p.species }
    end

    def self.death_place(p)
      g = (state[:graveyard] || []).find { |e| e[:pokemon].equal?(p) }
      return g ? g[:place] : "?"
    end

    def self.able?(p)
      return p && !p.egg? && p.hp > 0
    end

    # After every battle: who fainted is dead; they leave the party when a
    # living one is left (a whiteout is handled by pbStartOver)
    def self.after_battle
      dead = $Trainer.party.select { |p| p && !p.egg? && p.fainted? && !p.kif_nz_dead }
      dead.each { |p| bury(p) }
      move_dead_out if $Trainer.party.any? { |p| able?(p) }
    end

    def self.bury(p)
      p.kif_nz_dead = true
      entry = { :name => p.name, :species => p.species, :level => p.level, :place => place_name($game_map.map_id),
                :fusion => p.species_data.id_number > NB_POKEMON, :pokemon => p }
      (state[:deaths] ||= []) << entry.reject { |k, _| k == :pokemon }
      KIF.log("Nuzlocke: #{p.name} (#{p.species}, Lv. #{p.level}) died at #{entry[:place]}")
      @to_bury = (@to_bury || []) << entry
    end

    def self.move_dead_out
      fate = $PokemonSystem.ch_nz_fainted
      gone = $Trainer.party.select { |p| p && p.kif_nz_dead }
      return if gone.empty? || fate > FAINTED_RELEASED
      gone.each do |p|
        entry = (@to_bury || []).find { |e| e[:pokemon].equal?(p) } ||
                { :name => p.name, :species => p.species, :level => p.level, :place => place_name($game_map.map_id), :pokemon => p }
        (state[:graveyard] ||= []) << entry if fate == FAINTED_GRAVEYARD
        $Trainer.party.delete(p)
      end
      @to_bury = []
      names = gone.map(&:name).join(", ")
      pbMessage(fate == FAINTED_GRAVEYARD ? _INTL("{1} went to the Graveyard.", names) : _INTL("{1} was released.", names))
    end

    # First living Pokémon in the PC, taken out of its box
    def self.take_from_pc
      $PokemonStorage.maxBoxes.times do |b|
        $PokemonStorage.maxPokemon(b).times do |i|
          p = $PokemonStorage[b, i]
          next unless able?(p) && !p.kif_nz_dead
          $PokemonStorage[b, i] = nil
          return p
        end
      end
      return nil
    end

    def self.end_run(locked)
      state[:ended] = true
      if locked
        state[:failed] = true
        pbMessage(_INTL("Your Nuzlocke run is over. This save is locked and can't be played again."))
        KIF.log("Nuzlocke: run over, save locked")
        begin
          Game.save
        rescue => e
          KIF.log("Nuzlocke: the locked save couldn't be written (#{e.class}: #{e.message})")
        end
        $scene = pbCallTitle
        return :title
      end
      pbMessage(_INTL("Your Nuzlocke run is over. Nuzlocke is now Off for this save, so you can keep playing."))
      KIF.log("Nuzlocke: run over, save kept")
      $PokemonSystem.ch_nuzlocke = 0
      $Trainer.party.each { |p| p.kif_nz_dead = nil if p }
      return :kept
    end

    # Whiteout. Returns :title when the game goes back to the title screen.
    def self.whiteout
      return nil if $Trainer.party.any? { |p| able?(p) }
      case $PokemonSystem.ch_nz_whiteout
      when WHITEOUT_LOCK then return end_run(true)
      when WHITEOUT_KEEP then return end_run(false)
      end
      living = take_from_pc
      return end_run(false) unless living
      move_dead_out
      if $Trainer.party_full?
        spare = $Trainer.party.find { |p| p.kif_nz_dead }
        $Trainer.party.delete(spare)
        $PokemonStorage.pbStoreCaught(spare)
      end
      $Trainer.party.unshift(living)
      pbMessage(_INTL("{1} came from the PC to join you.", living.name))
      return nil
    end

    # The Graveyard as PC boxes of its own (30 a box), never part of the
    # player's PC: nothing that stores a Pokémon can put one there
    def self.graveyard_storage
      list = (state[:graveyard] || []).map { |g| g[:pokemon] }.compact
      size = PokemonBox::BOX_SIZE
      n = [(list.length + size - 1) / size, 1].max
      st = PokemonStorage.new(n, size)
      n.times do |b|
        st.boxes[b].name = n == 1 ? _INTL("Graveyard") : _INTL("Graveyard {1}", b + 1)
        st.boxes[b].background = 7   # Cave
      end
      list.each_with_index { |p, i| st[i / size, i % size] = p }
      return st
    end

    def self.show_graveyard
      if (state[:graveyard] || []).empty?
        pbMessage(_INTL("The Graveyard is empty."))
        return
      end
      pbFadeOutIn {
        scene = PokemonStorageScene.new
        KifGraveyardScreen.new(scene, graveyard_storage).pbStartScreen(0)
      }
    end
  end
end

#-------------------------------------------------------------------------------
# The Graveyard box: Summary only. Every way to change a box is refused.
#-------------------------------------------------------------------------------
class KifGraveyardScreen < PokemonStorageScreen
  def pbStartScreen(_command = 0, animate = true)
    @heldpkmn = nil
    @command = 0
    @scene.pbStartBox(self, 0, animate)
    loop do
      selected = @scene.pbSelectBox(@storage.party)
      break if selected.nil? || selected[0] == -3
      next if selected[0] == -4                       # box name: nothing to do here
      if selected[0] < 0                              # the party
        pbDisplay(_INTL("Only the Graveyard's Pokémon can be looked at here."))
        next
      end
      pokemon = @storage[selected[0], selected[1]]
      next unless pokemon
      cmd = pbShowCommands(_INTL("{1} died at {2}.", pokemon.name, KIF::Nuzlocke.death_place(pokemon)),
                           [_INTL("Summary"), _INTL("Cancel")])
      pbSummary(selected, nil) if cmd == 0
    end
    @scene.pbCloseBox
  end

  [:pbHold, :pbPlace, :pbSwap, :pbRelease, :pbStore, :pbWithdraw, :quickSwap, :pbBoxCommands,
   :pbItem, :pbMark, :renamePokemon, :organizeActions].each do |m|
    define_method(m) { |*_a| pbDisplay(_INTL("The Graveyard can only be looked at.")); nil }
  end
end

#-------------------------------------------------------------------------------
# Options (Challenges)
#-------------------------------------------------------------------------------
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Nuzlocke"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_nuzlocke },
                 proc { |value| $PokemonSystem.ch_nuzlocke = value },
                 [_INTL("No Nuzlocke rules."),
                  _INTL("Only the first wild Pokémon in each place can be caught, and a Pokémon that faints is dead.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Fainted Pokémon"), [_INTL("Graveyard"), _INTL("Released"), _INTL("Stay")],
                 proc { $PokemonSystem.ch_nz_fainted },
                 proc { |value| $PokemonSystem.ch_nz_fainted = value },
                 [_INTL("After the battle, a dead Pokémon goes to the Graveyard, a box you can look at but not change."),
                  _INTL("After the battle, a dead Pokémon is released."),
                  _INTL("A dead Pokémon stays where it is, fainted for good.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Nuzlocke whiteout"), [_INTL("Keep playing"), _INTL("Lock save"), _INTL("Blackout")],
                 proc { $PokemonSystem.ch_nz_whiteout },
                 proc { |value| $PokemonSystem.ch_nz_whiteout = value },
                 [_INTL("When your whole party is dead the run is over; Nuzlocke turns Off and you keep playing."),
                  _INTL("When your whole party is dead the run is over and the save is locked for good."),
                  _INTL("When your whole party is dead you black out as usual; a Pokémon from the PC joins you.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Dupes clause"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_nz_dupes },
                 proc { |value| $PokemonSystem.ch_nz_dupes = value },
                 [_INTL("Every first encounter counts, even a Pokémon you already have."),
                  _INTL("A Pokémon whose evolution line you already have doesn't use up the place.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Shiny clause"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_nz_shiny },
                 proc { |value| $PokemonSystem.ch_nz_shiny = value },
                 [_INTL("Shiny Pokémon follow the same rules."),
                  _INTL("A shiny can always be caught and doesn't use up the place.")])
}
KIF::Options.add(:challenges, :save) {
  ButtonOption.new(_INTL("Nuzlocke Graveyard"), proc { KIF::Nuzlocke.show_graveyard },
                   _INTL("The Pokémon that died on this run: a box you can look at (Summary) but not change. Also on the PC."))
}

# On the PC, once something has died
class KifGraveyardPC
  def shouldShow?
    return !(KIF::Nuzlocke.state[:graveyard] || []).empty?
  end

  def name
    return _INTL("Nuzlocke Graveyard")
  end

  def access
    KIF::Nuzlocke.show_graveyard
  end
end
PokemonPCList.registerPC(KifGraveyardPC.new)

#-------------------------------------------------------------------------------
# Hooks
#-------------------------------------------------------------------------------
class PokemonSystem
  alias kif_nz_no_reviving no_reviving unless method_defined?(:kif_nz_no_reviving)

  def no_reviving
    return true if KIF::Nuzlocke.on? && !KIF::Nuzlocke.lifted
    return kif_nz_no_reviving
  end
end

class Pokemon
  alias kif_nz_heal heal unless method_defined?(:kif_nz_heal)
  alias kif_nz_heal_HP heal_HP unless method_defined?(:kif_nz_heal_HP)

  def heal
    return if @kif_nz_dead && KIF::Nuzlocke.on?
    kif_nz_heal
  end

  def heal_HP
    return if @kif_nz_dead && KIF::Nuzlocke.on?
    kif_nz_heal_HP
  end
end

class PokeBattle_Battle
  alias kif_nz_pbStartBattle pbStartBattle unless method_defined?(:kif_nz_pbStartBattle)

  def pbStartBattle
    KIF::Nuzlocke.pending = nil
    if KIF::Nuzlocke.on? && wildBattle?
      begin
        foes = pbParty(1).compact
        place, verdict = KIF::Nuzlocke.judge(foes)
        @kif_nz = verdict
        @kif_nz_place = place
        KIF::Nuzlocke.pending = [place, foes] if verdict == :first
      rescue => e
        KIF.log("Nuzlocke: encounter check failed (#{e.class}: #{e.message})")
      end
    end
    kif_nz_pbStartBattle
  end

  attr_reader :kif_nz, :kif_nz_place
end

module ItemHandlers
  class << self
    alias kif_nz_triggerCanUseInBattle triggerCanUseInBattle unless method_defined?(:kif_nz_triggerCanUseInBattle)

    def triggerCanUseInBattle(item, pkmn, battler, move, firstAction, battle, scene, showMessages = true)
      verdict = battle.respond_to?(:kif_nz) ? battle.kif_nz : nil
      if [:used, :dupe].include?(verdict) && GameData::Item.get(item).is_poke_ball?
        if showMessages
          # two lines at most: PIF's battle message box shows two
          scene.pbDisplay(verdict == :used ? _INTL("Nuzlocke: you already had your encounter in {1}.", battle.kif_nz_place) :
                                             _INTL("Nuzlocke: you already have its evolution line (Dupes clause)."))
        end
        return false
      end
      return kif_nz_triggerCanUseInBattle(item, pkmn, battler, move, firstAction, battle, scene, showMessages)
    end
  end
end

alias kif_nz_pbAfterBattle pbAfterBattle unless defined?(kif_nz_pbAfterBattle)

def pbAfterBattle(decision, canLose)
  if KIF::Nuzlocke.on?
    begin
      place, foes = KIF::Nuzlocke.pending
      KIF::Nuzlocke.use_place(place, foes) if place
      KIF::Nuzlocke.pending = nil
      KIF::Nuzlocke.after_battle
    rescue => e
      KIF.log("Nuzlocke: after-battle step failed (#{e.class}: #{e.message})")
    end
  end
  kif_nz_pbAfterBattle(decision, canLose)
end

alias kif_nz_pbStartOver pbStartOver unless defined?(kif_nz_pbStartOver)

def pbStartOver(*args)
  if KIF::Nuzlocke.on? && $Trainer
    return if KIF::Nuzlocke.whiteout == :title
    # the living are healed as usual; the dead stay dead (Pokemon#heal)
    KIF::Nuzlocke.lifted = true
    begin
      return kif_nz_pbStartOver(*args)
    ensure
      KIF::Nuzlocke.lifted = false
    end
  end
  return kif_nz_pbStartOver(*args)
end

# A dead Pokémon can't be fused or unfused
alias kif_nz_pbDNASplicing pbDNASplicing unless defined?(kif_nz_pbDNASplicing)

def pbDNASplicing(pokemon, scene, *args)
  if KIF::Nuzlocke.on? && pokemon && pokemon.fainted?
    scene.pbDisplay(_INTL("Nuzlocke: {1} is dead and can't be fused or unfused.", pokemon.name))
    return false
  end
  return kif_nz_pbDNASplicing(pokemon, scene, *args)
end

alias kif_nz_pbUnfuse pbUnfuse unless defined?(kif_nz_pbUnfuse)

def pbUnfuse(pokemon, scene, *args)
  if KIF::Nuzlocke.on? && pokemon && pokemon.fainted?
    scene.pbDisplay(_INTL("Nuzlocke: {1} is dead and can't be unfused.", pokemon.name))
    return false
  end
  return kif_nz_pbUnfuse(pokemon, scene, *args)
end

# A locked run can't be loaded again
module Game
  class << self
    alias kif_nz_load load unless method_defined?(:kif_nz_load)

    def load(*args, &blk)
      ret = kif_nz_load(*args, &blk)
      if $PokemonGlobal && $PokemonGlobal.kif_nuzlocke[:failed]
        pbMessage(_INTL("This save's Nuzlocke run is over, and the save is locked."))
        $scene = pbCallTitle
      end
      return ret
    end
  end
end
