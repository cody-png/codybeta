#===============================================================================
# SCOPE-02 – PIF fixes: map events that crash (map sweep, 2026-10-22)
# tools/sweep_maps.rb in the kit ran every event page of every map; these are
# the crashes a player can reach, all in PIF 6.8.2's own maps and scripts.
#===============================================================================

# 1. Doors and warps to maps PIF doesn't ship (Train Station -> 238,
#    Route 39 -> 848, Mt. Moon -> 699, Boon Island -> 613, Ecruteak -> 572,
#    Underwater -> 601; the Silph Co. 6F stop before switch 825 -> 664).
#    Loading the map crashed the game; now the player just stays put.
class Scene_Map
  alias kif_mef_transfer_player transfer_player unless method_defined?(:kif_mef_transfer_player)

  def transfer_player(*args)
    id = $game_temp.player_new_map_id
    if id.is_a?(Integer) && id > 0 && !pbRgssExists?(sprintf("Data/Map%03d.rxdata", id))
      KIF.log("Transfer to map #{id} refused: PIF has no such map (from map #{$game_map.map_id rescue '?'})")
      $game_temp.player_transferring = false   # the scene's update still ends the fade
      pbPlayBuzzerSE rescue nil
      return
    end
    return kif_mef_transfer_player(*args)
  end
end

# 2. Switch 825 (SWITCH_V5_1) was only turned on by Continue, so a new game
#    sent the Silph Co. elevator's 6F and two staircases to the missing map
#    664 (and let a Goldenrod Tunnel scene run early) until a reload.
module Game
  class << self
    alias kif_mef_start_new start_new unless method_defined?(:kif_mef_start_new)

    def start_new(*args)
      ret = kif_mef_start_new(*args)
      $game_switches[SWITCH_V5_1] = true if $game_switches && defined?(SWITCH_V5_1)
      return ret
    end
  end
end

# 3. Water Labyrinth (map 594): its touch event calls a helper PIF 6.8.2
#    removed; KIF 0.20.7's was the same as getRandomCustomFusion.
unless defined?(getRandomCustomFusionForIntro)
  def getRandomCustomFusionForIntro(*args)
    return getRandomCustomFusion(*args)
  end
end

# 4. Registeel ice puzzle: a switch pressed before the reset tiles left the
#    pressed order a number, and adding a letter to it raised TypeError.
alias kif_mef_registeel_ice_press_switch registeel_ice_press_switch unless defined?(kif_mef_registeel_ice_press_switch)

def registeel_ice_press_switch(letter)
  registeel_ice_reset_switches unless pbGet(VAR_REGI_PUZZLE_SWITCH_PRESSED).is_a?(String)
  return kif_mef_registeel_ice_press_switch(letter)
end

# 5. Olivine City (map 138) event 21: a developer test NPC that crashes on a
#    removed method (and would reshuffle the Pokédex). Taken out.
KIF::MapPatches.add(138, "PIF fix: Olivine test NPC") do |map|
  ev = map.events[21]
  if ev && ev.pages.any? { |pg| pg.list.any? { |c| c.parameters.to_s.include?("test_is_fusion_of_any") } }
    map.events.delete(21)
  end
end

# 6. Two more developer NPCs that crash: Pallet Town (map 42) event 42
#    "LEGENDARY MODE ON" (flips mode switches, then crashes reshuffling
#    trainers) and the Olivine Mart (map 834) event 14 "Search by tags"
#    (crashes in search_hats). Only removed while they still say so.
{ 42 => [42, "LEGENDARY MODE ON"], 834 => [14, "Search by tags"] }.each do |map_id, (ev_id, text)|
  KIF::MapPatches.add(map_id, "PIF fix: developer NPC") do |map|
    ev = map.events[ev_id]
    map.events.delete(ev_id) if ev && ev.pages.any? { |pg| pg.list.any? { |c| c.code == 101 && c.parameters[0].to_s == text } }
  end
end

# 7. Celadon Café Backstore (map 407) event 9, the Pokémon seller: it prices
#    its daily stock from base stats through the old Essentials dex file
#    (pbOpenDexData / pbDexDataOffset(dexdata, species, 10), then six fgetb),
#    which 6.8.2 removed: restocking crashed. A stand-in reads the same
#    numbers from GameData. Only offset 10 (base stats) is used by any event.
class KIFDexDataStandIn
  ORDER = [:HP, :ATTACK, :DEFENSE, :SPEED, :SPECIAL_ATTACK, :SPECIAL_DEFENSE]

  def seek_species(species, offset)
    data = (GameData::Species.get(species) rescue nil)
    @bytes = (offset == 10 && data) ? ORDER.map { |s| data.base_stats[s].to_i } : []
  end

  def fgetb; return (@bytes || []).shift.to_i; end
  def close; end
