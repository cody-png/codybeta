#===============================================================================
# C-RAND-01 – Randomizer: trades and NPC requests (Cody, 2026-10-06)
#   * Trades: Off / Swap (what the Pokémon became; fusions part by part –
#     PIF never randomized the 22 fusion trades) / Random (each trade rolls its
#     own within the Strength range, fixed by the seed and the trade).
#   * NPC requests: when an event asks for a specific Pokémon (trades,
#     quests: "species == :ABRA", pbHasSpecies?(:X)):
#       Original – that exact Pokémon;
#       Swapped  – what it became (Swap mode); in Route / Dynamic modes there
#                  is no "became", so any Pokémon;
#       Any      – any Pokémon.
#     PokéRadar rares are always asked for as what they became.
#   * The NPC's lines name the new Pokémon ("…for a Pidgey!" with a/an fixed);
#     with Any, the first line naming the Pokémon is followed by
#     "(Any Pokémon will do.)". Only inside the event that asks.
# The event's own scripts are read to find what it asks for; nothing in the
# maps is changed.
#===============================================================================
module KIF
  module Rand
    REQUEST_SETTINGS = [[:npc_requests, :enum, 3]]   # Original / Swapped / Any
    # (only once, even if this file is loaded again)
    REQUEST_SETTINGS.each { |st| DATA_SETTINGS << st unless DATA_KEYS.include?(st[0]) }
    REQUEST_SETTINGS.each { |st| DATA_KEYS << st[0] unless DATA_KEYS.include?(st[0]) }
    DATA_DEFAULTS[:npc_requests] = 1

    REQUEST_RE = /species\s*==\s*:(\w+)|isSpecies\?\(\s*:(\w+)|pbHasSpecies\?\(\s*:(\w+)/
    TRADE_RE = /pbStartTrade\(\s*[^,]+,\s*(?:\n\s*)?:(\w+)/

    #---------------------------------------------------------------------------
    # Trades
    #---------------------------------------------------------------------------
    # The species a trade gives (nil = unchanged)
    def self.trade_result(species, map_id = nil, event_id = nil)
      mode = get(:trades)
      return nil if mode == 0 || !pokemon_parts_on?
      dex = dex_of(species)
      return nil if dex <= 0 || dex >= Settings::ZAPMOLCUNO_NB
      new = nil
      if mode == 1
        ensure_dex
        new = follow_wild(dex)
      else
        map_id ||= self.map_id
        event_id ||= self.event_id
        max = (fused?(dex) || sw(SWITCH_RANDOM_WILD_TO_FUSION)) ? PBSpecies.maxValue : NB_POKEMON
        new = with_seed(:trade, map_id, event_id, dex) {
          dex_of(getNewSpecies(dex, get(:wild_bst), false, max, sw(SWITCH_RANDOM_WILD_LEGENDARIES)))
        }
      end
      return nil unless new && valid_dex?(new) && new != dex
      return GameData::Species.get(new).species
    end

    #---------------------------------------------------------------------------
    # What an event asks for, and what it should say instead
    #---------------------------------------------------------------------------
    def self.event_script_text(list)
      parts = []
      list.each do |cmd|
        case cmd.code
        when 355, 655 then parts << cmd.parameters[0].to_s
        when 111 then parts << cmd.parameters[1].to_s if cmd.parameters[0] == 12
        end
      end
      return parts.join("\n")
    end

    # Requested species => what it should be (a species, :any, or nil)
    def self.request_target(sp)
      return nil unless pokemon_parts_on?
      mode = get(:wild_mode)
      if radar_rare_originals.include?(sp) && mode > 0
        return :any if mode == 3
        return radar_rare(sp, map_id)
      end
      case dget(:npc_requests)
      when 2 then return :any
      when 1
        return nil if mode == 0
        return :any unless mode == 1
        ensure_dex
        to = follow_wild(dex_of(sp))
        return nil unless to > 0 && valid_dex?(to)
        to_sp = GameData::Species.get(to).species
        return to_sp == sp ? nil : to_sp
      end
      return nil
    end

    # [[original species, replacement species or :any, kind], ...] for an
    # event's command list (cached per list and per randomizer state)
    def self.request_subs(list)
      return nil unless list && $PokemonGlobal && pokemon_parts_on?
      @req_cache ||= {}
      key = [list.object_id, seed, get(:wild_mode), get(:trades), dget(:npc_requests), data[:visit].to_i, map_id]
      return @req_cache[key] if @req_cache.key?(key)
      @req_cache.clear if @req_cache.length > 64
      text = event_script_text(list)
      subs = []
      text.scan(REQUEST_RE) do |a, b, c|
        sp = (a || b || c).to_sym
        next unless GameData::Species.exists?(sp)
        next if subs.any? { |s| s[0] == sp }
        to = request_target(sp)
        subs << [sp, to, :request] if to
      end
      text.scan(TRADE_RE) do |m|
        sp = m[0].to_sym
        next unless GameData::Species.exists?(sp)
        next if subs.any? { |s| s[0] == sp }
        to = trade_result(sp)
        subs << [sp, to, :trade] if to
      end
      @req_cache[key] = subs.empty? ? nil : subs
      return @req_cache[key]
    end

    @req_ctx = nil
    @any_noted = {}
    class << self
      attr_accessor :req_ctx
    end

    def self.article_for(word)
      return word.to_s =~ /\A[AEIOUaeiou]/ ? "an" : "a"
    end

    # [renamed text, show the "any" note after it?]
    def self.rename_text(text, subs)
      note = false
      out = utf8(text).dup
      subs.each do |from, to, _kind|
        name = (GameData::Species.get(from).name rescue nil)
        next unless name && out.include?(name)
        if to == :any
          unless @any_noted[from]
            @any_noted[from] = true
            note = true
          end
          next
        end
        new = species_name(to)
        # Not \b: names can end in "." or a symbol (Mime Jr., Nidoran)
        esc = "(?<![A-Za-z0-9])" + Regexp.escape(name) + "(?![A-Za-z0-9])"
        out = out.gsub(/\b(a|an|A|An)(\s+(?:\\[Cc]\[\d+\])?)#{esc}/) {
          art = article_for(new)
          art = art.capitalize if $1[0] == "A"
          "#{art}#{$2}#{new}"
        }
        out = out.gsub(/#{esc}/, new)
      end
      return [out, note]
    end

    def self.reset_any_notes
      @any_noted = {}
    end

    # Does this Pokémon count for what the event asks?
    def self.request_accepts?(pkmn, from, to, able)
      return false if pkmn.nil?
      proxy = KifSpeciesProxy.new(pkmn, from)
      return able.call(proxy) if to == :any
      sp = (pkmn.species rescue nil)
      ok = sp == to
      ok ||= ((data[:rares_seen] || {})[from] || []).include?(sp) if radar_rare_originals.include?(from)
      return ok && able.call(proxy)
    end

    # The event's "which Pokémon can be chosen" check, also accepting what
    # the requested Pokémon became (or anything, for :any)
    def self.wrap_able(able, ctx)
      reqs = ctx && ctx.select { |_f, _t, kind| kind == :request }
      return able unless able && reqs && !reqs.empty?
      return proc { |pk|
        able.call(pk) || reqs.any? { |from, to, _k| request_accepts?(pk, from, to, able) }
      }
    end

    #---------------------------------------------------------------------------
    # Spoiler log: every in-game trade
    #---------------------------------------------------------------------------
    def self.trade_spots
      return @trade_spots if @trade_spots
      spots = []
      infos = (load_data("Data/MapInfos.rxdata") rescue {})
      infos.keys.sort.each do |mid|
        map = (load_data(sprintf("Data/Map%03d.rxdata", mid)) rescue nil)
        next unless map && map.events
        name = (pbGetMapNameFromId(mid) rescue mid.to_s)
        map.events.keys.sort.each do |eid|
          seen = {}
          map.events[eid].pages.each do |page|
            event_script_text(page.list).scan(TRADE_RE) do |m|
              sp = m[0].to_sym
              next if seen[sp] || !GameData::Species.exists?(sp)
              seen[sp] = true
              spots << [mid, name, eid, sp]
            end
          end
        end
      end
      @trade_spots = spots
      return spots
    end

    def self.trade_lines
      return trade_spots.map { |mid, name, eid, sp|
        to = trade_result(sp, mid, eid)
        "#{name}: #{species_name(sp)} -> #{to ? species_name(to) : species_name(sp)}"
      }
    end
  end
end

# A Pokémon that answers "species" with the one an event asked for, so the
# event's own check (egg, shadow, type, …) still runs on the real Pokémon
class KifSpeciesProxy < BasicObject
  def initialize(pkmn, species)
    @kif_pkmn = pkmn
    @kif_species = species
  end

  def species; @kif_species; end
  def isSpecies?(s); s == @kif_species; end
  def is_a?(k); @kif_pkmn.is_a?(k); end
  def kind_of?(k); @kif_pkmn.kind_of?(k); end
  def nil?; false; end
  def respond_to?(*a); @kif_pkmn.respond_to?(*a); end

  def method_missing(m, *a, &b)
    @kif_pkmn.__send__(m, *a, &b)
  end
end

class Interpreter
  alias kif_rand_req_execute_command execute_command unless method_defined?(:kif_rand_req_execute_command)

  def execute_command
    return kif_rand_req_execute_command unless @list && $PokemonGlobal && $game_switches && $game_switches[SWITCH_RANDOM_WILD]
    old = KIF::Rand.req_ctx
    ctx = (KIF::Rand.request_subs(@list) rescue nil)
    KIF::Rand.reset_any_notes if ctx && @index == 0
    KIF::Rand.req_ctx = ctx
    begin
      return kif_rand_req_execute_command
    ensure
      KIF::Rand.req_ctx = old
    end
  end
end

class Object
  alias kif_rand_req_pbMessage pbMessage unless method_defined?(:kif_rand_req_pbMessage) || private_method_defined?(:kif_rand_req_pbMessage)
  alias kif_rand_req_pbConfirmMessage pbConfirmMessage unless method_defined?(:kif_rand_req_pbConfirmMessage) || private_method_defined?(:kif_rand_req_pbConfirmMessage)
  alias kif_rand_req_pbChoosePokemon pbChoosePokemon unless method_defined?(:kif_rand_req_pbChoosePokemon) || private_method_defined?(:kif_rand_req_pbChoosePokemon)
  alias kif_rand_req_pbHasSpecies pbHasSpecies? unless method_defined?(:kif_rand_req_pbHasSpecies) || private_method_defined?(:kif_rand_req_pbHasSpecies)

  def pbMessage(message, commands = nil, *args, &block)
    ctx = KIF::Rand.req_ctx
    return kif_rand_req_pbMessage(message, commands, *args, &block) unless ctx && message.is_a?(String)
    text, note = KIF::Rand.rename_text(message, ctx)
    if note && commands
      kif_rand_req_pbMessage(_INTL("(Any Pokémon will do.)"))
      note = false
    end
    ret = kif_rand_req_pbMessage(text, commands, *args, &block)
    kif_rand_req_pbMessage(_INTL("(Any Pokémon will do.)")) if note
    return ret
  end

  def pbConfirmMessage(message, *args, &block)
    ctx = KIF::Rand.req_ctx
    message = KIF::Rand.rename_text(message, ctx)[0] if ctx && message.is_a?(String)
    return kif_rand_req_pbConfirmMessage(message, *args, &block)
  end

  def pbChoosePokemon(variableNumber, nameVarNumber, ableProc = nil, *args)
    ableProc = KIF::Rand.wrap_able(ableProc, KIF::Rand.req_ctx)
    return kif_rand_req_pbChoosePokemon(variableNumber, nameVarNumber, ableProc, *args)
  end

  def pbHasSpecies?(species, *args)
    return true if kif_rand_req_pbHasSpecies(species, *args)
    ctx = KIF::Rand.req_ctx
    return false unless ctx && (species.is_a?(Symbol) || species.is_a?(String))
    req = ctx.find { |from, _t, kind| kind == :request && from == species.to_sym }
    return false unless req
    return $Trainer.party.any? { |pk| !pk.egg? && KIF::Rand.request_accepts?(pk, req[0], req[1], proc { true }) }
  end
end
