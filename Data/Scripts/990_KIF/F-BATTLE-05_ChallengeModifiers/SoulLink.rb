#===============================================================================
# F-BATTLE-05 – Soul Link (Multiplayer plan phase 3; Claude Docs/Base KIF/
# MULTIPLAYER_PLAN.md section 3 and Cody's answers). Soul Link as a Nuzlocke
# rule set comes from Aleks (sKarreku) and Pigeon (@anunsocialpigeon).
#
# Two players, each with their own save and Nuzlocke On, link their runs:
#   * Pairs by place: the first encounter in a place (Nuzlocke's place) pairs
#     with the partner's first encounter in the same place. A place one of
#     you reached first waits for the other. A missed encounter (fled,
#     fainted) loses the pair: the other's catch from there dies.
#   * Deaths are shared: when one dies, its pair dies too, wherever it is
#     (party, PC, Day Care, inside a fusion). A fusion carries the links of
#     both halves, so deaths chain through fusions.
#   * One run over = both runs over.
#   * Link mode Fused: when a pair is made, each catch becomes a fusion with
#     the partner's catch (my pick is the head of mine, theirs is the head of
#     theirs).
#   * Type rule / Party rule: warnings only, Off by default.
# Everything is inert unless Soul Link is On, Nuzlocke is On and the save is
# linked.
#
# Events (my_log / their_log in $PokemonGlobal.kif_soullink), numbered per
# player ("q"), each with a random "r" to tell copies apart:
#   c caught {p place, i id, s species, n name, l level}   m missed {p}
#   d died {i [ids], s, n, p, x 1 = died because of the link}   o run over
# Transport: an update code (KIFSL-...: zlib'd JSON + 8-byte HMAC with the
# link key), sent over the Multiplayer connection (sl_up) or pasted by hand.
# "f" = whose events, "a" = how many of the other's events the sender has.
# On connect both send sl_hello {link, seen, acked}: each then sends the
# other's missing events, and echoes back the other's own events it holds
# past "acked" - a game that loaded an older save gets its lost events back
# (deaths it no longer has are applied again).
# Linking: each side makes a random half; a link code (KIFLINK-...) carries
# name, trainer id, half, rules hash, game hash (game mode, difficulty,
# randomizer switches) and link mode. The key is SHA-256 of both halves; the
# lower half is side 0.
# Phase 4 (2026-10-24): every event carries "t" (Unix time) and "dbg" 1 when
# made with Debug on; sl_party carries id:species:level:hp:totalhp of each
# party Pokemon (the last one is kept in the save as partner_party), so the
# party screen, the pairs list and the log (SoulLinkMenu.rb) can show it.
#===============================================================================
KIF::Options.define(:ch_soullink, 0, :save)    # Off / On
KIF::Options.define(:ch_sl_mode, 0, :save)     # Linked / Fused
KIF::Options.define(:ch_sl_type, 0, :save)     # type rule Off / On
KIF::Options.define(:ch_sl_party, 0, :save)    # party rule Off / On

class PokemonGlobalMetadata
  attr_writer :kif_soullink
  def kif_soullink
    @kif_soullink ||= {}
  end
end

class Pokemon
  attr_accessor :kif_sl_id
  attr_accessor :kif_sl_fused   # made by Fused link mode: not to be unfused while linked
end

