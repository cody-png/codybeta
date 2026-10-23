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
#   * Gift Pokémon (Cody, 2026-10-22): Free = gifts, eggs and trades never use
#     up a place; Counts = they use up the place they were received in when
#     its encounter is still unused (pbAddPokemon / pbAddToParty /
#     pbAddForeignPokemon / pbGenerateEgg / pbStartTrade; the Silent adders
#     are PIF's unfusing, Day Care and Mystery Gift, not gifts). PIF's own
#     pbAddPokemonID gifts count too. The starter never counts (Cody): every
#     lab gives it with pbAddPokemonID as the player's first Pokémon (Oak's
#     Lab and its Johto/Hoenn/Sinnoh/Custom copies, Legendary and randomized
#     starters via obtainStarter); PIF's Hoenn helpers use pbAddPokemonSilent.
#   * Kuray Shop (Cody, 2026-10-22): its Pokémon are the K-Eggs it sells
#     (F-ITEM-02); using one never uses up a place. Counts = the run gets one
#     K-Egg from the shop, another is refused before any money is taken;
#     Free = no limit. Independent of Gift Pokémon.
#   * Safari Zone (its own battle class, PokeBattle_SafariZone): only a catch
#     uses up the place, one per area ("Area 1".."Area 5", both maps of an
#     area are one) or one for the whole zone; after it the Ball command is
#     refused. Dupes and Shiny clauses apply as usual.
#===============================================================================
KIF::Options.define(:ch_nuzlocke, 0, :save)
KIF::Options.define(:ch_nz_fainted, 0, :save)    # Graveyard / Released / Stays fainted
KIF::Options.define(:ch_nz_whiteout, 0, :save)   # Run over, keep playing / Run over, save locked / Normal blackout
KIF::Options.define(:ch_nz_dupes, 1, :save)
KIF::Options.define(:ch_nz_shiny, 1, :save)
KIF::Options.define(:ch_nz_gifts, 0, :save)      # Free / Counts
KIF::Options.define(:ch_nz_safari, 0, :save)     # One catch per area / One catch for the whole zone
KIF::Options.define(:ch_nz_kuray, 0, :save)      # Counts / Free

class PokemonGlobalMetadata
  attr_writer :kif_nuzlocke
  def kif_nuzlocke
    @kif_nuzlocke ||= {}
  end
end

class Pokemon
  attr_accessor :kif_nz_dead
end

class Player
  attr_accessor :kif_nz_failed   # a locked Nuzlocke run (shown on the load screen)
end

