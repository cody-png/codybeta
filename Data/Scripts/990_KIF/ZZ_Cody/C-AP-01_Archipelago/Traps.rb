#===============================================================================
# C-AP-01 – Archipelago traps (2026-10-23)
#   A received item "TRAP_<KIND>" (apworld trap_percentage and the trap
#   weights) is kept in the save ($PokemonGlobal.kif_ap[:traps]) and runs at
#   a quiet moment: on the map, no message, menu or event, the player still
#   (KIF::AP.quiet?), not on Pinkan Island, one trap per check of the inbox.
#   A trap that can't run where the player is (a battle with no wild Pokemon
#   here) waits; the received items behind it are given as usual.
#     POISON     every healthy Pokemon that can be poisoned is (field poison
#                stops at 1 HP: Settings::POISON_FAINT_IN_FIELD is false)
#     PARALYSIS  every healthy Pokemon that can be paralyzed is
#     BATTLE     a wild battle with a Pokemon of this map at the party's
#                average level (waits for a map with wild Pokemon; never in
#                the Safari Zone or the Bug-Catching Contest; with Nuzlocke on
#                no battle starts, so no Pokemon can die and no route's
#                encounter is used up)
#     CONFUSION  the four direction buttons are shuffled for 50 steps on the
#                map, a new random shuffle each time (Cody); menus, battles
#                and move routes are not touched
#     MONEY      10% of your money, at most $5,000
#     SWAP       a fused party Pokemon swaps head and body (as the DNA
#                Reverser does; never an egg, a fainted or a rental one; it
#                keeps at least 1 HP)
#     PARTY_LOCK one party Pokemon won't battle for a while (Traps_PartyLock.rb)
#     WARP       back to the last Pokemon Center (Traps_Warp.rb)
#     PP_DRAIN   one move of the lead Pokemon drops to 0 PP (Traps_PPDrain.rb)
#===============================================================================
module KIF
  module AP
    module Traps
      KINDS = %w[POISON PARALYSIS BATTLE CONFUSION MONEY SWAP PARTY_LOCK WARP PP_DRAIN]   # the last three: Traps_<name>.rb
      CONFUSION_STEPS = 50
      MONEY_PERCENT = 10
      MONEY_MAX = 5000

      module_function

      def pending(d); d[:traps] ||= []; end

      # A received trap: kept until it can run
      def add(kind, who, d)
        kind = kind.to_s.upcase
        unless KINDS.include?(kind)
          KIF.log("Archipelago: unknown trap #{kind.inspect} skipped")
          return
        end
        pending(d) << [kind, who.to_s]
      end

      def source(who, d)
        return _INTL("yourself") if who.empty? || who == d[:slot]
        return who
      end

      # Runs the first waiting trap that can run here (one per call)
      def run_one(d)
        list = pending(d)
        return false if list.empty? || KIF::Rand.pinkan?
        i = list.index { |kind, _w| ready?(kind) }
        return false unless i
        kind, who = list.delete_at(i)
        send("run_#{kind.downcase}", source(who, d))
        return true
      rescue StandardError => e
        KIF.log("Archipelago: trap failed (#{e.class}: #{e.message})")
        return false
      end

      def ready?(kind)
        return locks.length < MAX_LOCKS if kind == "PARTY_LOCK"   # a third waits for an unlock
        return warp_ready? if kind == "WARP"
        return true unless kind == "BATTLE"
        return true if KIF::Nuzlocke.on?   # shown, but no battle
        return false if pbInSafari? || pbInBugContest?
        return false if $Trainer.able_pokemon_count == 0
        return !wild_species.nil?
      end

      def healthy(pkmn)
        return pkmn && !pkmn.egg? && pkmn.hp > 0 && pkmn.status == :NONE
      end

      def run_poison(who)
        hit = $Trainer.party.select { |pk| healthy(pk) && !pk.hasType?(:POISON) && !pk.hasType?(:STEEL) }
        hit.each { |pk| pk.status = :POISON; pk.statusCount = 0 }
        pbMessage(hit.empty? ? _INTL("A Poison Trap from {1}! None of your Pokémon could be poisoned.", who) :
                               _INTL("A Poison Trap from {1}! Your Pokémon were poisoned.", who))
      end

      def run_paralysis(who)
        hit = $Trainer.party.select { |pk| healthy(pk) && !pk.hasType?(:ELECTRIC) }
        hit.each { |pk| pk.status = :PARALYSIS; pk.statusCount = 0 }
        pbMessage(hit.empty? ? _INTL("A Paralysis Trap from {1}! None of your Pokémon could be paralyzed.", who) :
                               _INTL("A Paralysis Trap from {1}! Your Pokémon were paralyzed.", who))
      end

      # A species from this map's wild Pokemon: the tile's own kind first,
      # then any land or cave table (nil: none here)
      def wild_species
        enc = $PokemonEncounters
        return nil unless enc
        # tables are per time of day (LandDay, LandNight...)
        types = [enc.encounter_type] + [:Land, :Cave, :TallGrass].map { |t| enc.find_valid_encounter_type_for_time(t, pbGetTimeNow) }
        types.compact.uniq.each do |t|
          next unless GameData::EncounterType.exists?(t) && enc.has_encounter_type?(t)
          w = enc.choose_wild_pokemon(t)
          return w[0] if w
        end
        return nil
      rescue StandardError
        return nil
      end

      def party_level
        lv = $Trainer.party.reject(&:egg?).map(&:level)
        return lv.empty? ? 5 : (lv.sum / lv.length).clamp(2, GameData::GrowthRate.max_level)
      end

      def run_battle(who)
        if KIF::Nuzlocke.on?
          pbMessage(_INTL("A Battle Trap from {1}! Nuzlocke is on, so no battle starts.", who))
          return
        end
        species = wild_species
        level = party_level
        pbMessage(_INTL("A Battle Trap from {1}! A wild Pokémon attacks!", who))
        pbWildBattle(species, level)
      end

      def run_confusion(who)
        d = KIF::AP.data
        d[:confused] = CONFUSION_STEPS
        d[:confused_map] = shuffled_directions
        pbMessage(_INTL("A Confusion Trap from {1}! Your directions are shuffled for {2} steps.", who, CONFUSION_STEPS))
      end

      def run_money(who)
        lost = [$Trainer.money * MONEY_PERCENT / 100, MONEY_MAX].min
        $Trainer.money -= lost
        pbMessage(lost > 0 ? _INTL("A Money Trap from {1}! You dropped ${2}.", who, lost.to_s_formatted) :
                             _INTL("A Money Trap from {1}! You had no money to drop.", who))
      end

      def run_swap(who)
        list = $Trainer.party.select { |pk| pk && !pk.egg? && pk.hp > 0 && pk.isFusion? && !(pk.owner && pk.owner.name == "RENTAL") }
        if list.empty?
          pbMessage(_INTL("A Fusion Swap Trap from {1}! None of your Pokémon is fused, so nothing happens.", who))
          return
        end
        pk = list[rand(list.length)]
        pbMessage(_INTL("A Fusion Swap Trap from {1}! {2}'s head and body swap places.", who, pk.name))
        reverseFusion(pk)
        pk.hp = 1 if pk.hp <= 0   # a smaller HP total never knocks it out
      end

      # CONFUSION: on the map only (Game_Player#update_command_new reads dir4)
      def confused?
        d = KIF::AP.on? ? KIF::AP.data : nil
        return d && d[:confused].to_i > 0
      end

      def step
        d = KIF::AP.data
        return unless d && d[:confused].to_i > 0
        d[:confused] -= 1
        return if d[:confused] > 0
        @tell_normal = true
      end

      # "back to normal" is said at the next quiet moment
      def tell_normal
        return unless @tell_normal
        @tell_normal = false
        pbMessage(_INTL("Your directions are back to normal."))
      end

      FLIP = { 2 => 8, 8 => 2, 4 => 6, 6 => 4 }   # a confusion from before the shuffle (kept in older saves)
      DIRS = [2, 4, 6, 8]

      # a random order of the four directions in which no button keeps its own
      def shuffled_directions
        loop do
          to = DIRS.shuffle
          return DIRS.zip(to).to_h if DIRS.each_index.none? { |i| DIRS[i] == to[i] }
        end
      end

      def flip(dir)
        map = (KIF::AP.data[:confused_map] rescue nil)
        return (map.is_a?(Hash) ? map : FLIP)[dir] || dir
      end
    end
  end
end

Events.onStepTaken += proc { |_sender, _e| KIF::AP::Traps.step if $PokemonGlobal && $PokemonGlobal.kif_ap }

class Game_Player
  alias kif_ap_update_command_new update_command_new unless method_defined?(:kif_ap_update_command_new)

  def update_command_new(*args)
    return kif_ap_update_command_new(*args) unless KIF::AP::Traps.confused?
    KIF::AP::Traps.instance_variable_set(:@flipping, true)
    begin
      return kif_ap_update_command_new(*args)
    ensure
      KIF::AP::Traps.instance_variable_set(:@flipping, false)
    end
  end
end

module Input
  class << Input
    alias kif_ap_dir4 dir4 unless method_defined?(:kif_ap_dir4)
  end

  def self.dir4
    d = kif_ap_dir4
    return KIF::AP::Traps.instance_variable_get(:@flipping) ? KIF::AP::Traps.flip(d) : d
  end
end
