#===============================================================================
# C-AP-01 – Archipelago Dexsanity (apworld 0.7.0, 2026-10-25)
#   A base species (dex 1-576) registered as caught sends location
#   DEX_BASE + its dex number when the slot has it. Every way of getting a
#   Pokemon goes through Player::Pokedex#set_owned (catching, hatching,
#   evolving, trades, gifts, unfusing, Improved Pokedex), so that one hook
#   covers them. A fusion sends its head and its body (fusions have no
#   locations; triple fusions send nothing). Milestones (slot
#   "dex_milestones": [[id, count], ...]) send once that many base species are
#   registered, a fusion's parts included.
#   set_owned runs mid-battle, mid-evolution and mid-trade, so the "found"
#   messages wait for a quiet moment (KIF::AP.grant_pending). Linking and
#   loading a save scan the Pokedex (owned species and owned fusions' parts)
#   and send what is already there, without messages.
#   The apworld's logic reads the game's own wild tables: linking a Dexsanity
#   slot is refused while wild Pokemon are randomized (or Fuse everything is
#   on), and when the save's mode (Classic / Remix, SWITCH_MODERN_MODE) isn't
#   the slot's game_mode (checked before the link changes anything). At quiet
#   moments a linked save is warned once per load about what makes checks
#   impossible: random wild Pokemon, the other mode (Legendary Mode's
#   "Trainers" option flips it), Nuzlocke (one catch per place).
#===============================================================================
module KIF
  module AP
    DEX_BASE = 30_000_000
    DEX_MILESTONE_BASE = 30_100_000

    module Dex
      @have = nil     # registered base dex numbers => true (this save's Pokedex)
      @global = nil   # the $PokemonGlobal @have belongs to
      @queue = []     # [location id, dex number (> 0) or -milestone count] to tell at a quiet moment
      @warned = nil

      module_function

      def slot?(d = KIF::AP.data)
        return false unless d.is_a?(Hash)
        return (d[:locations] || []).any? { |id| id.is_a?(Integer) && id > DEX_BASE && id < DEX_BASE + 200_000 }
      end

      def save_mode
        return $game_switches && $game_switches[SWITCH_MODERN_MODE] ? "remix" : "classic"
      end

      def mode_name(mode)
        return mode == "remix" ? _INTL("Remix") : _INTL("Classic")
      end

      # settings: a slot's randomizer, which replaces the save's when linking (apply_settings)
      def wild_randomized?(settings = nil)
        if settings.is_a?(Hash) && !settings.empty?
          return [:wild_mode, :fuse_all].any? { |k| (settings[k.to_s] || KIF::Rand::DATA_DEFAULTS[k] || 0).to_i > 0 }
        end
        return KIF::Rand.get(:wild_mode) > 0 || KIF::Rand.get(:fuse_all) > 0
      rescue StandardError
        return false
      end

      # Why this save can't link to a Dexsanity slot (nil: it can)
      def refuse_reason(d, settings = nil)
        return nil unless slot?(d)
        if wild_randomized?(settings)
          return _INTL("This Archipelago game has Pokedex checks, which need the normal wild Pokemon, but this save randomizes them. Turn off random wild Pokemon and Fuse everything in the randomizer, then link again.")
        end
        mode = d[:game_mode]
        if mode && mode != save_mode
          return _INTL("This Archipelago game's Pokedex checks were made for {1}, but this save plays {2}. Make the game again with game_mode: {3}, or link a {1} save.",
                       mode_name(mode), mode_name(save_mode), save_mode)
        end
        return nil
      end

      # The base dex numbers a species registers: itself, or a fusion's head and body
      def parts(species)
        n = getDexNumberForSpecies(species)
        return [] unless n.is_a?(Integer) && n > 0
        return [n] if n <= NB_POKEMON
        return [] if n >= Settings::ZAPMOLCUNO_NB
        body = getBodyID(n)
        return [getHeadID(n, body), body].select { |x| x.between?(1, NB_POKEMON) }.uniq
      rescue StandardError
        return []
      end

      # Every base species the Pokedex holds as owned, fusion parts included
      def registered(dex)
        have = {}
        (dex.instance_variable_get(:@owned_standard) || []).each_with_index { |v, n| have[n] = true if v && n.between?(1, NB_POKEMON) }
        (dex.instance_variable_get(:@owned_fusion) || []).each_with_index do |row, head|
          next unless row.is_a?(Array) && head.between?(1, NB_POKEMON) && row.include?(true)
          row.each_with_index do |v, body|
            next unless v == true && body.between?(1, NB_POKEMON)
            have[head] = true
            have[body] = true
          end
        end
        return have
      end

      # Scans the save's Pokedex once per loaded save (before its first new
      # species) and sends what it already holds. Returns the checks sent.
      def prepare
        return 0 if @global == $PokemonGlobal.object_id && @have
        return scan
      end

      def scan
        @global = $PokemonGlobal.object_id
        @queue = []
        @warned = nil
        @have = {}
        return 0 unless KIF::AP.on? && slot? && $Trainer
        before = KIF::AP.data[:checked].length
        registered($Trainer.pokedex).each_key { |n| note(n, false) }
        milestones(false)
        return KIF::AP.data[:checked].length - before
      rescue StandardError => e
        KIF.log("Archipelago: Pokedex scan failed (#{e.class}: #{e.message})")
        return 0
      end

      def note(n, tell)
        @have[n] = true
        id = DEX_BASE + n
        d = KIF::AP.data
        return unless d[:locations].include?(id) && !d[:checked].include?(id)
        KIF::AP.check!(id)
        @queue << [id, n] if tell
      end

      def milestones(tell)
        d = KIF::AP.data
        (d[:dex_milestones] || []).each do |id, k|
          next if @have.length < k || !d[:locations].include?(id) || d[:checked].include?(id)
          KIF::AP.check!(id)
          @queue << [id, -k] if tell
        end
      end

      # After Pokedex#set_owned (the player's Pokedex only)
      def owned(dex, species)
        return unless KIF::AP.on? && $Trainer && dex.equal?($Trainer.pokedex) && slot?
        prepare
        parts(species).each { |n| note(n, true) }
        milestones(true)
      rescue StandardError => e
        KIF.log("Archipelago: Pokedex check failed for #{species.inspect} (#{e.class}: #{e.message})")
      end

      # What makes some Pokedex checks impossible right now: [[key, message]]
      def warnings
        out = []
        if wild_randomized?
          out << [:wild, _INTL("Wild Pokemon are randomized in this save, so some Pokedex checks of this Archipelago game may be impossible. Turn off random wild Pokemon and Fuse everything in the randomizer.")]
        end
        mode = KIF::AP.data[:game_mode]
        if mode && mode != save_mode
          out << [:mode, _INTL("This save now plays {2}, but this Archipelago game's Pokedex checks were made for {1}, so some may be impossible. Set Options > Trainers back to {1}.",
                               mode_name(mode), mode_name(save_mode))]
        end
        if defined?(KIF::Nuzlocke) && KIF::Nuzlocke.on?
          out << [:nuzlocke, _INTL("Nuzlocke is on, so only the first wild Pokemon of each place can be caught and many Pokedex checks of this Archipelago game can't be done. Turn Nuzlocke off in Options > Challenges if you get stuck.")]
        end
        return out
      end

      # At a quiet moment (KIF::AP.grant_pending)
      def tell
        return unless @global == $PokemonGlobal.object_id
        if slot?
          @warned ||= {}
          warnings.each do |key, text|
            next if @warned[key]
            @warned[key] = true
            pbMessage(text)
          end
        end
        until @queue.empty?
          id, n = @queue.shift
          what = n > 0 ? _INTL("{1} was registered in the Pokedex.", GameData::Species.get(n).name) :
                         _INTL("{1} Pokemon registered in the Pokedex.", -n)
          pbMessage(_INTL("\\me[Item get]{1} {2}\\wtnp[30]", what, KIF::AP.found_text(id, :given)))
        end
      end
    end
  end
end

class Player < Trainer
  class Pokedex
    unless method_defined?(:kif_ap_set_owned) || private_method_defined?(:kif_ap_set_owned)
      alias kif_ap_set_owned set_owned
    end

    def set_owned(species, should_refresh_dexes = true)
      KIF::AP::Dex.prepare if KIF::AP.on? && $Trainer && equal?($Trainer.pokedex)   # what was there before counts silently
      ret = kif_ap_set_owned(species, should_refresh_dexes)
      KIF::AP::Dex.owned(self, species) if KIF::AP.on?
      return ret
    end
  end
end