module KIF
  module Nuzlocke
    FAINTED_GRAVEYARD = 0
    FAINTED_RELEASED  = 1
    WHITEOUT_KEEP     = 0
    WHITEOUT_LOCK     = 1
    WHITEOUT_NORMAL   = 2

    class << self
      attr_accessor :started_over   # pbStartOver ran during this battle's end
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
    def self.judge(foes, place = place_name($game_map.map_id))
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

    # Gift Pokémon: Counts
    def self.gift_received(pkmn, trade = false)
      return unless on? && $PokemonSystem.ch_nz_gifts == 1 && $game_map
      return if !trade && only_pokemon?   # the starter
      place = place_name($game_map.map_id)
      return if (state[:places] || {})[place]
      (state[:places] ||= {})[place] = [pkmn.is_a?(Pokemon) ? pkmn.species : pkmn]
      KIF.log("Nuzlocke: a gift used up #{place}")
    rescue => e
      KIF.log("Nuzlocke: gift check failed (#{e.class}: #{e.message})")
    end

    # The Pokémon just received is the only one the player has (party and PC)
    def self.only_pokemon?
      return false if $Trainer.party.compact.length > 1
      $PokemonStorage.maxBoxes.times { |b| $PokemonStorage.maxPokemon(b).times { |i| return false if $PokemonStorage[b, i] } }
      return true
    end

    # Kuray Shop: Counts limits the run to one K-Egg bought there
    def self.shop_pokemon?(item)
      return item.is_a?(Symbol) && defined?(KIF::KurayShop) && KIF::KurayShop.open? &&
             defined?(KIF::KurayEggs) && KIF::KurayEggs.egg?(item)
    end

    def self.shop_limited?(item)
      return on? && $PokemonSystem.ch_nz_kuray == 0 && shop_pokemon?(item)
    end

    # Safari Zone: each area ("Area 1"...) or the whole zone is one place
    def self.safari_place(map_id)
      return "Safari Zone" if $PokemonSystem.ch_nz_safari == 1
      return "Safari Zone #{place_name(map_id)}"
    end

    def self.safari_refusal(battle)
      return nil unless battle.respond_to?(:kif_nz)
      case battle.kif_nz
      when :used then return _INTL("Nuzlocke: you already caught a Pokémon in {1}.", battle.kif_nz_place)
      when :dupe then return _INTL("Nuzlocke: you already have its evolution line (Dupes clause).")
      end
      return nil
    end

    def self.death_place(p)
      g = (state[:graveyard] || []).find { |e| e[:pokemon].equal?(p) }
      return g ? g[:place] : "?"
    end

    #---------------------------------------------------------------------------
    # Load screen: a locked run is marked and can't be continued; its
    # Graveyard can still be looked at, straight from the save file
    #---------------------------------------------------------------------------
    class << self
      attr_accessor :preview   # the save data the load screen shows, when its run is locked
    end

    # A locked run is also written to a small file in the save folder, keyed
    # by the trainer's ID: autosaves and backups of that run are locked too,
    # and a save that couldn't be written still is
    LOCK_FILE = "KIF_nuzlocke_locked.txt"

    def self.lock_path
      return File.join(KIF.save_dir, LOCK_FILE)
    end

    def self.locked_ids
      return File.file?(lock_path) ? File.read(lock_path).split(/\s+/).map(&:to_i) : []
    rescue StandardError
      return []
    end

    def self.lock_trainer(player)
      return unless player && player.respond_to?(:id)
      ids = locked_ids
      return if ids.include?(player.id)
      File.open(lock_path, "ab") { |f| f.write("#{player.id}\r\n") }
    rescue StandardError => e
      KIF.log("Nuzlocke: lock file not written (#{e.class}: #{e.message})")
    end

    def self.failed_save?(save_data)
      return false unless save_data.is_a?(Hash)
      g = save_data[:global_metadata]
      return true if g && g.respond_to?(:kif_nuzlocke) && g.kif_nuzlocke[:failed]
      p = save_data[:player]
      return !!(p && p.respond_to?(:id) && locked_ids.include?(p.id))
    end

    # Saves locked before the player carried the mark get it here
    def self.mark_preview(save_data)
      self.preview = failed_save?(save_data) ? save_data : nil
      save_data[:player].kif_nz_failed = true if preview && save_data[:player]
    end

    def self.locked_menu
      loop do
        cmd = pbMessage(_INTL("This Nuzlocke run is over and the save is locked."),
                        [_INTL("View Graveyard"), _INTL("Back")], 2)
        break unless cmd == 0
        view_graveyard_of(preview)
      end
    end

    # The save's own Graveyard, without loading the game
    def self.view_graveyard_of(save_data)
      old = [$PokemonGlobal, $Trainer]
      $PokemonGlobal = save_data[:global_metadata]
      $Trainer = save_data[:player]
      show_graveyard
    ensure
      $PokemonGlobal, $Trainer = old
    end

    def self.able?(p)
      return p && !p.egg? && p.hp > 0
    end

    # After every battle: who fainted is dead; they leave the party when a
    # living one is left (a whiteout is handled by pbStartOver)
    def self.after_battle
      bury_fainted
      move_dead_out if $Trainer.party.any? { |p| able?(p) }
    end

    def self.bury_fainted
      $Trainer.party.select { |p| p && !p.egg? && p.fainted? && !p.kif_nz_dead }.each { |p| bury(p) }
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
        $Trainer.kif_nz_failed = true
        pbMessage(_INTL("Your Nuzlocke run is over. This save is locked and can't be played again."))
        KIF.log("Nuzlocke: run over, save locked")
        lock_trainer($Trainer)
        begin
          KIF.log("Nuzlocke: the locked save couldn't be written (no save slot); the lock file still holds it") if Game.save == false
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
  EnumOption.new(_INTL("Gift Pokémon"), [_INTL("Free"), _INTL("Counts")],
                 proc { $PokemonSystem.ch_nz_gifts },
                 proc { |value| $PokemonSystem.ch_nz_gifts = value },
                 [_INTL("Gifts, eggs and trades never use up a place."),
                  _INTL("A gift, egg or trade uses up the place you got it in, if you haven't had its encounter yet.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Safari Zone"), [_INTL("Per area"), _INTL("Whole zone")],
                 proc { $PokemonSystem.ch_nz_safari },
                 proc { |value| $PokemonSystem.ch_nz_safari = value },
                 [_INTL("In the Safari Zone only a catch uses up the place: one catch in each area."),
                  _INTL("In the Safari Zone only a catch uses up the place: one catch in the whole zone.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Kuray Shop"), [_INTL("Counts"), _INTL("Free")],
                 proc { $PokemonSystem.ch_nz_kuray },
                 proc { |value| $PokemonSystem.ch_nz_kuray = value },
                 [_INTL("You can get one Pokémon from the Kuray Shop on this run."),
                  _INTL("You can get any number of Pokémon from the Kuray Shop.")])
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

# On the pause menu while Nuzlocke is On with Fainted Pokémon: Graveyard (Cody)
KIF::PauseMenu.add(:kif_nz_graveyard, "Graveyard", icon: "menuIcons/GRAVEYARD", order: 50,
  condition: proc { KIF::Nuzlocke.on? && $PokemonSystem.ch_nz_fainted == KIF::Nuzlocke::FAINTED_GRAVEYARD },
  handler: proc { |_scene| KIF::Nuzlocke.show_graveyard; :stay })

#-------------------------------------------------------------------------------
# Hooks
#-------------------------------------------------------------------------------
class PokemonSystem
  alias kif_nz_no_reviving no_reviving unless method_defined?(:kif_nz_no_reviving)

  def no_reviving
    return true if KIF::Nuzlocke.on? && !KIF::Nuzlocke.lifted
    return kif_nz_no_reviving
  end

  # While Nuzlocke forces it, PIF's Challenge options (which write every row
  # back on closing) and PIF's blackout toggle don't change the player's own
  # No reviving
  alias kif_nz_set_no_reviving no_reviving= unless method_defined?(:kif_nz_set_no_reviving)

  def no_reviving=(value)
    return if KIF::Nuzlocke.on? && !KIF::Nuzlocke.lifted
    self.kif_nz_set_no_reviving(value)
  end
end

class Pokemon
  alias kif_nz_heal heal unless method_defined?(:kif_nz_heal)
  alias kif_nz_heal_HP heal_HP unless method_defined?(:kif_nz_heal_HP)

  def heal
    return if @kif_nz_dead && KIF::Nuzlocke.on?
    kif_nz_heal
  end

  # calc_stats keeps the HP missing from the total, so a level gained in the
  # PC or by Rare Candy would give a dead Pokémon HP back
  alias kif_nz_calc_stats calc_stats unless method_defined?(:kif_nz_calc_stats)

  def calc_stats(*args)
    r = kif_nz_calc_stats(*args)
    @hp = 0 if @kif_nz_dead && KIF::Nuzlocke.on?
    return r
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

# Safari Zone: judged when the battle starts; only a catch (decision 4) uses
# the place up
class PokeBattle_SafariZone
  alias kif_nz_safari_pbStartBattle pbStartBattle unless method_defined?(:kif_nz_safari_pbStartBattle)

  def pbStartBattle
    @kif_nz = nil
    if KIF::Nuzlocke.on?
      begin
        @kif_nz_place, @kif_nz = KIF::Nuzlocke.judge(@party2.compact, KIF::Nuzlocke.safari_place($game_map.map_id))
      rescue => e
        KIF.log("Nuzlocke: Safari check failed (#{e.class}: #{e.message})")
      end
    end
    ret = kif_nz_safari_pbStartBattle
    KIF::Nuzlocke.use_place(@kif_nz_place, @party2.compact) if ret == 4 && @kif_nz == :first && KIF::Nuzlocke.on?
    return ret
  end

  attr_reader :kif_nz, :kif_nz_place
end

# The Safari Ball command is refused (the turn isn't used) once the place is
# used up; Bait, Rock and Run still work
class PokeBattle_Scene
  alias kif_nz_pbSafariCommandMenu pbSafariCommandMenu unless method_defined?(:kif_nz_pbSafariCommandMenu)

  def pbSafariCommandMenu(index)
    loop do
      cmd = kif_nz_pbSafariCommandMenu(index)
      msg = cmd == 0 ? KIF::Nuzlocke.safari_refusal(@battle) : nil
      return cmd unless msg
      pbDisplayMessage(msg)
    end
  end
end

# Gift Pokémon: Counts (the place is used up only when the Pokémon arrived)
alias kif_nz_pbAddPokemon pbAddPokemon unless defined?(kif_nz_pbAddPokemon)
alias kif_nz_pbAddToParty pbAddToParty unless defined?(kif_nz_pbAddToParty)
alias kif_nz_pbAddForeignPokemon pbAddForeignPokemon unless defined?(kif_nz_pbAddForeignPokemon)
alias kif_nz_pbGenerateEgg pbGenerateEgg unless defined?(kif_nz_pbGenerateEgg)
alias kif_nz_pbAddPokemonID pbAddPokemonID unless defined?(kif_nz_pbAddPokemonID)

def pbAddPokemonID(pkmn, *args)
  ret = kif_nz_pbAddPokemonID(pkmn, *args)
  KIF::Nuzlocke.gift_received(pkmn) if ret
  return ret
end

def pbAddPokemon(pkmn, *args)
  ret = kif_nz_pbAddPokemon(pkmn, *args)
  KIF::Nuzlocke.gift_received(pkmn) if ret
  return ret
end

def pbAddToParty(pkmn, *args)
  ret = kif_nz_pbAddToParty(pkmn, *args)
  KIF::Nuzlocke.gift_received(pkmn) if ret
  return ret
end

def pbAddForeignPokemon(pkmn, *args)
  ret = kif_nz_pbAddForeignPokemon(pkmn, *args)
  KIF::Nuzlocke.gift_received(pkmn) if ret
  return ret
end

def pbGenerateEgg(pkmn, *args)
  ret = kif_nz_pbGenerateEgg(pkmn, *args)
  KIF::Nuzlocke.gift_received(pkmn) if ret
  return ret
end
# PIF's own aliases of pbGenerateEgg (event scripts) point at the hook too
alias pbAddEgg pbGenerateEgg
alias pbGenEgg pbGenerateEgg

alias kif_nz_pbStartTrade pbStartTrade unless defined?(kif_nz_pbStartTrade)

def pbStartTrade(pokemonIndex, newpoke, *args)
  ret = kif_nz_pbStartTrade(pokemonIndex, newpoke, *args)
  KIF::Nuzlocke.gift_received($Trainer.party[pokemonIndex] || newpoke, true)
  return ret
end

# Kuray Shop: Counts. A second K-Egg is refused when chosen (before the price
# check), only one can be bought at a time, and a bought one is recorded
class PokemonMart_Scene
  alias kif_nz_pbChooseBuyItem pbChooseBuyItem unless method_defined?(:kif_nz_pbChooseBuyItem)
  alias kif_nz_pbChooseNumber pbChooseNumber unless method_defined?(:kif_nz_pbChooseNumber)

  def pbChooseBuyItem(*args)
    loop do
      item = kif_nz_pbChooseBuyItem(*args)
      return item unless item && KIF::Nuzlocke.shop_limited?(item) && KIF::Nuzlocke.state[:kuray_shop]
      pbDisplayPaused(_INTL("Nuzlocke: you already got your Pokémon from the Kuray Shop."))
    end
  end

  def pbChooseNumber(helptext, item, maximum, *args)
    maximum = 1 if KIF::Nuzlocke.shop_limited?(item)
    return kif_nz_pbChooseNumber(helptext, item, maximum, *args)
  end
end

class PokemonMartAdapter
  alias kif_nz_addItem addItem unless method_defined?(:kif_nz_addItem)

  def addItem(item, *args)
    ret = kif_nz_addItem(item, *args)
    KIF::Nuzlocke.state[:kuray_shop] = true if ret && KIF::Nuzlocke.shop_limited?(item)
    return ret
  end
end

alias kif_nz_pbAfterBattle pbAfterBattle unless defined?(kif_nz_pbAfterBattle)

# The fainted are buried before PIF's step (it heals after a canLose loss),
# but leave the party only after it: its evolution check goes by party index.
# A battle that ends with nobody standing ends like a whiteout even when PIF
# doesn't black out (canLose battles, rematches, the Bug Contest, a partner
# winning alone). Self Battle fights with copies: nothing to bury.
def pbAfterBattle(decision, canLose)
  nz = KIF::Nuzlocke.on? && !(defined?(KIF::SelfBattle) && KIF::SelfBattle.instance_variable_get(:@active))
  if nz
    begin
      place, foes = KIF::Nuzlocke.pending
      KIF::Nuzlocke.use_place(place, foes) if place
      KIF::Nuzlocke.pending = nil
      KIF::Nuzlocke.started_over = false
      KIF::Nuzlocke.bury_fainted
    rescue => e
      KIF.log("Nuzlocke: after-battle step failed (#{e.class}: #{e.message})")
    end
  end
  ret = kif_nz_pbAfterBattle(decision, canLose)
  if nz && KIF::Nuzlocke.on?
    begin
      if $Trainer.party.any? { |p| KIF::Nuzlocke.able?(p) }
        KIF::Nuzlocke.move_dead_out
      elsif !KIF::Nuzlocke.started_over
        KIF::Nuzlocke.whiteout
      end
    rescue => e
      KIF.log("Nuzlocke: after-battle step failed (#{e.class}: #{e.message})")
    end
  end
  return ret
end

alias kif_nz_pbStartOver pbStartOver unless defined?(kif_nz_pbStartOver)

def pbStartOver(*args)
  if KIF::Nuzlocke.on? && $Trainer
    KIF::Nuzlocke.started_over = true
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

class PokemonStorageScreen
  alias kif_nz_pbFuseFromPC pbFuseFromPC unless method_defined?(:kif_nz_pbFuseFromPC)

  def pbFuseFromPC(selected, heldpoke, *args)
    if KIF::Nuzlocke.on?
      other = (@storage[selected[0], selected[1]] rescue nil)
      dead = [heldpoke, other].find { |p| p && p.fainted? }
      if dead
        pbDisplay(_INTL("Nuzlocke: {1} is dead and can't be fused.", dead.name))
        return
      end
    end
    return kif_nz_pbFuseFromPC(selected, heldpoke, *args)
  end
end

alias kif_nz_pbUnfuse pbUnfuse unless defined?(kif_nz_pbUnfuse)

def pbUnfuse(pokemon, scene, *args)
  if KIF::Nuzlocke.on? && pokemon && pokemon.fainted?
    scene.pbDisplay(_INTL("Nuzlocke: {1} is dead and can't be unfused.", pokemon.name))
    return false
  end
  return kif_nz_pbUnfuse(pokemon, scene, *args)
end

#-------------------------------------------------------------------------------
# Load screen (PIF's MultiSaves): mark, refuse Continue, offer the Graveyard
#-------------------------------------------------------------------------------
class PokemonLoadScreen
  alias kif_nz_load_save_file load_save_file unless method_defined?(:kif_nz_load_save_file)

  def load_save_file(*args)
    ret = kif_nz_load_save_file(*args)
    begin
      KIF::Nuzlocke.mark_preview(ret)
    rescue => e
      KIF::Nuzlocke.preview = nil
      KIF.log("Nuzlocke: save check failed (#{e.class}: #{e.message})")
    end
    return ret
  end
end

# A prepended module, not an alias: Save Folder (C-SYS-05) prepends
# pbChoose too, and an alias next to a prepend loops (test 294)
module KIF
  module Nuzlocke
    # Continue on a locked save opens the locked menu instead, until
    # something else is chosen
    def self.guard_choose(continue_idx)
      loop do
        ret = yield
        return ret unless continue_idx && continue_idx >= 0 && ret == continue_idx && preview
        locked_menu
      end
    end

    module LoadChooseHook
      def pbChoose(*args)
        KIF::Nuzlocke.guard_choose(args[1]) { super(*args) }
      end
    end
  end
end
PokemonLoad_Scene.prepend(KIF::Nuzlocke::LoadChooseHook)

class PokemonLoadPanel
  alias kif_nz_refresh refresh unless method_defined?(:kif_nz_refresh)

  def refresh
    redraw = @refreshBitmap && !@refreshing && !disposed?
    kif_nz_refresh
    return unless redraw && @isContinue && @trainer && @trainer.respond_to?(:kif_nz_failed) && @trainer.kif_nz_failed
    begin
      grave = Bitmap.new("Graphics/Icons/menuIcons/GRAVEYARD")
      self.bitmap.blt(32 + self.bitmap.text_size(@title.to_s).width + 10, 4, grave, grave.rect)
      grave.dispose
      pbDrawTextPositions(self.bitmap, [[_INTL("Nuzlocke over"), 112, 80, 0, Color.new(240, 72, 88), Color.new(160, 64, 64)]])
    rescue => e
      KIF.log("Nuzlocke: load-screen mark failed (#{e.class}: #{e.message})")
    end
  end
end

# Battle Frontier / organized battles heal everyone afterwards with PIF's
# rule: a Pokémon that faints there isn't dead
alias kif_nz_pbOrganizedBattleEx pbOrganizedBattleEx unless defined?(kif_nz_pbOrganizedBattleEx)

def pbOrganizedBattleEx(*args)
  old = KIF::Nuzlocke.lifted
  KIF::Nuzlocke.lifted = true
  begin
    return kif_nz_pbOrganizedBattleEx(*args)
  ensure
    KIF::Nuzlocke.lifted = old
  end
end

# A locked run can't be loaded from Savefile management (backups) either
class PokemonLoadScreen
  alias kif_nz_savefileOptions savefileOptions unless method_defined?(:kif_nz_savefileOptions)

  def savefileOptions(*args)
    data = kif_nz_savefileOptions(*args)
    if data && KIF::Nuzlocke.failed_save?(data)
      pbMessage(_INTL("This is a save of a Nuzlocke run that is over, so it can't be played."))
      return nil
    end
    return data
  end
end
