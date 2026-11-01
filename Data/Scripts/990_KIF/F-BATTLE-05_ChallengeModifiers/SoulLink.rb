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
end

module KIF
  module SoulLink
    ALPHA     = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    ID_CHARS  = "abcdefghjkmnpqrstuvwxyz23456789"
    CHUNK     = 60       # events per update code / message
    MAX_TEXT  = 60_000   # an update code's length
    MAX_JSON  = 200_000  # an update code unpacked (one the player pastes)
    LINK_JSON = 4_000    # a link code unpacked (a real one: about 250)
    NET_JSON  = 40_000   # an update code from the connection unpacked (60 events: about 20,000)
    MAX_EVENTS = 600     # events in one update code
    MAX_LOG    = 600     # the partner's events kept in a save
    MAX_PLACES = 400     # places kept in a save

    class << self
      attr_accessor :applying   # true: a death caused by the link (marked x); :log: already in my log
      attr_reader :peer         # what the connected partner said (sl_hello), this session only
    end

    def self.on?
      return $PokemonSystem && $PokemonSystem.ch_soullink == 1 && KIF::Nuzlocke.on? && $PokemonGlobal && digest? ? true : false
    end

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

    def self.state; $PokemonGlobal ? $PokemonGlobal.kif_soullink : {}; end
    def self.linked?; on? && state[:key] ? true : false; end
    def self.partner; state[:partner_name] || "?"; end

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
    # (values and keys: reading them is what costs time; a real link code has 15, 60 events about 1,900)
    def self.parse(s, values = nil); KIF::Net::Parser.new(s, values).run; end

    def self.inflate(z, max = MAX_JSON)
      zi = Zlib::Inflate.new
      out = +"".b
      # in chunks: a small code that unpacks to megabytes is refused early
      zi.inflate(z) { |chunk| out << chunk; raise "too big" if out.bytesize > max }
      out << zi.finish.to_s
      return out.bytesize <= max ? out : nil
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
    # My half of a link: a public value g^x in the group of Net.rb's Spake2 (x stays in this save). The two
    # link codes are often pasted into a chat; the key needs x or the partner's, which those codes don't give.
    def self.my_half
      sp = KIF::Net::Spake2
      h = state[:half]
      return h if h.is_a?(String) && h.length == sp::HEX && (state[:sk] || state[:key])
      x = crypto.random(32).unpack1("H*").to_i(16) | 1
      state[:sk] = x.to_s(16)
      return state[:half] = sp.hex(sp::G.pow(x, sp::P))
    end

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
      h = (s = inflate(z, LINK_JSON)) && parse(s, 200)
      return :invalid unless h.is_a?(Hash) && h["v"] == 1 && h["n"].is_a?(String) && h["t"].is_a?(Integer) &&
                             h["h"].is_a?(String) && h["h"] =~ /\A[0-9a-f]{#{KIF::Net::Spake2::HEX}}\z/ && h["set"].is_a?(String) &&
                             [0, 1].include?(h["m"]) && (h["g"].nil? || h["g"].is_a?(String))
      h["n"] = KIF::Net.shown_name(h["n"])
      return h
    end

    # link this save with the partner whose link code this is; false for my own code
    def self.link_with(info)
      half = my_half
      return false if info["h"] == half
      sp = KIF::Net::Spake2
      y = sp.read(info["h"])
      x = state[:sk].to_i(16)
      if y && y > 1 && y < sp::P - 1 && y.pow(sp::Q, sp::P) == 1   # an element of the group, not a small one
        shared = sp.hex(y.pow(x, sp::P))
      else
        shared = sp.hex(x)   # not a half a partner's game makes: the key is this save's alone (nobody can sign for it)
      end
      lo, hi = [half, info["h"]].sort
      key = crypto.sha256("KIF SL key 2 " + lo + hi + shared)
      state.replace(half: half, key: crypto.hex(key), link: crypto.hex(crypto.sha256("KIF SL id " + key))[0, 16],
                    side: half == lo ? 0 : 1, partner_name: info["n"], partner_tid: info["t"],
                    my_seq: 0, their_seq: 0, acked: 0, my_log: [], their_log: [], places: {}, pending: [],
                    self_key: crypto.hex(crypto.random(16)))
      KIF.log("Soul Link: linked with #{info['n']}")
      @offer = nil
      @asked = false
      @sent = nil
      send_hello
      return true
    end

    def self.unlink
      state.clear
      @offer = nil
      @asked = false
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
      ev["z"] = own_mac(ev)
      st[:my_log] << ev
      KIF.log("Soul Link: event #{ev['k']} #{ev['p'] || ev['n']}")
      push
      return ev
    end

    # Each event this save makes carries a MAC with a key that stays in this save (never sent). The partner has
    # the link key and can forge any update code; the events it sends back as "yours" count only with this MAC.
    def self.own_mac(e)
      key = crypto.unhex(state[:self_key] ||= crypto.hex(crypto.random(16)))
      body = e.reject { |k, _| k == "q" || k == "z" }.sort_by { |k, _| k }.map { |k, v| [k, v] }   # (not q: a moved event is numbered again)
      return crypto.hex(crypto.hmac(key, "KIFSL own" + json(body)))[0, 16]
    end

    def self.own_mac?(e)
      return e["z"].is_a?(String) && crypto.same?(e["z"], own_mac(e))
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
      elsif $PokemonSystem.ch_sl_mode == 1 && !pl[:fused]
        pl[:fused] = true
        queue("k" => "fuse", "i" => mine, "s" => theirs[:s], "n" => theirs[:n], "p" => place)
      end
    end

    def self.queue(action)
      state[:pending] << action
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

    #---------------------------------------------------------------------------
    # Update codes
    #---------------------------------------------------------------------------
    def self.unsent; linked? ? state[:my_seq] - state[:acked] : 0; end

    def self.update_code(events, side = state[:side])
      st = state
      z = Zlib::Deflate.deflate(json({ "v" => 1, "l" => st[:link], "f" => side, "a" => st[:their_seq], "e" => events }))
      mac = crypto.hmac(crypto.unhex(st[:key]), "KIFSL" + z)[0, 8]
      return make_code("KIFSL", z + mac)
    end

    # my events the partner hasn't confirmed (the paste code holds them all)
    def self.my_update_code
      return update_code(state[:my_log].select { |e| e["q"] > state[:acked] }.first(MAX_EVENTS))
    end

    EV_KINDS = %w[c m d o]
    SPECIES_RE = /\A(?!.*_x_)[A-Za-z0-9_]{1,48}\z/   # :NIDORANfE has a small letter; "_x_" ids make PIF's fusion lookup raise

    EV_KEYS = %w[q k r p n s i l t x dbg z]   # what log_event makes; an event is kept in the save as it came, so nothing else may ride along

    def self.valid_event?(e)
      return false unless e.is_a?(Hash) && e.keys.all? { |k| EV_KEYS.include?(k) } && e["q"].is_a?(Integer) && e["q"] > 0 &&
                          EV_KINDS.include?(e["k"]) && e["r"].is_a?(String) && e["r"].length <= 8
      str = proc { |k, n| e[k].nil? || (e[k].is_a?(String) && e[k].length <= n && e[k] !~ /[\x00-\x1f]/) }
      return false unless str.call("p", 48) && str.call("n", 24) && str.call("s", 48)
      return false if e["s"] && e["s"] !~ SPECIES_RE
      ids = e["i"].is_a?(Array) ? e["i"] : [e["i"]].compact
      return false unless ids.length <= 6 && ids.all? { |i| i.is_a?(String) && i =~ /\A[a-z0-9]{1,8}\z/ }
      return false if e["l"] && !(e["l"].is_a?(Integer) && e["l"].between?(1, 1000))
      return false if e["t"] && !(e["t"].is_a?(Integer) && e["t"].between?(0, 2**40))
      return false unless e["dbg"].nil? || e["dbg"] == 1
      return false unless e["x"].nil? || e["x"] == 1
      return false unless e["z"].nil? || (e["z"].is_a?(String) && e["z"].length <= 16)
      return e["k"] == "o" || e["k"] == "d" || e["p"].is_a?(String)
    end

    # Hash {f:, a:, e:} or a Symbol why not: :invalid, :key (not this link / tampered).
    # net: from the connection (one message holds 60 events at most), else one the player pasted (600)
    def self.read_update_code(text, net = false)
      return :off unless linked?
      bytes = code_bytes("KIFSL", text) or return :invalid
      return :invalid if bytes.bytesize < 12
      z = bytes[0...-8]
      return :key unless crypto.same?(crypto.hmac(crypto.unhex(state[:key]), "KIFSL" + z)[0, 8], bytes[-8, 8])
      h = (s = inflate(z, net ? NET_JSON : MAX_JSON)) && parse(s, net ? 2_500 : 24_000)
      return :invalid unless h.is_a?(Hash) && h["v"] == 1 && h["l"] == state[:link] && [0, 1].include?(h["f"]) &&
                             h["a"].is_a?(Integer) && h["e"].is_a?(Array) && h["e"].length <= (net ? CHUNK : MAX_EVENTS) && h["e"].all? { |e| valid_event?(e) }
      h["e"].each { |e| %w[p n s].each { |k| e[k] = e[k].gsub(/[\\<>]/, "") if e[k].is_a?(String) } }   # shown in messages: no message codes, no tags
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
        break if st[:their_log].length >= MAX_LOG   # (a save holds no more than that)
        break if %w[c m].include?(e["k"]) && !st[:places].key?(e["p"]) && st[:places].length >= MAX_PLACES
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
        return [_INTL("{1} died, {2}", e["n"], e["p"]), dead.empty? ? "" : _INTL("{1} dies", dead.join(", "))]
      when "o"
        queue("k" => "over")
        return [_INTL("{1}'s run is over", who), _INTL("yours ends")]
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
      events = events.select { |e| own_mac?(e) }   # only what this save made: the partner can forge the rest
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
    def self.pending?; linked? && !state[:pending].empty?; end

    def self.apply_pending(show = true)
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
          kill(p, where, a["why"] == "log" ? :log : true)
        when "fuse"
          fuse(a) && show && pbMessage(_INTL("Soul Link: {1} fused with {2}'s {3}.", a["was"], partner, species_name(a["s"])))
        when "over"
          over = a
        end
      end
      KIF::Nuzlocke.move_dead_out if $Trainer.party.any? { |p| p && p.kif_nz_dead } && $Trainer.party.any? { |p| KIF::Nuzlocke.able?(p) }
      if over
        pbMessage(_INTL("{1}'s run is over, so yours ends too.", partner)) if show && !over["own"]
        end_together
      elsif !$Trainer.party.any? { |p| KIF::Nuzlocke.able?(p) } && $Trainer.party.any? { |p| p && p.kif_nz_dead }
        KIF::Nuzlocke.whiteout
      end
    end

    def self.end_together
      self.applying = true
      KIF::Nuzlocke.end_run($PokemonSystem.ch_nz_whiteout == KIF::Nuzlocke::WHITEOUT_LOCK)
    ensure
      self.applying = false
    end

    def self.kill(p, where, how = true)
      self.applying = how
      p.hp = 0
      KIF::Nuzlocke.bury(p)
      return unless where.is_a?(Array)   # party: Nuzlocke moves them; Day Care: stays, dead
      fate = $PokemonSystem.ch_nz_fainted
      return if fate > KIF::Nuzlocke::FAINTED_RELEASED
      if fate == KIF::Nuzlocke::FAINTED_GRAVEYARD
        (KIF::Nuzlocke.state[:graveyard] ||= []) << { :name => p.name, :species => p.species, :level => p.level,
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
      p.calc_stats
      return true
    rescue StandardError => e
      KIF.log("Soul Link: fusing failed (#{e.class}: #{e.message})")
      return false
    end

    #---------------------------------------------------------------------------
    # Over the Multiplayer connection
    #---------------------------------------------------------------------------
    def self.session
      s = KIF::Net.session if defined?(KIF::Net) && KIF::Net.respond_to?(:session)
      return s&.connected? ? s : nil
    end

    def self.connected?
      return false unless (s = session) && @peer && linked?
      return @peer["link"] == state[:link]
    end

    def self.on_connect(_s = nil)
      on_disconnect
      send_hello
    end

    def self.on_disconnect
      @peer = nil
      @peer_code = nil
      @peer_info = nil   # (a new partner must not be linked with the last one's code)
      @offer = nil
      @asked = false
      @party_sent = nil
      @hello_sent = false
    end

    def self.send_hello
      s = session or return
      return unless on?
      st = state
      s.post("sl_hello", "link" => st[:link] || "", "seen" => st[:their_seq] || 0, "acked" => st[:acked] || 0,
                         "code" => link_code)
      s.post("sl_party", "ids" => @party_sent = party_ids) if st[:key]
      @hello_sent = true
    end

    # Soul Link turned on while connected: say hello then (checked every second on the map)
    def self.hello_late
      send_hello if !@hello_sent && session && on?
    end

    # id:species:level:hp:totalhp for each link in the party (a fusion has two)
    def self.party_ids
      rows = $Trainer.party.compact.flat_map { |p| ids_of(p).map { |id| [id, p.species, p.level, p.hp, p.totalhp].join(":") } }
      return rows.join(",")[0, 600]
    end

    # the party again when it changed (checked every second on the map)
    def self.send_party
      return unless connected?
      ids = party_ids
      return if ids == @party_sent
      session.post("sl_party", "ids" => @party_sent = ids)
    end

    # the partner's last party: {id => [species, level, hp, totalhp]}
    def self.read_party(text)
      snap = {}
      text.split(",").each do |row|
        id, s, *n = row.split(":")
        next unless id.to_s =~ /\A[a-z0-9]{1,8}\z/ && s.to_s =~ SPECIES_RE && n.length == 3 && n.all? { |x| x =~ /\A\d{1,5}\z/ }
        snap[id] = [s, *n.map(&:to_i)]
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

    # A hello is answered with the whole log, so a partner repeating it is not answered every time:
    # four in a row, then one every 30 seconds
    def self.hello_ok?(st)
      now = KIF::Net.now
      b = (st[:hello_budget] ||= [4.0, now])
      b[0] = 4.0 if b[1] > now   # (a save from an earlier run: the clock restarted)
      b[0] = [b[0] + (now - b[1]) / 30.0, 4.0].min
      b[1] = now
      return false if b[0] < 1
      b[0] -= 1
      return true
    end

    # a message from the partner's game (KIF::Net.update)
    def self.receive(type, msg)
      if type == "sl_hello"   # kept while Off too: linking needs it once Soul Link is turned on
        @peer = msg
        unless msg["code"] == @peer_code   # (a hello again with the same code: nothing new to read)
          @peer_code = msg["code"]
          @peer_info = read_link_code(msg["code"])
        end
      end
      return unless on?
      st = state
      case type
      when "sl_hello"
        return unless st[:key] && msg["link"] == st[:link]
        s = session or return
        return unless hello_ok?(st)   # every answer is this save's whole log
        st[:acked] = [msg["seen"], st[:my_seq]].min
        mine = st[:my_log].select { |e| e["q"] > msg["seen"] }
        mine.each_slice(CHUNK) { |part| s.post("sl_up", "code" => update_code(part)) }
        @sent = st[:my_seq]
        echo = st[:their_log].select { |e| e["q"] > msg["acked"] }
        echo.each_slice(CHUNK) { |part| s.post("sl_up", "code" => update_code(part, 1 - st[:side])) }
        s.post("sl_party", "ids" => @party_sent = party_ids)
      when "sl_link"
        info = read_link_code(msg["code"])
        return unless info.is_a?(Hash)
        @offer = info
        @peer_info = info
        link_with(info) if @asked && !st[:key]
      when "sl_up"
        h = read_update_code(msg["code"], true)
        return KIF.log("Soul Link: an update from #{partner} didn't fit (#{h})") unless h.is_a?(Hash)
        lines, n = receive_update(h)
        @notes = (@notes || []) + lines
        # tell them what arrived (an empty update carries "a")
        session&.post("sl_up", "code" => update_code([])) if n > 0 && h["f"] != st[:side]
      when "sl_party"
        return unless connected?   # only my partner's party
        snap = read_party(msg["ids"])
        @partner_party = snap.keys
        st[:partner_party] = snap
      end
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

    # the partner's Pokémon: its nickname, or what it is now (it may have evolved)
    def self.their_name(r)
      t = r[:theirs]
      return "?" unless t.is_a?(Hash)
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
      if $PokemonSystem.ch_sl_type == 1
        seen = {}
        party.each do |p|
          next if ids_of(p).empty?
          t = p.type1
          out << _INTL("Type rule: {1} and {2} are both {3} type.", seen[t].name, p.name, GameData::Type.get(t).name) if seen[t]
          seen[t] ||= p
        end
      end
      return out + party_rule_lines(party)
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

    # the party rule on the map (checked each second): a line when a pair newly
    # goes missing (a PC deposit, a party change on either side), not every step
    def self.party_rule_check
      lines = party_rule_lines
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
                  _INTL("Your catch fuses with your partner's catch from the same place: yours is the head, theirs the body.")])
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
  condition: proc { KIF::SoulLink.on? },
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

      def bury(p)
        ret = kif_sl_bury(p)
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
        rescue => e
          KIF.log("Soul Link: run end not logged (#{e.class}: #{e.message})")
        end
        return kif_sl_end_run(*args)
      end
    end
  end
end

Events.onMapUpdate += proc { |_sender, _e|
  if Graphics.frame_count % 60 == 0
    begin
      KIF::SoulLink.hello_late
    rescue => e
      KIF.log("Soul Link: hello not sent (#{e.class}: #{e.message})")
    end
  end
  if Graphics.frame_count % 60 == 0 && KIF::SoulLink.linked?
    begin
      KIF::SoulLink.send_party
      KIF::SoulLink.party_rule_check
    rescue => e
      KIF.log("Soul Link: party not sent (#{e.class}: #{e.message})")
    end
  end
  if KIF::SoulLink.pending? && KIF::Net.quiet?
    begin
      KIF::SoulLink.apply_pending
    rescue => e
      KIF.log("Soul Link: applying failed (#{e.class}: #{e.message})")
    end
  end
}