end

def pbOpenDexData(*_args)
  return KIFDexDataStandIn.new
end

def pbDexDataOffset(dexdata, species, offset)
  dexdata.seek_species(species, offset) if dexdata.respond_to?(:seek_species)
end

# 8. Prices in event texts: PIF wrote them "$200 000" (a comma would split a
#    \ch[] choice), "$50000", "15,000$" or "50$", sometimes three ways in one
#    event (the Celadon Café sellers). Every price written in an event's text
#    or choices now reads like PIF's Poké Mart ("$200,000", "$50"); a \ch[]
#    choice with a comma is quoted, which \ch[] reads. Only the text changes:
#    what is charged is the event's own money commands. A price shown from a
#    game variable ("$\v[15]") prints as the game gives it. A line or choice
#    the loaded language translates (french.dat) is left alone: the English
#    text is its translation key. Maps are done as they load, common events
#    once the language is loaded (Cody, 2026-10-24: all of them).
module KIF
  module EventPrices
    def self.money(digits)
      return "$" + digits.delete(" ,").to_i.to_s_formatted
    end

    # "$200 000", "$50000", "15,000$", "50$" -> "$200,000", "$50,000", "$15,000", "$50"
    def self.prices(text)
      t = text.gsub(/(?<![\d$,])(\d{1,3}(?:,\d{3})+|\d+)\$/) { money($1) }
      return t.gsub(/\$(\d{1,3}(?:[ ,]\d{3})+|\d+)(?!\d|,\d)/) { money($1) }
    end

    def self.fix_text(text)
      m = text.match(/\\ch\[(\d+,\d+,)(.*)\]\z/)
      return prices(text) unless m
      fields = m[2].split(",").map { |f| g = prices(f); g.include?(",") ? "\"#{g}\"" : g }
      return prices(m.pre_match) + "\\ch[" + m[1] + fields.join(",") + "]"
    end

    def self.translated?(map_id, text)
      return MessageTypes.getFromMapHash(map_id, text) != text
    end

    def self.utf8(s)
      return s.to_s.dup.force_encoding("UTF-8")
    end

    def self.fix_map(map, map_id)
      map.events.each_value { |ev| ev.pages.each { |pg| fix_list(pg.list, map_id) if pg.list } }
    end

    # list: an event page's commands (or a common event's)
    def self.fix_list(list, map_id)
      list.each_with_index do |cmd, i|
        if cmd.code == 102 && cmd.parameters[0].is_a?(Array)
          next unless cmd.parameters[0].any? { |s| s.to_s.include?("$") }
          cmd.parameters[0] = cmd.parameters[0].map do |s|
            u = utf8(s)
            f = prices(u)
            (f == u || translated?(map_id, u)) ? s : f
          end
          next
        end
        next unless cmd.code == 101
        lines = [cmd]
        lines << list[i + lines.length] while list[i + lines.length] && list[i + lines.length].code == 401
        next unless lines.any? { |c| c.parameters[0].to_s.include?("$") }
        # joined the way Interpreter#command_101 joins them
        text = lines.map { |c| utf8(c.parameters[0]) }.inject { |a, t| (t != "" && !a.end_with?(" ")) ? "#{a} #{t}" : a + t }
        fixed = fix_text(text)
        next if fixed == text || translated?(map_id, text)
        cmd.parameters[0] = fixed
        lines[1..-1].each { |c| c.parameters[0] = "" }
      end
    end
  end
end

# Every map as it loads (after KIF::MapPatches)
alias kif_mef_load_data load_data unless defined?(kif_mef_load_data)

def load_data(filename, *args)
  ret = kif_mef_load_data(filename, *args)
  if filename.is_a?(String) && filename =~ /Map(\d+)\.rxdata\z/ && ret.respond_to?(:events) && ret.events
    begin
      KIF::EventPrices.fix_map(ret, $1.to_i)
    rescue => e
      KIF.log("Map prices not changed (#{filename}): #{e.class}: #{e.message}")
    end
  end
  return ret
end

# Common events once the language is loaded: they are read at start-up,
# before Game.set_up_system loads it
module Game
  class << self
    alias kif_mef_set_up_system set_up_system unless method_defined?(:kif_mef_set_up_system)

    def set_up_system(*args)
      ret = kif_mef_set_up_system(*args)
      begin
        ($data_common_events || []).each { |ce| KIF::EventPrices.fix_list(ce.list, 0) if ce && ce.list }
      rescue => e
        KIF.log("Common event prices not changed: #{e.class}: #{e.message}")
      end
      return ret
    end
  end
end