module KIF
  module SoulLink
    ALPHA     = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    ID_CHARS  = "abcdefghjkmnpqrstuvwxyz23456789"
    CHUNK     = 60       # events per update code / message
    MAX_TEXT  = 60_000   # an update code's length
    MAX_JSON  = 200_000  # an update code unpacked

    class << self
      attr_accessor :applying   # true: a death caused by the link (marked x); :log: already in my log
      attr_reader :peer         # what the connected partner said (sl_hello), this session only
    end

    # On = the rules apply: Soul Link On, Nuzlocke On, a save loaded
    def self.on?
      return $PokemonSystem && $PokemonSystem.ch_soullink == 1 && KIF::Nuzlocke.on? && $PokemonGlobal && digest? ? true : false
    end

    # Awake = the link still talks (hello, updates, codes, the screens). That is
    # while Nuzlocke is On, and for a linked save after its run ended (Keep
    # playing turns Nuzlocke Off) or with events the partner doesn't have yet.
    # The rules (pairs, deaths, fusions) are only applied while On (NSL-01).
    def self.awake?
      return false unless $PokemonSystem && $PokemonSystem.ch_soullink == 1 && $PokemonGlobal && digest?
      return true if KIF::Nuzlocke.on?
      st = $PokemonGlobal.kif_soullink
      return false unless st[:key]
      return (KIF::Nuzlocke.state[:ended] || st[:my_seq].to_i > st[:acked].to_i) ? true : false
    end

    # the run is over and Nuzlocke is Off: nothing is applied to the Pokémon any more
    def self.run_ended?; KIF::Nuzlocke.state[:ended] && !KIF::Nuzlocke.on? ? true : false; end

    # SHA-256 for codes and keys. A build without the digest library (JoiPlay's
    # isn't checked yet) keeps Soul Link off: LoadError gets past `rescue => e`.
    def self.digest?
      return @digest unless @digest.nil?
      @digest = begin
        require "digest/sha2" unless defined?(Digest::SHA256)
        defined?(Digest::SHA256) ? true : false
      rescue LoadError, StandardError
        false
      end
    end

    # A save was loaded (or the game reset): what this module kept of the last
    # one's connection (what was sent, the partner's party, notes) is forgotten
    # and a new hello goes out (NSL-10). The connection itself stays.
    def self.new_save(g)
      @save_id = g.object_id
      @sent = @party_sent = @partner_party = @party_told = @caught = @offer = nil
      @hello_sent = @asked = false
      @notes = []
    end

    def self.state
      g = $PokemonGlobal
      new_save(g) if g && g.object_id != @save_id
      return g ? g.kif_soullink : {}
    end

    def self.linked?; awake? && state[:key] ? true : false; end
    def self.partner; state[:partner_name] || "?"; end

    # one of mine that must stay with its pair: linked, alive, in a live run
    def self.protected?(p)
      return false unless p && !p.egg? && p.hp > 0 && !p.kif_nz_dead && KIF::Nuzlocke.on? && linked?
      return !ids_of(p).empty?
    end

    # the message when a protected Pokémon would leave the game other than by dying, or nil
    def self.leave_refusal(p, what)
      return nil unless protected?(p)
      return case what
             when :release then _INTL("{1} is linked to {2}'s Pokémon, so it can't be released.", p.name, partner)
             when :trade   then _INTL("{1} is linked to {2}'s Pokémon, so it can't be traded.", p.name, partner)
             else _INTL("{1} is linked to {2}'s Pokémon, so it can't be deleted.", p.name, partner)
             end
    end

    #---------------------------------------------------------------------------
    # Small pieces: hashes, codes
    #---------------------------------------------------------------------------
    def self.crypto
      raise "no SHA-256 in this copy of the game" unless digest?   # a StandardError: the callers' rescue takes it
      return KIF::Net::Crypto
    end

    def self.new_id
      bytes = crypto.random(8).bytes
      return bytes.map { |b| ID_CHARS[b % ID_CHARS.length] }.join
    end

    def self.b32(bytes)
      bits = bytes.unpack1("B*")
      bits += "0" * (-bits.length % 5)
      return bits.scan(/.{5}/).map { |b| ALPHA[b.to_i(2)] }.join
    end

    def self.unb32(text)
      return nil unless text =~ /\A[#{ALPHA}]+\z/
      bits = text.chars.map { |c| format("%05b", ALPHA.index(c)) }.join
      return [bits[0, bits.length / 8 * 8]].pack("B*")
    end

    def self.make_code(prefix, bytes)
      return prefix + "-" + b32(bytes).scan(/.{1,4}/).join("-")
    end

    # the bytes of a code with this prefix, or nil
    def self.code_bytes(prefix, text)
      t = text.to_s.upcase.gsub(/[\s\-_.]/, "")
      return nil unless t.start_with?(prefix) && t.length <= MAX_TEXT
      return unb32(t[prefix.length..-1].tr("ILO", "110"))
    end

    def self.json(v); KIF::Net::Wire.json(v); end
    def self.parse(s); KIF::Net::Parser.new(s).run; end

    def self.inflate(z)
      zi = Zlib::Inflate.new
      out = +"".b
      # in chunks: a small code that unpacks to megabytes is refused early
      zi.inflate(z) { |chunk| out << chunk; raise "too big" if out.bytesize > MAX_JSON }
      out << zi.finish.to_s
      return out.bytesize <= MAX_JSON ? out : nil
    rescue StandardError
      return nil
    ensure
      (zi.close rescue nil) if zi
    end

    # Nuzlocke options and the link mode: both runs should play by the same rules
    def self.rules_hash
      s = $PokemonSystem
      v = [s.ch_nz_fainted, s.ch_nz_whiteout, s.ch_nz_dupes, s.ch_nz_shiny, s.ch_nz_gifts, s.ch_nz_safari, s.ch_nz_kuray]
      return crypto.hex(crypto.sha256("KIF SL rules " + v.join(",")))[0, 8]
    end

    # Game mode, difficulty and randomizer: shown as Same / Different when linking
    MODE_SWITCHES = %i[SWITCH_GAME_DIFFICULTY_EASY SWITCH_GAME_DIFFICULTY_HARD SWITCH_MODERN_MODE SWITCH_EXPERT_MODE
                       SWITCH_LEGENDARY_MODE SWITCH_NO_LEVELS_MODE SWITCH_SINGLE_SPECIES_MODE SWITCH_REVERSED_MODE]

    def self.game_hash
      names = Object.constants.grep(/\ASWITCH_\w*RANDOM/).reject { |c| c.to_s =~ /AT_LEAST_ONCE|INTRO|DONT/ }.sort + MODE_SWITCHES
      v = names.map { |c| Object.const_defined?(c) && $game_switches && $game_switches[Object.const_get(c)] ? 1 : 0 }
      v << ($Trainer.game_mode rescue 0).to_i
      if defined?(KIF::Rand)   # KIF's randomizer keeps most of its settings in its own data, not in switches (seed left out)
        v += (KIF::Rand.code_enums.map { |s| KIF::Rand.get(s[0]) } + [KIF::Rand.get(:wild_bst), KIF::Rand.get(:trainer_bst)] rescue [])
      end
      return crypto.hex(crypto.sha256("KIF SL game " + v.join(",")))[0, 8]
    end

    def self.my_name; ($Trainer.name rescue nil).to_s[0, 24]; end
    def self.my_tid; ($Trainer.id rescue 0).to_i & 0xffffffff; end

    #---------------------------------------------------------------------------
    # Linking
    #---------------------------------------------------------------------------
    def self.my_half; state[:half] ||= crypto.hex(crypto.random(16)); end

    def self.link_code
      z = Zlib::Deflate.deflate(json({ "v" => 1, "n" => my_name, "t" => my_tid, "h" => my_half,
                                       "set" => rules_hash, "g" => game_hash, "m" => $PokemonSystem.ch_sl_mode }))
      return make_code("KIFLINK", z + crypto.sha256(z)[0, 4])
    end

    # the partner's link code: Hash, :typo or :invalid
    def self.read_link_code(text)
      bytes = code_bytes("KIFLINK", text) or return :invalid
      return :typo if bytes.bytesize < 6
      z = bytes[0...-4]
      return :typo unless crypto.sha256(z)[0, 4] == bytes[-4, 4]
      h = (s = inflate(z)) && parse(s)
      return :invalid unless h.is_a?(Hash) && h["v"] == 1 && h["n"].is_a?(String) && h["t"].is_a?(Integer) &&
                             h["h"].is_a?(String) && h["h"] =~ /\A[0-9a-f]{32}\z/ && h["set"].is_a?(String) &&
                             [0, 1].include?(h["m"]) && (h["g"].nil? || h["g"].is_a?(String))
      h["n"] = KIF::Net.shown_name(h["n"])
      return h
    end

    # link this save with the partner whose link code this is; false for my own code
    def self.link_with(info)
      half = my_half
      return false if info["h"] == half
      lo, hi = [half, info["h"]].sort
      key = crypto.sha256("KIF SL key " + lo + hi)
      state.replace(half: half, key: crypto.hex(key), link: crypto.hex(crypto.sha256("KIF SL id " + key))[0, 16],
                    side: half == lo ? 0 : 1, partner_name: info["n"], partner_tid: info["t"],
                    mode: half == lo ? $PokemonSystem.ch_sl_mode : info["m"],   # both play side 0's mode (NSL-20)
                    my_seq: 0, their_seq: 0, acked: 0, my_log: [], their_log: [], places: {}, pending: [])
      KIF.log("Soul Link: linked with #{info['n']}")
      @offer = nil
      @asked = false
      @sent = nil
      send_hello
      starter_check
      return true
    end

    # the partner is told by a hello with no link in it (NSL-09)
    def self.unlink
      state.clear
      @offer = nil
      @asked = false
      @sent = nil
      send_hello(true)
    end

    # The starter pairs as the place "Starter" when the link is made before the
    # first Poké Ball (NSL-03); checked once a second on the map and when linking.
    STARTER = "Starter"

    def self.starter_check
      st = state
      return if st[:starter_done] || !linked?
      return st[:starter_done] = true if KIF::Nuzlocke.started?
      party = $Trainer.party.compact
      return unless party.length == 1 && KIF::Nuzlocke.only_pokemon?
      st[:starter_done] = true
      encounter_done(STARTER, party[0])
    end

    # Over the connection: picking Link sends my code; the link is made once
    # both players picked it. :linked, :waiting
    def self.ask_link(session = KIF::Net.session)
      @asked = true
      session.post("sl_link", "code" => link_code) if session&.connected?
      return link_with(@offer) ? :linked : :waiting if @offer
      return :waiting
    end

    def self.offer; @offer; end
    def self.asked?; @asked; end

    #---------------------------------------------------------------------------
    # Events
    #---------------------------------------------------------------------------
    def self.log_event(h)
      st = state
      st[:my_seq] += 1
      ev = h.merge("q" => st[:my_seq], "r" => new_id[0, 4], "t" => Time.now.to_i)
      ev["dbg"] = 1 if $DEBUG   # shown in both players' Soul Link log
      st[:my_log] << ev
      KIF.log("Soul Link: event #{ev['k']} #{ev['p'] || ev['n']}")
      push
      return ev
    end

    def self.place_entry(place); (state[:places][place] ||= {}); end

    # after a wild battle that was this place's first encounter
    def self.encounter_done(place, caught)
      return unless linked?
      pl = place_entry(place)
      return if pl.key?(:mine)
      if caught
        caught.kif_sl_id ||= new_id
        pl[:mine] = caught.kif_sl_id
        log_event("k" => "c", "p" => place, "i" => caught.kif_sl_id, "s" => caught.species.to_s,
                  "n" => caught.name.to_s[0, 24], "l" => caught.level)
      else
        pl[:mine] = :missed
        log_event("k" => "m", "p" => place)
      end
      check_place(place)
    end

    # a pair at this place is complete (or lost): queue what follows
    def self.check_place(place)
      pl = state[:places][place] or return
      mine, theirs = pl[:mine], pl[:theirs]
      return unless mine.is_a?(String) && theirs
      if theirs == :missed
        queue("k" => "kill", "i" => mine, "why" => "missed", "p" => place)
      elsif (gone = state[:their_log].find { |e| e["k"] == "d" && Array(e["i"]).include?(theirs[:i]) })
        # their Pokémon died before mine was caught: mine dies on arrival (NSL-08)
        queue("k" => "kill", "i" => mine, "why" => "died", "who" => gone["n"], "s" => gone["s"], "p" => gone["p"])
      elsif link_mode == 1 && !pl[:fused]
        pl[:fused] = true
        queue("k" => "fuse", "i" => mine, "s" => theirs[:s], "n" => theirs[:n], "p" => place)
      end
    end

    # Linked or Fused: the agreed mode of this link (older saves: my own setting)
    def self.link_mode; state[:mode] || $PokemonSystem.ch_sl_mode; end

    def self.queue(action)
      state[:pending] << action unless run_ended?   # a finished run takes no more deaths
    end

    # A place Nuzlocke used up without a wild battle (a gift, a Safari catch): the
    # Pokémon pairs there like a wild catch (NSL-02); without the Pokémon nothing
    # is logged (a miss would kill the partner's catch).
    def self.place_used(place, pkmn)
      encounter_done(place, pkmn) if pkmn.is_a?(Pokemon) && linked? && KIF::Nuzlocke.on?
    end

    # A co-op wild battle (I am the guest) ended with nobody catching anything, and the host is my
    # Soul Link partner: its first encounter here is lost for the host, so mine is lost too, else
    # my next catch here would die on arrival (NSL-16). decision: the host's result (4 = caught).
    # Not when the host's side of this place was settled already.
    def self.shared_miss?(place, decision)
      return false unless [1, 2, 3, 5].include?(decision) && linked? && KIF::Nuzlocke.on? && connected?
      pl = state[:places][place]
      return !(pl && pl[:theirs])
    end

    # What a block added to the party or the boxes (a gift call doesn't return it): [result, Pokémon or nil]
    def self.watching
      before = {}
      (each_mon { |p, _| before[p.object_id] = true }) rescue nil   # (the gift is given whatever this finds)
      ret = yield
      got = nil
      (each_mon { |p, _| got ||= p unless before[p.object_id] }) rescue nil
      return [ret, got]
    end

    def self.ids_of(p)
      return [] unless p
      ids = [p.kif_sl_id]
      ids << p.original_head.kif_sl_id if p.respond_to?(:original_head) && p.original_head.respond_to?(:kif_sl_id)
      ids << p.original_body.kif_sl_id if p.respond_to?(:original_body) && p.original_body.respond_to?(:kif_sl_id)
      return ids.compact.uniq
    end

    # Every Pokémon the player has: [pokemon, where] (:party, [box, slot], :daycare)
    def self.each_mon
      $Trainer.party.each { |p| yield p, :party if p }
      $PokemonStorage.maxBoxes.times do |b|
        next if $PokemonStorage[b].is_a?(StorageTransferBox)   # shared by every save: writing to it saves the game (as Nuzlocke)
        $PokemonStorage.maxPokemon(b).times { |i| p = $PokemonStorage[b, i]; yield p, [b, i] if p }
      end
      (($PokemonGlobal.daycare rescue nil) || []).each { |slot| yield slot[0], :daycare if slot.is_a?(Array) && slot[0].is_a?(Pokemon) }
    end

    def self.find(id)
      each_mon { |p, where| return [p, where] if ids_of(p).include?(id) }
      return nil
    end

    # my died event (Nuzlocke.bury)
    def self.died(p)
      return unless linked?
      ids = ids_of(p)
      return if ids.empty?
      ev = { "k" => "d", "i" => ids, "s" => p.species.to_s, "n" => p.name.to_s[0, 24],
             "p" => KIF::Nuzlocke.place_name($game_map.map_id) }
      return if applying == :log
      ev["x"] = 1 if applying
      log_event(ev)
    end

    def self.run_over
      return unless linked? && !applying
      log_event("k" => "o")
    end

    # Lock save: the save can't be opened again, so a partner who isn't connected hears of it from the load screen
    def self.offline_note
      return unless linked? && !applying && !connected?
      pbMessage(_INTL("{1} isn't connected. To end {1}'s run too, pick this save on the load screen and choose Share Soul Link code.", partner))
    end

    # The linked state inside a save's data when its Soul Link is On (the load screen), else nil
    def self.saved_state(save_data)
      return nil unless save_data.is_a?(Hash) && digest?
      set = save_data[:kif_save_settings]
      g = save_data[:global_metadata]
      return nil unless set.is_a?(Hash) && set[:ch_soullink] == 1 && g.respond_to?(:kif_soullink)
      st = g.kif_soullink
      return st.is_a?(Hash) && st[:key] ? st : nil
    end

    # events of a saved (locked) run the partner hasn't confirmed
    def self.saved_unsent(save_data)
      st = saved_state(save_data) or return 0
      return st[:my_seq].to_i - st[:acked].to_i
    end

    #---------------------------------------------------------------------------
    # Update codes
    #---------------------------------------------------------------------------
    def self.unsent; linked? ? state[:my_seq] - state[:acked] : 0; end

    def self.update_code(events, side = nil, st = state)
      side ||= st[:side]
      z = Zlib::Deflate.deflate(json({ "v" => 1, "l" => st[:link], "f" => side, "a" => st[:their_seq], "e" => events }))
      mac = crypto.hmac(crypto.unhex(st[:key]), "KIFSL" + z)[0, 8]
      return make_code("KIFSL", z + mac)
    end

    # my events the partner hasn't confirmed (the paste code holds them all)
    def self.my_update_code
      return update_code(state[:my_log].select { |e| e["q"] > state[:acked] })
    end

    PASTE_MAX = 1800   # a pasted code must fit a Discord message (2000)

    # the same in codes of at most PASTE_MAX characters, to be pasted in order (NSL-29)
    def self.my_update_codes(st = state)
      evs = st[:my_log].select { |e| e["q"] > st[:acked] }
      out = []
      until evs.empty?
        n = [evs.length, CHUNK].min
        n -= [n / 4, 1].max while n > 1 && update_code(evs.first(n), nil, st).length > PASTE_MAX
        out << update_code(evs.shift(n), nil, st)
      end
      return out.empty? ? [update_code([], nil, st)] : out   # nothing new: a code that still says what I have
    end

    EV_KINDS = %w[c m d o]
    SPECIES_RE = /\A(?!.*_x_)[A-Za-z0-9_]{1,48}\z/   # :NIDORANfE has a small letter; "_x_" ids make PIF's fusion lookup raise

    def self.valid_event?(e)
      return false unless e.is_a?(Hash) && e["q"].is_a?(Integer) && e["q"] > 0 && (EV_KINDS + ["x"]).include?(e["k"]) &&
                          e["r"].is_a?(String) && e["r"].length <= 8
      str = proc { |k, n| e[k].nil? || (e[k].is_a?(String) && e[k].length <= n && e[k] !~ /[\x00-\x1f]/) }
      return false unless str.call("p", 48) && str.call("n", 24) && str.call("s", 48)
      return false if e["s"] && e["s"] !~ SPECIES_RE
      ids = e["i"].is_a?(Array) ? e["i"] : [e["i"]].compact
      return false unless ids.length <= 6 && ids.all? { |i| i.is_a?(String) && i =~ /\A[a-z0-9]{1,8}\z/ }
      return false if e["k"] == "d" && !(e["i"].is_a?(Array) && !e["i"].empty?)   # their_event and own_event walk the ids (NSL-30)
      return false if e["k"] == "c" && !e["i"].is_a?(String)
      return false if e["l"] && !(e["l"].is_a?(Integer) && e["l"].between?(1, 1000))
      return false if e["t"] && !(e["t"].is_a?(Integer) && e["t"].between?(0, 2**40))
      return false unless e["dbg"].nil? || e["dbg"] == 1
      return e["k"] == "x" || e["k"] == "o" || e["k"] == "d" || e["p"].is_a?(String)
    end

    # An event kind this build doesn't know (a newer build made it): kept as an empty
    # "x" with its number, so the rest of the code still applies (NSL-21)
    def self.future_event(e)
      return e unless e.is_a?(Hash) && e["k"].is_a?(String) && !EV_KINDS.include?(e["k"]) && e["k"] != "x"
      return { "q" => e["q"], "r" => e["r"], "k" => "x", "t" => e["t"] }
    end

    # Hash {f:, a:, e:} or a Symbol why not: :invalid, :key (not this link / tampered)
    def self.read_update_code(text)
      return :off unless linked?
      bytes = code_bytes("KIFSL", text) or return :invalid
      return :invalid if bytes.bytesize < 12
      z = bytes[0...-8]
      return :key unless crypto.same?(crypto.hmac(crypto.unhex(state[:key]), "KIFSL" + z)[0, 8], bytes[-8, 8])
      h = (s = inflate(z)) && parse(s)
      h["e"] = h["e"].map { |e| future_event(e) } if h.is_a?(Hash) && h["e"].is_a?(Array)
      return :invalid unless h.is_a?(Hash) && h["v"] == 1 && h["l"] == state[:link] && [0, 1].include?(h["f"]) &&
                             h["a"].is_a?(Integer) && h["e"].is_a?(Array) && h["e"].all? { |e| valid_event?(e) }
      return h
    end

    # apply a read code: [lines for the summary, events applied]
    def self.receive_update(h)
      st = state
      st[:acked] = h["a"].clamp(st[:acked], st[:my_seq]) if h["f"] != st[:side]
      events = h["e"].sort_by { |e| e["q"] }
      return h["f"] == st[:side] ? adopt_own(events) : apply_theirs(events)
    end

    def self.apply_theirs(events)
      st = state
      lines = []
      n = 0
      events.each do |e|
        next if e["q"] <= st[:their_seq]
        break if e["q"] != st[:their_seq] + 1   # a gap: wait for the rest
        st[:their_seq] = e["q"]
        st[:their_log] << e
        n += 1
        lines << their_event(e)
      end
      return [lines.compact, n]
    end

    # one of the partner's events: what it means here (summary line [left, right])
    def self.their_event(e)
      who = partner
      case e["k"]
      when "c"
        pl = place_entry(e["p"])
        pl[:theirs] = { i: e["i"], s: e["s"], n: e["n"], l: e["l"] }
        check_place(e["p"])
        mine = pl[:mine]
        right = mine.is_a?(String) ? _INTL("paired") : mine == :missed ? _INTL("no pair") : _INTL("waiting for you")
        return [_INTL("Caught {1}, {2}", species_name(e["s"]), e["p"]), right]
      when "m"
        pl = place_entry(e["p"])
        pl[:theirs] = :missed
        check_place(e["p"])
        mine = pl[:mine]
        return [_INTL("No catch, {1}", e["p"]), mine.is_a?(String) ? _INTL("{1} dies", mon_name(mine)) : ""]
      when "d"
        dead = []
        state[:places].each do |place, pl|
          next unless pl[:theirs].is_a?(Hash) && e["i"].include?(pl[:theirs][:i]) && pl[:mine].is_a?(String)
          dead << mon_name(pl[:mine])
          queue("k" => "kill", "i" => pl[:mine], "why" => "died", "who" => e["n"], "s" => e["s"], "p" => e["p"])
        end
        return [_INTL("{1} died, {2}", e["n"], e["p"]), dead.empty? || run_ended? ? "" : _INTL("{1} dies", dead.join(", "))]
      when "o"
        queue("k" => "over")
        return [_INTL("{1}'s run is over", who), run_ended? ? "" : _INTL("yours ends")]
      end
    end

    def self.species_name(s)
      d = (GameData::Species.try_get(s.to_s.to_sym) rescue nil) if s   # the partner's id: a bad one already in a save shows as text
      return d ? d.name : s.to_s
    end

    def self.mon_name(id)
      p, = find(id)
      return p ? p.name : "?"
    end

    # The partner sent back my own events: those this save doesn't have (an
    # older save was loaded) are taken as they were; mine made since then
    # are numbered after them and sent again
    def self.adopt_own(events)
      st = state
      lines = []
      n = 0
      moved = []
      events.each do |e|
        local = st[:my_log].find { |x| x["q"] == e["q"] }
        next if local && local["r"] == e["r"]
        moved += st[:my_log].select { |x| x["q"] >= e["q"] }
        st[:my_log].reject! { |x| x["q"] >= e["q"] }
        st[:my_log] << e
        n += 1
        lines << own_event(e)
      end
      return [lines.compact, 0] if n == 0
      st[:my_seq] = st[:my_log].map { |x| x["q"] }.max || 0
      st[:acked] = [st[:acked], events.map { |e| e["q"] }.max].max
      moved.uniq.sort_by { |x| x["q"] }.each do |x|
        next if st[:my_log].any? { |y| y["r"] == x["r"] }
        st[:my_seq] += 1
        st[:my_log] << x.merge("q" => st[:my_seq])
      end
      st[:my_log].sort_by! { |x| x["q"] }
      KIF.log("Soul Link: #{n} of my own events came back from #{partner}")
      push
      return [lines.compact, n]
    end

    def self.own_event(e)
      case e["k"]
      when "c", "m"
        nz = (KIF::Nuzlocke.state[:places] ||= {})
        nz[e["p"]] ||= [e["s"] ? e["s"].to_sym : :NONE]
        place_entry(e["p"])[:mine] = e["k"] == "c" ? e["i"] : :missed
        check_place(e["p"])
        return [e["k"] == "c" ? _INTL("You caught {1}, {2}", species_name(e["s"]), e["p"]) : _INTL("You had no catch, {1}", e["p"]), ""]
      when "d"
        e["i"].each { |id| queue("k" => "kill", "i" => id, "why" => "log", "p" => e["p"]) }
        return [_INTL("{1} died, {2}", e["n"], e["p"]), _INTL("dies again")]
      when "o"
        queue("k" => "over", "own" => true)
        return [_INTL("Your run was over"), ""]
      end
    end

    #---------------------------------------------------------------------------
    # What the events lead to, at a quiet moment on the map (or in the Soul
    # Link screen): deaths, fusions, the run's end
    #---------------------------------------------------------------------------
    def self.pending?; linked? && KIF::Nuzlocke.on? && (!state[:pending].empty? || state[:wipe]) ? true : false; end

    # warp: on the map a wiped party blacks out as after a lost battle; in a screen it waits for the map (NSL-23)
    def self.apply_pending(show = true, warp = false)
      return unless pending?
      st = state
      over = nil
      until st[:pending].empty?
        a = st[:pending].shift
        case a["k"]
        when "kill"
          p, where = find(a["i"])
          next unless p && !p.kif_nz_dead
          msg = case a["why"]
                when "missed" then _INTL("{1} had no catch on {2}, so {3} has no pair and dies.", partner, a["p"], p.name)
                when "log"    then _INTL("This run's log says {1} died on {2}.", p.name, a["p"])
                else _INTL("{1}'s {2} died on {3}.\n{4} was linked to it and dies too.", partner, a["who"], a["p"], p.name)
                end
          if show && a["why"] != "log"
            # SL2: both Pokémon greyed on a card above the message
            card = a["why"] == "missed" ? [_INTL("{1} had no catch", partner), _INTL("on {1}", a["p"])] :
                                          [_INTL("{1}'s {2}", partner, a["who"]), _INTL("died on {1}", a["p"])]
            Menu.death_card(card, a["s"], p) { pbMessage(msg) }
          elsif show
            pbMessage(msg)
          end
          reason = a["why"] == "missed" ? _INTL("no pair") : a["why"] == "died" ? _INTL("linked to {1}'s {2}", partner, a["who"]) : nil
          kill(p, where, a["why"] == "log" ? :log : true, reason)
        when "fuse"
          fuse(a) && show && pbMessage(_INTL("Soul Link: {1} fused with {2}'s {3}.", a["was"], partner, species_name(a["s"])))
        when "over"
          over = a
        end
      end
      KIF::Nuzlocke.move_dead_out if $Trainer.party.any? { |p| p && p.kif_nz_dead } && $Trainer.party.any? { |p| KIF::Nuzlocke.able?(p) }
      st.delete(:wipe)
      if over
        pbMessage(_INTL("{1}'s run is over, so yours ends too.", partner)) if show && !over["own"]
        end_together
      elsif !$Trainer.party.any? { |p| KIF::Nuzlocke.able?(p) } && $Trainer.party.any? { |p| p && p.kif_nz_dead }
        warp ? pbStartOver : st[:wipe] = true
      end
    end

    def self.end_together
      self.applying = true
      KIF::Nuzlocke.end_run($PokemonSystem.ch_nz_whiteout == KIF::Nuzlocke::WHITEOUT_LOCK)
    ensure
      self.applying = false
    end

    def self.kill(p, where, how = true, why = nil)
      self.applying = how
      p.hp = 0
      KIF::Nuzlocke.bury(p, why)
      return unless where.is_a?(Array)   # party: Nuzlocke moves them; Day Care: stays, dead
      fate = $PokemonSystem.ch_nz_fainted
      return if fate > KIF::Nuzlocke::FAINTED_RELEASED
      if fate == KIF::Nuzlocke::FAINTED_GRAVEYARD
        (KIF::Nuzlocke.state[:graveyard] ||= []) << { :name => p.name, :species => p.species, :level => p.level, :why => why,
                                                      :place => KIF::Nuzlocke.place_name($game_map.map_id), :pokemon => p }
      end
      $PokemonStorage[where[0], where[1]] = nil
    ensure
      self.applying = false
    end

    # Link mode Fused: my catch (head) and the partner's catch (body) become one
    def self.fuse(a)
      p, = find(a["i"])
      body = GameData::Species.try_get(a["s"].to_s.to_sym)
      return false unless p && body && !p.kif_nz_dead && p.species_data.id_number <= NB_POKEMON &&
                          body.id_number <= NB_POKEMON && !p.egg?
      a["was"] = p.name
      head = p.clone
      half = Pokemon.new(body.id, p.level)
      p.original_head = head
      p.original_body = half
      p.species = getFusionSpecies(body.id, p.species).id
      p.kif_sl_fused = true
      p.calc_stats
      return true
    rescue StandardError => e
      KIF.log("Soul Link: fusing failed (#{e.class}: #{e.message})")
      return false
    end

    #---------------------------------------------------------------------------
    # Over the Multiplayer connection
    #---------------------------------------------------------------------------
    # The line to my partner: the connection their hello came on (a lobby with
    # more players has more lines; every sl_* message goes to this one), else the session
    def self.session
      s = @peer_line if @peer_line.respond_to?(:connected?) && @peer_line.connected?
      s ||= KIF::Net.session if defined?(KIF::Net) && KIF::Net.respond_to?(:session)
      return s&.connected? ? s : nil
    end

    # a message on this line (nil: the only one) is from my partner's line, or no partner line is known
    def self.partner_line?(line)
      return line.nil? || @peer_line.nil? || line.equal?(@peer_line)
    end

    def self.connected?
      return false unless (s = session) && @peer && linked?
      return @peer["link"] == state[:link]
    end

    # (a new line while my partner's is still up changes nothing of the partner's state)
    def self.on_connect(line = nil)
      keep = line && @peer_line && !line.equal?(@peer_line) && @peer_line.respond_to?(:connected?) && @peer_line.connected?
      on_disconnect unless keep
      send_hello
    end

    # a line that isn't my partner's closing changes nothing
    def self.on_disconnect(line = nil)
      return if line && @peer_line && !line.equal?(@peer_line)
      @peer = nil
      @peer_line = nil
      @peer_info = nil   # (a new partner must not be linked with the last one's code)
      @offer = nil
      @asked = false
      @party_sent = nil
      @hello_sent = false
    end

    # force: also when the link is gone (Unlink: the partner learns from the hello)
    def self.send_hello(force = false)
      s = session or return
      return unless force || awake?
      st = state
      s.post("sl_hello", "link" => st[:link] || "", "seen" => st[:their_seq] || 0, "acked" => st[:acked] || 0,
                         "code" => link_code)
      s.post("sl_party", "ids" => @party_sent = party_ids) if st[:key]
      @hello_sent = true
    end

    # Soul Link turned on while connected, or a save loaded: say hello then (checked every second on the map)
    def self.hello_late
      send_hello if !@hello_sent && session && awake?
    end

    PARTY_MAX = 900   # characters of an sl_party row list (Net.rb TYPES)

    # id:species:level:hp:totalhp:name for each link in the party (a fusion has two)
    def self.party_ids
      rows = $Trainer.party.compact.flat_map { |p| ids_of(p).map { |id| [id, p.species, p.level, p.hp, p.totalhp, row_name(p)].join(":") } }
      out = +""
      rows.each { |r| break if out.length + r.length + 1 > PARTY_MAX; out << "," unless out.empty?; out << r }
      return out
    end

    # the current nickname, safe in a row (no separators or codes)
    def self.row_name(p); p.name.to_s.gsub(/[\<>:,\x00-\x1f]/, "")[0, 12]; end

    # the party again when it changed (checked every second on the map)
    def self.send_party
      return unless connected?
      ids = party_ids
      return if ids == @party_sent
      session.post("sl_party", "ids" => @party_sent = ids)
    end

    # the partner's last party: {id => [species, level, hp, totalhp, name or nil]}
    def self.read_party(text)
      snap = {}
      text.split(",").each do |row|
        id, s, *n = row.split(":")
        name = n.length == 4 ? n.pop : nil   # a row from a build without names has three numbers
        next unless id.to_s =~ /\A[a-z0-9]{1,8}\z/ && s.to_s =~ SPECIES_RE && n.length == 3 && n.all? { |x| x =~ /\A\d{1,5}\z/ }
        snap[id] = [s, *n.map(&:to_i), name.to_s.empty? ? nil : KIF::Net.shown_name(name)[0, 12]]
      end
      return snap
    end

    # new events and the party to the partner, when connected
    def self.push
      return unless connected?
      st = state
      list = st[:my_log].select { |e| e["q"] > (@sent || st[:acked]) }
      list.each_slice(CHUNK) { |part| session.post("sl_up", "code" => update_code(part)) }
      @sent = st[:my_seq]
    end

    # a message from the partner's game (KIF::Net.update); line: the connection it came on
    def self.receive(type, msg, line = nil)
      if type == "sl_hello"   # kept while Off too: linking needs it once Soul Link is turned on
        # a third player's hello never replaces my partner's (a lobby with more players)
        return if line && @peer_line && !line.equal?(@peer_line) && linked? && msg["link"] != state[:link]
        @peer = msg
        @peer_line = line
        @peer_info = read_link_code(msg["code"])
      end
      return unless awake?
      st = state
      case type
      when "sl_hello"
        if st[:key] && msg["link"] != st[:link]
          note_left if @peer_info.is_a?(Hash) && @peer_info["t"] == st[:partner_tid]   # their save isn't linked with this one
          return
        end
        return unless st[:key]
        st.delete(:left)
        st[:acked] = [msg["seen"], st[:my_seq]].min
        s = session
        mine = st[:my_log].select { |e| e["q"] > msg["seen"] }
        mine.each_slice(CHUNK) { |part| s.post("sl_up", "code" => update_code(part)) }
        @sent = st[:my_seq]
        echo = st[:their_log].select { |e| e["q"] > msg["acked"] }
        echo.each_slice(CHUNK) { |part| s.post("sl_up", "code" => update_code(part, 1 - st[:side])) }
        s.post("sl_party", "ids" => @party_sent = party_ids)
      when "sl_link"
        return unless partner_line?(line) || !st[:key]
        info = read_link_code(msg["code"])
        return unless info.is_a?(Hash)
        @offer = info
        @peer_info = info
        link_with(info) if @asked && !st[:key]
      when "sl_up"
        return unless partner_line?(line)
        h = read_update_code(msg["code"])
        return KIF.log("Soul Link: an update from #{partner} didn't fit (#{h})") unless h.is_a?(Hash)
        before = st[:their_seq]
        lines, n = receive_update(h)
        @notes = (@notes || []) + lines
        # tell them what arrived (an empty update carries "a")
        session&.post("sl_up", "code" => update_code([])) if n > 0 && h["f"] != st[:side]
        news(h["e"], before, st[:their_seq]) if n > 0 && h["f"] != st[:side]
      when "sl_party"
        return unless connected? && partner_line?(line)   # only my partner's party
        snap = read_party(msg["ids"])
        @partner_party = snap.keys
        st[:partner_party] = snap
      end
    end

    # the partner's game isn't linked with this one (they unlinked, or loaded another save)
    def self.note_left
      st = state
      return if st[:left]
      st[:left] = true
      KIF.log("Soul Link: #{partner}'s game isn't linked with this save")
      KIF::Net.notes << _INTL("{1} isn't linked with you any more. Pick Unlink in Soul Link to start over.", partner)
    end

    # one line on the map for the catches and misses the partner's game just sent (deaths show as they apply)
    def self.news(events, from, upto)
      evs = events.select { |e| e["q"] > from && e["q"] <= upto && %w[c m].include?(e["k"]) }
      return if evs.empty?
      e = evs[0]
      KIF::Net.notes << (evs.length > 1 ? _INTL("{1} sent {2} Soul Link updates. See Soul Link, Soul Link log.", partner, evs.length) :
                         e["k"] == "c" ? _INTL("{1} caught {2} on {3}.", partner, species_name(e["s"]), e["p"]) :
                                         _INTL("{1} had no catch on {2}.", partner, e["p"]))
    end

    def self.peer_info; @peer_info; end
    def self.partner_party; @partner_party; end
    def self.take_notes; n = @notes || []; @notes = []; n; end

    #---------------------------------------------------------------------------
    # What the screens show (SoulLinkMenu.rb): pairs and how they are
    #---------------------------------------------------------------------------
    def self.dead_ids(log); log.select { |e| e["k"] == "d" }.flat_map { |e| Array(e["i"]) }; end

    # One place: {place:, mine: id / :missed / nil, theirs: {i s n l} / :missed / nil,
    # state:, snap: [species, level, hp, totalhp] of the partner's from their
    # last party, or nil}. States: :alive :hurt (half HP or less) :dead
    # :missed (no pair) :waiting (for the partner) :open (for me)
    def self.pair(place, pl, mine_dead, their_dead)
      m, t = pl[:mine], pl[:theirs]
      snap = t.is_a?(Hash) ? (state[:partner_party] || {})[t[:i]] : nil
      st = if m == :missed || t == :missed then :missed
           elsif m.is_a?(String) && mine_dead.include?(m) then :dead   # before the partner has caught: dead, not waiting
           elsif m.nil? then :open
           elsif t.nil? then :waiting
           elsif mine_dead.include?(m) || their_dead.include?(t[:i]) || (snap && snap[2] <= 0) then :dead
           elsif snap && snap[2] * 2 <= snap[3] then :hurt
           else :alive
           end
      return { place: place, mine: m, theirs: t, state: st, snap: snap }
    end

    def self.pairs
      return [] unless linked?
      md = dead_ids(state[:my_log])
      td = dead_ids(state[:their_log])
      return state[:places].map { |place, pl| pair(place, pl, md, td) }
    end

    # the partner's Pokémon: its nickname now (from their last party), else the one it was caught with
    def self.their_name(r)
      t = r[:theirs]
      return "?" unless t.is_a?(Hash)
      return r[:snap][4] if r[:snap] && r[:snap][4]
      return r[:snap] && t[:n] == species_name(t[:s]) ? species_name(r[:snap][0]) : t[:n]
    end

    WORST = %i[alive waiting hurt missed dead]

    # the pair of one of my Pokémon (a fusion has two: the worse one), or nil
    def self.pair_of(p)
      return nil unless linked? && p
      ids = ids_of(p)
      return nil if ids.empty?
      return pairs.select { |r| ids.include?(r[:mine]) }.max_by { |r| WORST.index(r[:state]) || 0 }
    end

    #---------------------------------------------------------------------------
    # Extra rules (warnings): lines for the Soul Link screen
    #---------------------------------------------------------------------------
    def self.warnings
      out = []
      return out unless linked?
      party = $Trainer.party.compact.reject { |p| p.egg? || p.kif_nz_dead }
      return type_lines(party) + party_rule_lines(party)
    end

    def self.type_lines(party = nil)
      out = []
      return out unless $PokemonSystem.ch_sl_type == 1 && linked?
      party ||= $Trainer.party.compact.reject { |p| p.egg? || p.kif_nz_dead }
      seen = {}
      party.each do |p|
        next if ids_of(p).empty?
        t = p.type1
        out << _INTL("Type rule: {1} and {2} are both {3} type.", seen[t].name, p.name, GameData::Type.get(t).name) if seen[t]
        seen[t] ||= p
      end
      return out
    end

    # another linked Pokémon in the party with this one's primary type (the party screen's box says so), or nil
    def self.type_clash(p)
      return nil unless $PokemonSystem.ch_sl_type == 1 && linked? && p && !p.egg? && !p.kif_nz_dead && !ids_of(p).empty?
      return $Trainer.party.compact.find { |o| !o.equal?(p) && !o.egg? && !o.kif_nz_dead && !ids_of(o).empty? && o.type1 == p.type1 }
    end

    # Lines for the Soul Link screen when the partner's game plays by other settings or another build (NSL-20, NSL-21)
    def self.differences
      out = []
      info = @peer_info
      return out unless connected? && info.is_a?(Hash)
      out << _INTL("Settings differ now from {1}'s.", partner) if info["set"] != rules_hash || (info["g"] && info["g"] != game_hash)
      s = session
      out << _INTL("{1} has KIF {2}, you have KIF {3}.", partner, s.partner_ver, KIF::Net.version) if s.respond_to?(:partner_ver) && s.partner_ver != KIF::Net.version
      return out
    end

    def self.party_rule_lines(party = nil)
      out = []
      return out unless $PokemonSystem.ch_sl_party == 1 && @partner_party && connected? && linked?
      party ||= $Trainer.party.compact.reject { |p| p.egg? || p.kif_nz_dead }
      party.each do |p|
        theirs = state[:places].values.find { |pl| ids_of(p).include?(pl[:mine]) && pl[:theirs].is_a?(Hash) }
        next unless theirs
        out << _INTL("Party rule: {1}'s pair isn't in {2}'s party.", p.name, partner) unless @partner_party.include?(theirs[:theirs][:i])
      end
      return out
    end

    # the party and type rules on the map (checked each second): a line when a
    # clash or a missing pair is new (a PC deposit, a party change on either
    # side), not every step
    def self.party_rule_check
      lines = type_lines + party_rule_lines
      fresh = lines - (@party_told || [])
      @party_told = lines
      return if fresh.empty?
      t = fresh.first
      t += " " + _INTL("({1} more on Pause > Soul Link.)", fresh.length - 1) if fresh.length > 1
      KIF::Net.notes << t
    end
  end
end

#-------------------------------------------------------------------------------
# Options (Challenges > Soul Link)
#-------------------------------------------------------------------------------
KIF::Options.add(:challenges, :save) {
  next nil unless KIF::SoulLink.digest?
  EnumOption.new(_INTL("Soul Link"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_soullink },
                 proc { |value| $PokemonSystem.ch_soullink = value },
                 [_INTL("No Soul Link."),
                  _INTL("Link this Nuzlocke run with a friend's: Pokémon caught in the same place are paired, and when one dies, so does its pair. Soul Link in the pause menu.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Link mode"), [_INTL("Linked"), _INTL("Fused")],
                 proc { $PokemonSystem.ch_sl_mode },
                 proc { |value| $PokemonSystem.ch_sl_mode = value },
                 [_INTL("Your catch and your partner's catch from the same place are linked."),
                  _INTL("Your catch fuses with your partner's catch from the same place: yours is the head, theirs the body. The fusion can't be unfused.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Soul Link type rule"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_sl_type },
                 proc { |value| $PokemonSystem.ch_sl_type = value },
                 [_INTL("No type rule."),
                  _INTL("Warns when two linked Pokémon in your party share a primary type.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Soul Link party rule"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_sl_party },
                 proc { |value| $PokemonSystem.ch_sl_party = value },
                 [_INTL("No party rule."),
                  _INTL("Warns when a linked Pokémon is in your party but its pair isn't in your partner's (while connected).")])
}

KIF::PauseMenu.add(:kif_soullink, "Soul Link", icon: "menuIcons/PLAYER", order: 55,
  condition: proc { KIF::SoulLink.awake? },
  handler: proc { |scene|
    scene.pbHideMenu if scene.respond_to?(:pbHideMenu)   # the pause menu draws over the screens (z 99999)
    KIF::SoulLink::Menu.open
    :stay
  })

#-------------------------------------------------------------------------------
# Hooks
#-------------------------------------------------------------------------------
# the Pokémon caught in this battle (the objects that are stored)
class PokeBattle_Battle
  alias kif_sl_pbRecordAndStoreCaughtPokemon pbRecordAndStoreCaughtPokemon unless method_defined?(:kif_sl_pbRecordAndStoreCaughtPokemon)

  def pbRecordAndStoreCaughtPokemon(*args)
    KIF::SoulLink.instance_variable_set(:@caught, (@caughtPokemon || []).dup) if KIF::SoulLink.linked?
    return kif_sl_pbRecordAndStoreCaughtPokemon(*args)
  end
end

alias kif_sl_pbAfterBattle pbAfterBattle unless defined?(kif_sl_pbAfterBattle)

def pbAfterBattle(decision, canLose)
  pend = KIF::SoulLink.linked? ? KIF::Nuzlocke.pending : nil
  ret = kif_sl_pbAfterBattle(decision, canLose)
  if pend
    begin
      caught = (KIF::SoulLink.instance_variable_get(:@caught) || []).find { |c| pend[1].any? { |f| f.equal?(c) } } ||
               (KIF::SoulLink.instance_variable_get(:@caught) || []).first
      KIF::SoulLink.encounter_done(pend[0], caught)
    rescue => e
      KIF.log("Soul Link: after-battle step failed (#{e.class}: #{e.message})")
    end
  end
  KIF::SoulLink.instance_variable_set(:@caught, nil)
  return ret
end

module KIF
  module Nuzlocke
    class << self
      alias kif_sl_bury bury unless method_defined?(:kif_sl_bury)
      alias kif_sl_end_run end_run unless method_defined?(:kif_sl_end_run)

      def bury(p, why = nil)
        ret = kif_sl_bury(p, why)
        begin
          KIF::SoulLink.died(p)
        rescue => e
          KIF.log("Soul Link: death not logged (#{e.class}: #{e.message})")
        end
        return ret
      end

      def end_run(*args)
        begin
          KIF::SoulLink.run_over
          KIF::SoulLink.offline_note if args[0]   # a locked save can't be opened again
        rescue => e
          KIF.log("Soul Link: run end not logged (#{e.class}: #{e.message})")
        end
        return kif_sl_end_run(*args)
      end
    end
  end
end

module KIF
  module SoulLink
    # every map frame (a test calls it with the frame it wants)
    def self.map_tick(frame = Graphics.frame_count)
      if frame % 60 == 0
        begin
          hello_late
          starter_check
        rescue => e
          KIF.log("Soul Link: hello not sent (#{e.class}: #{e.message})")
        end
      end
      if frame % 60 == 0 && linked?
        begin
          send_party
          party_rule_check
        rescue => e
          KIF.log("Soul Link: party not sent (#{e.class}: #{e.message})")
        end
      end
      if pending? && KIF::Net.quiet?
        begin
          apply_pending(true, true)
        rescue => e
          KIF.log("Soul Link: applying failed (#{e.class}: #{e.message})")
        end
      end
    end
  end
end

Events.onMapUpdate += proc { |_sender, _e| KIF::SoulLink.map_tick }
