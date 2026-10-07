#===============================================================================
# C-RAND-01 – Randomizer: Entrances page, spoiler log section, Entrance log
#===============================================================================
module KIF
  module Rand
    def self.page_entrances
      open_page(_INTL("Randomizer: Entrances"), _INTL("Doors between Kanto's outdoor maps and the places behind them."), nil) {
        rows = [
          enum(:entrances, _INTL("Entrances"), [_INTL("Off"), _INTL("Simple"), _INTL("Full")],
               [_INTL("Doors lead where they always did."),
                _INTL("Doors are shuffled; the two ends of a gate or cave stay on the same gate or cave."),
                _INTL("Doors are shuffled freely. Every layout can still be finished.")]),
          enum(:ent_doors, _INTL("Which doors"), [_INTL("Dungeons"), _INTL("Buildings"), _INTL("Everything")],
               [_INTL("Caves, towers, forests, the Mansion, gates and tunnels."),
                _INTL("Pokémon Centers, gyms, marts and houses."),
                _INTL("Both.")]),
          onoff(:ent_coupled, _INTL("Coupled"),
                _INTL("Going back through a door may lead somewhere else again."),
                _INTL("Going back the way you came returns you to where you were.")),
          onoff(:ent_hints, _INTL("Door hints"),
                _INTL("Nothing is shown when you come out of a shuffled door."),
                _INTL("A line names the door you came out of and the place it belongs to.")),
          enum(:ent_start, _INTL("Start"), [_INTL("Pallet"), _INTL("Random town"), _INTL("Random map")],
               [_INTL("Your journey starts in Pallet Town as usual."),
                _INTL("When Oak hands you the Pokédex, leaving the lab takes you to a random town's Pokémon Center, which becomes home. New games only."),
                _INTL("Like Random town, but any Pokémon Center in Kanto, routes included. New games only.")])
        ]
        unless $game_switches[SWITCH_DURING_INTRO]
          rows << ButtonOption.new(_INTL("Entrance log"), proc { KIF::Rand::ER.show_log },
                                   _INTL("Every shuffled door you have used so far, and where it led."))
        end
        rows
      }
    end

    class << self
      alias kif_ent_page_state page_state unless method_defined?(:kif_ent_page_state)
      def page_state(page)
        return on_off(dget(:entrances) > 0) if page == :entrances
        return kif_ent_page_state(page)
      end

      alias kif_ent_sections sections unless method_defined?(:kif_ent_sections)
      def sections
        out = kif_ent_sections
        out << ["Entrances", ER.method(:log_lines)] if ER.active?
        return out
      end
    end

    module ER
      # The doors used so far, as a reader
      def self.show_log
        s = state
        unless active? && s[:seen] && !s[:seen].empty?
          pbMessage(active? ? _INTL("You haven't used a shuffled door yet.") : _INTL("Entrances are not shuffled on this save."))
          return
        end
        lines = s[:seen].map { |door_id, kind| describe(door_id, kind) }.reject(&:empty?)
        lines << ""
        lines << _INTL("Doors not yet found: {1}", [s[:in].length - s[:seen].map(&:first).uniq.length, 0].max)
        Rand.show_lines(_INTL("Entrance log ({1} found)", s[:seen].length), lines)
      end

      # The hint after a shuffled warp: where you came out, and whose door it is
      def self.hint_for(map_id, event_id)
        t = targets[[map_id, event_id]]
        return nil unless t
        o = dat[:door_by_id][t[4]]
        return nil unless o
        if t[5] == :in
          i = dat[:door_by_id][state[:in][o[:id]] || o[:id]]
          return _INTL("{1} leads into {2}.", door_name(o), door_name(i))
        else
          back = dat[:door_by_id][state[:out][o[:id]] || o[:id]]
          return _INTL("Out of {1}, by way of {2}.", door_name(o), door_name(back))
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Main screen: the Entrances page button (after Exclusions)
#-------------------------------------------------------------------------------
class RandomizerOptionsScene
  alias kif_ent_pbGetOptions pbGetOptions unless method_defined?(:kif_ent_pbGetOptions)

  def pbGetOptions(inloadscreen = false)
    options = kif_ent_pbGetOptions(inloadscreen)
    return options unless KIF::Rand::ER.available?
    r = KIF::Rand
    btn = r::DynButton.new(proc { "#{_INTL("Entrances")} (#{r.page_state(:entrances)})" },
                           proc { r.page_entrances; kif_refresh },
                           _INTL("Shuffle the doors of Kanto; every layout stays beatable."))
    # before "Randomize now" when that button is there
    idx = options.index { |o| o.is_a?(r::DynButton) && o.name.to_s.start_with?(_INTL("Randomize now")) }
    idx ? options.insert(idx, btn) : options.push(btn)
    return options
  end
end

#-------------------------------------------------------------------------------
# Door hints: one line after a shuffled warp
#-------------------------------------------------------------------------------
module KIF
  module Rand
    module ER
      class << self
        attr_accessor :pending_hint
      end
    end
  end
end

class Interpreter
  alias kif_enthint_command_201 command_201 unless method_defined?(:kif_enthint_command_201)

  def command_201
    before = $game_temp.player_transferring
    r = kif_enthint_command_201
    if !before && $game_temp.player_transferring && KIF::Rand.dget(:ent_hints) == 1 && KIF::Rand::ER.active?
      KIF::Rand::ER.pending_hint = KIF::Rand::ER.hint_for(@map_id, @event_id)
    end
    return r
  end
end

class Scene_Map
  alias kif_enthint_transfer_player transfer_player unless method_defined?(:kif_enthint_transfer_player)

  def transfer_player(cancel_swimming = true)
    kif_enthint_transfer_player(cancel_swimming)
    KIF::Rand::ER.settle_home if KIF::Rand::ER.new_home
    hint = KIF::Rand::ER.pending_hint
    return unless hint
    KIF::Rand::ER.pending_hint = nil
    pbMessage(hint)
  rescue => e
    KIF::Rand::ER.pending_hint = nil
    KIF.log("Door hint failed (#{e.class}: #{e.message})")
  end
end
