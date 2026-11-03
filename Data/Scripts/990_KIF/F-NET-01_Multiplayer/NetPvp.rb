#===============================================================================
# F-NET-01 – Multiplayer: PvP, a friendly match against another player in the
# game you are connected to (Multiplayer > Challenge <name>)
#
# One player challenges (format Single, Double or Triple, how many Pokemon each,
# an optional level rule: all 50 or all 100); the other says yes or no at a quiet
# moment on the map. Then the CHALLENGER's game runs the battle (whoever it is:
# the Multiplayer host or a guest) over the co-op machinery (NetCoop*.rb): the
# other player plays the runner's log on its own battle screen, from the other
# side (battler i is the runner's i ^ 1), and sends back checked choices. In a
# lobby of three the third player is not part of it. Two guests fight through the
# lobby host, which passes their frames on (Net.rb, FORWARD: the same hop-by-hop
# line each way); the host's own game plays on as usual. Messages:
#   co_vs  {id, fmt, n, lv}   challenge (fmt 0: cancelled); fmt 1 single, 2 double, 3 triple
#   co_vsr {id, ok, why}      the answer (why: busy, no, few)
# After a yes the runner sends co_ask (kind "pvp"), the other game answers co_join
# with its team, and co_begin .. co_end run as in co-op. Every one of these
# messages counts only from the player the match is with (the slot the frame
# came from), so a third player's frames do nothing.
#
# Both games fight with COPIES of the picked Pokemon, so nothing about a real
# Pokemon changes: no Exp, EVs, money, catches, items or evolutions. The match
# is not a normal trainer battle (no pbAfterBattle): no Nuzlocke burial or Soul
# Link event, no whiteout (so no DeathLink), no autosave, no battle counter of
# the Archipelago traps. The Bag and balls are off, Auto-Battle and "let the
# game choose" are off, Level Caps do not apply, and the Multiplayer host's
# gameplay settings count. Run is a forfeit. A player who does not choose in
# PvP.pick_wait seconds has that turn picked by the game's AI, and forfeits after
# two such waits in a row (a pick or a replacement; a real pick starts over); one whose line
# drops, or whose game can't show the battle, loses to the other; so does one
# the runner hears nothing from for PvP.silence seconds (the other game sends a
# "still here" every PvP.beat_every seconds from a thread, so a stalled lobby
# host that stops passing frames on ends the match too). The other player's team
# is rebuilt strictly (PvP.load_strict): stats worked out here, EVs capped, an
# ability its species can't have dropped, a team with a move, ability or item
# this game lacks refused.
#
# The runner's game decides everything in the battle, so a modified runner could
# cheat: matches are for friends (the join code), and the screen says so. Between
# two guests the lobby host also reads every frame and could change it unseen:
# frames are signed for each line (guest to host, host to guest), not from one
# guest to the other.
#===============================================================================
module KIF
  module PvP
    ID = [Integer, 1, 1_000_000_000]
    # (plain fields only: Net.frame_limits gives these a few hundred bytes and 36 values)
    { "co_vs"  => { "id" => ID, "fmt" => [Integer, 0, 3], "n" => [Integer, 1, 6], "lv" => [Integer, 0, 100] },
      "co_vsr" => { "id" => ID, "ok" => [Integer, 0, 1], "why" => [String, 16] },
    }.each { |k, v| KIF::Net::TYPES[k] = v }

    LEVELS = [0, 50, 100]   # the level rules: as they are, all 50, all 100
    Mon = KIF::Coop::Mon

    # seconds; tests shorten them
    @answer_wait = 45.0   # a challenge waits this long for an answer
    @join_wait   = 25.0   # the host waits this long for the other game to join after a yes
    @quiet_wait  = 12.0   # the other game waits this long for a quiet moment to join
    @pick_wait   = 60.0   # a player picks a move in this long, else the AI picks that turn
    @sw_wait     = 45.0   # ... a replacement
    SILENT_FORFEIT = 2    # waits for a pick that end with no pick, in a row: that player forfeits
    @silence     = 30.0   # the runner hears nothing from the other game for this long: that player forfeits
    @beat_every  = 5.0    # the other game says "still here" this often (from a thread, so a menu or a long message doesn't stop it)
    @running = false
    @line = nil
    @next_id = nil

    class << self
      attr_accessor :answer_wait, :join_wait, :quiet_wait, :pick_wait, :sw_wait, :silence, :beat_every
      def running?; @running; end

      # a challenge is out, received, said yes to, or about to run on this game
      def pending?
        st = line
        return st ? !!(st[:out] || st[:in] || st[:acc] || st[:go] || st[:ask]) : false
      end
    end

    def self.log(msg); KIF::Net.log("pvp: #{msg}"); end
    def self.session; s = KIF::Net.session if KIF::Net.respond_to?(:session); s&.connected? ? s : nil; end
    def self.partner(slot = nil)
      s = session or return "?"
      n = slot && s.respond_to?(:name_of) ? s.name_of(slot) : nil
      return KIF::Net.shown_name(n || s.partner)
    end
    def self.post(t, f = {}, slot = nil); (s = session) ? KIF::Net.post_to(s, t, f, slot) : false; end

    # Who a match is with: the one other player, or (a lobby of three) the one picked from the others, the host
    # and the other guest alike. nil: a stand-in session (the one partner), or Back.
    def self.target
      s = session
      return nil unless s && s.respond_to?(:peers)
      ps = s.peers
      return nil if ps.empty?
      return ps[0][0] if ps.length == 1
      return KIF::Net.pick_peer(_INTL("Challenge who?"))
    end

    # this player's lobby slot (0 the host). The role belongs to the session, so a match passes its own (s): that
    # session keeps its role after its line dropped, while PvP.session (connected ones only) is nil by then and
    # the host would read as slot 1. A stand-in session has no slot: its role says.
    def self.my_slot(s = nil)
      s ||= KIF::Net.session if KIF::Net.respond_to?(:session)
      return s.my_slot if s.respond_to?(:my_slot)
      return s.role == :host ? 0 : 1 if s.respond_to?(:role)
      return KIF::Coop.rules_host? ? 0 : 1
    end

    # a match between two guests: the lobby host passes every frame on
    def self.relayed?(with, s = nil)
      return with.is_a?(Integer) && with != 0 && my_slot(s) != 0
    end

    # the slot the match in this line is with (nil: the one partner)
    def self.with_of(st)
      return (st[:out] || st[:in] || st[:acc] || st[:go] || st[:ask] || {})[:with]
    end
    def self.note(text); KIF::Net.notes << text unless KIF::Net.notes.include?(text); end

    # per connection: the challenge sent (:out), the one received (:in), a yes this game gave or got and
    # now waits on the host for (:acc), the match this host starts (:go), the host's invite (:ask)
    def self.line
      s = session or return nil
      @line = { s: s, out: nil, in: nil, acc: nil, go: nil, ask: nil, declines: 0, mute: 0.0, busy_at: 0.0 } unless @line && @line[:s].equal?(s)
      return @line
    end

    # a state in which this game starts or joins no match
    def self.busy?
      return true if @running || KIF::Coop.guest || KIF::Coop.hosting? || $game_temp&.in_battle
      return KIF::Coop.cannot_join?
    end

    def self.next_id
      @next_id = ((@next_id || (Random.rand(1000) * 1000)) + 1) % 1_000_000_000
      @next_id = 1 if @next_id == 0
      return @next_id
    end

    def self.describe(fmt, n, lv)
      return _INTL("{1}, {2}, {3}", fmt == 3 ? _INTL("Triple battle") : fmt == 2 ? _INTL("Double battle") : _INTL("Single battle"),
                   n == 1 ? _INTL("1 Pokemon each") : _INTL("{1} Pokemon each", n),
                   lv == 0 ? _INTL("levels as they are") : _INTL("all level {1}", lv))
    end

    #---------------------------------------------------------------------------
    # Pokemon for a match: copies, healed, at the level rule
    #---------------------------------------------------------------------------
    def self.copy(pk)
      return Marshal.load(Marshal.dump(pk))
    rescue StandardError
      return defined?(KIF::PokeIO) ? (KIF::PokeIO.from_hash(KIF::PokeIO.to_hash(pk)) rescue nil) : nil
    end

    # a copy at full health and PP, at lv when there is a rule (0: as it is)
    def self.ready(pk, lv)
      c = copy(pk) or return nil
      c.level = [lv, GameData::GrowthRate.max_level].min if lv > 0
      c.calc_stats
      c.instance_variable_set(:@hp, c.totalhp)   # (heal would keep a fainted one down in No reviving)
      c.heal_status
      c.heal_PP
      return c
    end

    # copies of this player's Pokemon for a match: no Eggs, none a Nuzlocke run buried. More than n: the player
    # picks n (the usual team pick). [] for none, nil if the pick was cancelled.
    def self.pick_team(n)
      mine = $Trainer.party.compact.reject { |p| p.egg? || p.instance_variable_get(:@kif_nz_dead) }.map { |p| copy(p) }.compact
      return mine if mine.length <= n
      orig = $Trainer.party
      begin
        $Trainer.party = mine   # (the pick works on the trainer's party: the real one is put back below)
        @pick_fainted = true    # (a match uses healed copies: a fainted Pokemon may be picked)
        unless PokemonSelection.choose(n, n, true, true)
          return PokemonSelection.hasValidTeam?(n, n, true, true) ? nil : []   # [] is not a cancel: too few can take part, the caller says so
        end
        return $Trainer.party.compact.first(n)
      ensure
        @pick_fainted = false
        PokemonSelection.restore
        $Trainer.party = orig
      end
    end

    def self.pick_fainted; @pick_fainted ? true : false; end

    def self.choose_number(text, min, max, cur)
      p = ChooseNumberParams.new
      p.setMaxDigits(1)
      p.setRange(min, max)
      p.setDefaultValue(cur)
      p.setInitialValue(cur)
      p.setCancelValue(-1)
      p.setNegativesAllowed(false)
      n = pbMessageChooseNumber(text, p)
      return n.is_a?(Integer) && n >= min && n <= max ? n : nil
    end

    #---------------------------------------------------------------------------
    # The row on the Multiplayer connected screen
    #---------------------------------------------------------------------------
    def self.menu_label
      st = line
      return _INTL("Challenge: waiting for {1}", partner(st[:out][:with])) if st && st[:out]
      return _INTL("Challenge: {1} asked", partner(st[:in][:with])) if st && st[:in]
      return _INTL("Challenge") if session.respond_to?(:peers) && session.peers.length > 1
      return _INTL("Challenge {1}", partner)
    end

    def self.menu_pick(_scr = nil)
      st = line or return
      if (o = st[:out])
        cancel(st) if pbConfirmMessage(_INTL("Cancel your challenge to {1}?", partner(o[:with])))
        return
      end
      return pbMessage(_INTL("{1} has already asked you. Answer on the map.", partner(st[:in][:with]))) if st[:in]
      return pbMessage(_INTL("You can't start a match right now.")) if busy? || st[:go] || st[:acc]
      with = target
      return if with.nil? && session.respond_to?(:peers) && session.peers.length > 1   # Back
      who = partner(with)
      pbMessage(_INTL("A friendly match against {1}: no Exp, money or catches, and no Bag. You each bring your own Pokemon.", who))
      pbMessage(_INTL("Your game runs the battle, and {1}'s game plays it from the other side. A modified game could cheat, so only battle friends you trust.", who))
      pbMessage(relay_line) if relayed?(with)
      c = pbMessage(_INTL("Challenge {1}?", who), [_INTL("Single battle"), _INTL("Double battle"), _INTL("Triple battle"), _INTL("Cancel")], 4)
      return unless c.is_a?(Integer) && c >= 0 && c <= 2
      fmt = c + 1
      min = fmt
      n = choose_number(_INTL("How many Pokemon each?"), min, 6, 6) or return
      l = pbMessage(_INTL("Level rule?"), [_INTL("Levels as they are"), _INTL("All level 50"), _INTL("All level 100"), _INTL("Cancel")], 4)
      return unless l.is_a?(Integer) && l >= 0 && l <= 2
      team = pick_team(n) or return
      return pbMessage(_INTL("You need at least {1} Pokemon that can take part. Eggs and buried Pokemon can't.", min)) if team.length < min
      n = team.length   # (a smaller team than asked for: the friend brings no more than that)
      id = next_id
      return unless post("co_vs", { "id" => id, "fmt" => fmt, "n" => n, "lv" => LEVELS[l] }, with)
      st[:out] = { id: id, fmt: fmt, n: n, lv: LEVELS[l], team: team, at: KIF::Net.now, with: with }
      note(_INTL("Asked {1}: {2}.", who, describe(fmt, n, LEVELS[l])))
    end

    # said to both guests of a match through the lobby host
    def self.relay_line
      s = session
      h = s && s.respond_to?(:name_of) ? s.name_of(0) : nil
      return _INTL("{1}'s game passes the match on between you two, so {1} could read or change it. Only battle where you all trust each other.", KIF::Net.shown_name(h || "The host"))
    end

    def self.cancel(st)
      o = st[:out] or return
      st[:out] = nil
      post("co_vs", { "id" => o[:id], "fmt" => 0, "n" => 1, "lv" => 0 }, o[:with])
    end

    #---------------------------------------------------------------------------
    # Messages (KIF::Coop.receive hands them over)
    #---------------------------------------------------------------------------
    def self.receive(type, msg, from = nil)
      st = line or return
      case type
      when "co_vs" then got_challenge(st, msg, from)
      when "co_vsr" then got_answer(st, msg, from)
      end
    end

    def self.reply(id, ok, why = "", slot = nil); post("co_vsr", { "id" => id, "ok" => ok, "why" => why }, slot); end

    def self.got_challenge(st, m, from = nil)
      if m["fmt"] == 0   # taken back
        st[:in] = nil if st[:in] && st[:in][:id] == m["id"] && st[:in][:with] == from
        st[:acc] = nil if st[:acc] && st[:acc][:id] == m["id"] && st[:acc][:with] == from
        return
      end
      return unless LEVELS.include?(m["lv"]) && m["n"] >= m["fmt"]
      now = KIF::Net.now
      o = st[:out]
      # at most one question at a time, and a short "busy" a few seconds apart (a stream of challenges costs this game almost nothing)
      # (a challenge of this game's own that waits for someone else's answer is one question too)
      busy_now = st[:in] || st[:go] || st[:acc] || busy? || now < st[:mute]
      # both challenged each other at once: the lower slot's challenge counts (both games work it out the same), the higher one is dropped
      them = from || (my_slot == 0 ? 1 : 0)   # (a stand-in session has no slots: the one partner)
      crossed = o && o[:with] == from && them < my_slot
      if busy_now || (o && !crossed)
        return unless now - st[:busy_at] > 3.0
        st[:busy_at] = now
        return reply(m["id"], 0, "busy", from)
      end
      if crossed
        st[:out] = nil
        note(_INTL("{1} challenged you too. Answer theirs.", partner(from)))
      end
      st[:in] = { id: m["id"], fmt: m["fmt"], n: m["n"], lv: m["lv"], at: now, with: from }
    end

    def self.got_answer(st, m, from = nil)
      o = st[:out]
      return unless o && o[:id] == m["id"] && o[:with] == from   # only the player that was asked answers
      st[:out] = nil
      who = partner(from)
      if m["ok"] != 1
        why = { "busy" => _INTL("{1} is busy.", who), "few" => _INTL("{1} has too few Pokemon for that.", who) }[m["why"]]
        return note(why || _INTL("{1} said no.", who))
      end
      note(_INTL("{1} said yes.", who))
      st[:go] = o   # this game runs the match
    end

    # the runner's invite to join a match (KIF::Coop.guest_ask): only after a yes, only from the player that was said yes to
    def self.got_ask(msg, from = nil)
      s = session or return
      st = line
      a = st[:acc]
      return post("co_no", { "id" => msg["id"], "why" => "busy" }, from) if !a || busy? || msg["max"] != a[:n] || a[:with] != from
      st[:ask] = msg.merge("from" => from)
      st[:ask_at] = KIF::Net.now
    end

    #---------------------------------------------------------------------------
    # On the map, every frame
    #---------------------------------------------------------------------------
    def self.map_tick
      st = line or return
      now = KIF::Net.now
      gone(st)
      if (o = st[:out]) && now - o[:at] > @answer_wait
        cancel(st)
        note(_INTL("{1} didn't answer.", partner(o[:with])))
      end
      st[:acc] = nil if st[:acc] && now - st[:acc][:at] > 120
      st[:in] = nil if st[:in] && now - st[:in][:at] > @answer_wait + 15
      if (ask = st[:ask])
        if !st[:acc] || busy?
          st[:ask] = nil
          return post("co_no", { "id" => ask["id"], "why" => "busy" }, ask["from"])
        elsif KIF::Net.quiet?
          st[:ask] = nil
          return join(st, ask)
        elsif now - st[:ask_at] > @quiet_wait
          st[:ask] = nil
          return post("co_no", { "id" => ask["id"], "why" => "busy" }, ask["from"])
        end
      end
      return unless KIF::Net.quiet?
      ask_player(st) if st[:in]
      run_hosted(st) if st[:go] && KIF::Net.quiet?
    end

    # a challenge, an answer or an invite whose player has left the lobby (the others go on) is dropped
    def self.gone(st)
      s = session
      return unless s && s.respond_to?(:peers)
      ps = s.peers
      return if ps.empty?
      %i[out in acc go].each do |k|
        w = st[k] && st[k][:with]
        st[k] = nil if w && ps.none? { |sl, _n, _v| sl == w }
      end
    end

    # the friend challenged: a question at a quiet moment
    def self.ask_player(st)
      c = st[:in]
      st[:in] = nil
      with = c[:with]
      who = partner(with)
      pbMessage(_INTL("{1}'s game would run the battle. A modified game could cheat, so only accept friends you trust.", who))
      pbMessage(relay_line) if relayed?(with)
      yes = pbConfirmMessage(_INTL("{1} challenges you: {2}. Accept?", who, describe(c[:fmt], c[:n], c[:lv])))
      return unless session
      team = yes ? pick_team(c[:n]) : nil
      min = c[:fmt]
      few = team && team.length < min
      if !team || few
        unless few   # (a No, or a pick cancelled)
          st[:declines] += 1
          st[:mute] = KIF::Net.now + 60 if st[:declines] >= 2   # two No answers: no more questions for a minute
        end
        pbMessage(_INTL("You need at least {1} Pokemon that can take part. Eggs and buried Pokemon can't.", min)) if few
        return reply(c[:id], 0, few ? "few" : "no", with)
      end
      st[:declines] = 0
      go = { id: c[:id], fmt: c[:fmt], n: c[:n], lv: c[:lv], team: team, at: KIF::Net.now, with: with }
      return unless reply(c[:id], 1, "", with)
      st[:acc] = go   # the challenger's game runs the match: its invite comes next
    end

    #---------------------------------------------------------------------------
    # The challenger (the Multiplayer host or a guest): invite, read the team, run the match
    #---------------------------------------------------------------------------
    def self.run_hosted(st)
      go = st[:go]
      st[:go] = nil
      s = session
      return unless go && s
      with = go[:with]
      if busy?   # (the other game waits for an invite that will not come: told so)
        post("co_vs", { "id" => go[:id], "fmt" => 0, "n" => 1, "lv" => 0 }, with)
        return note(_INTL("You can't start the match right now."))
      end
      id = next_id
      KIF::Coop.instance_eval { @host_box.clear; @host_id = id; @host_slots = with ? [with] : nil }
      reply = nil
      begin
        unless post("co_ask", { "id" => id, "map" => ($game_map ? $game_map.map_id : 0), "kind" => "pvp", "max" => go[:n] }, with)   # (gone from the lobby)
          return note(_INTL("{1} is not in the game any more.", partner(with)))
        end
        KIF::Coop.wait_map(@join_wait) { reply = KIF::Coop.take_host(id, %w[co_join co_no]) }
        join = reply && reply[0] == "co_join" ? read_join(reply[1], go) : nil
        join[:slot] = with if join
        unless join
          who = partner(with)
          if !reply then pbMessage(_INTL("{1} didn't join.", who))
          elsif reply[0] == "co_no" then pbMessage(_INTL("{1} is busy.", who))
          else pbMessage(_INTL("{1}'s team has moves or Pokemon this game doesn't have (a mod's, or another KIF's), or doesn't fit the match.", who))
          end
          post("co_end", { "id" => id, "d" => { "x" => reply && reply[0] == "co_join" ? "party" : "late" } }, with) if session
          return
        end
        join[:id] = id
        battle(s, join, go)
      ensure
        KIF::Coop.instance_eval { @host_id = nil }
      end
    end

    def self.read_join(msg, go)
      list = msg["party"]
      return nil unless list.is_a?(Array) && list.length.between?(1, go[:n])
      party = list.map { |h| load_strict(h) }
      return nil if party.any?(&:nil?) || party.length < go[:fmt]
      return { party: party, name: KIF::Net.shown_name(msg["name"]), type: KIF::Coop::Mon.partner_type(msg["type"]),
               tid: msg["tid"].is_a?(Integer) ? msg["tid"] : 0, bag: {} }
    end

    # A friend's Pokemon from checked fields, or nil. What the other game sends is not trusted: the stats are worked
    # out here from the level, IVs, EVs and nature (this game's IV and EV modes count), EVs stay within the limit, an
    # ability its species can't have is dropped for its normal slot, and a Pokemon with a move, ability or item this
    # game doesn't have (a mod's, another KIF's), an Egg, or two of the same move is refused.
    def self.load_strict(h)
      mon = KIF::Coop::Mon
      p = mon.load(h, true) or return nil
      return nil if p.egg? || p.instance_variable_get(:@kif_coop_lost)
      ids = p.moves.map(&:id)
      return nil if ids.empty? || ids.uniq.length != ids.length
      ab = p.instance_variable_get(:@ability)
      p.instance_variable_set(:@ability, nil) if ab && !p.getAbilityList.any? { |a, _i| a == ab }
      tot = mon::STATS.sum { |s| p.ev[s] }
      mon::STATS.each { |s| p.ev[s] = p.ev[s] * Pokemon::EV_LIMIT / tot } if tot > Pokemon::EV_LIMIT
      p.calc_stats
      p.instance_variable_set(:@hp, p.totalhp)
      return p
    rescue StandardError, SystemStackError => e
      log("a Pokemon didn't fit (#{e.class}: #{e.message})")
      return nil
    end

    # Runs the match on this game (the challenger's). Own runner, not pbTrainerBattleCore: no pbAfterBattle.
    def self.battle(s, join, go)
      dbl = go[:fmt] >= 2   # (a double or a triple: the battle's size is named below)
      lv = go[:lv]
      decision = 0
      host = nil
      @running = true
      auto = $PokemonSystem.respond_to?(:autobattler) ? $PokemonSystem.autobattler : nil
      $PokemonSystem.autobattler = 0 if auto
      waits = [KIF::Coop.cmd_wait, KIF::Coop.sw_wait]
      KIF::Coop.cmd_wait, KIF::Coop.sw_wait = @pick_wait, @sw_wait
      KIF::Coop.with_rules { suspended do
        mine = go[:team].map { |p| ready(p, lv) }.compact
        foe = join[:party].map { |p| ready(p, lv) }.compact
        trainer = NPCTrainer.new(join[:name], join[:type])
        trainer.id = join[:tid]
        trainer.party = foe
        trainer.lose_text = ""
        trainer.define_singleton_method(:full_name) { name }   # "Monto sent out ...", not with a trainer class
        battle = PokeBattle_Battle.new(pbNewBattleScene, mine, foe, [$Trainer], [trainer])
        battle.party1starts = [0]
        battle.party2starts = [0]
        setBattleRule(%w[single double triple][go[:fmt] - 1], "canLose", "noexp", "nomoney", "cannotrun", "setstyle")
        pbPrepareBattle(battle)
        $PokemonTemp.clearBattleRules
        battle.switchStyle = false
        host = Host.new(s, join)
        host.attach(battle)
        Audio.me_stop
        log("match #{join[:id]} with #{join[:name]} (#{%w[single double triple][go[:fmt] - 1]}, #{mine.length} v #{foe.length}, level rule #{lv})")
        pbBattleAnimation(pbGetTrainerBattleBGM([trainer]), dbl ? 3 : 1, [trainer]) {
          pbSceneStandby { decision = battle.pbStartBattle }
        }
        Input.update
      end }   # (the Multiplayer host's gameplay settings count, as in every shared battle)
      result(decision, join[:name])
    rescue StandardError, SystemStackError => e
      log("match failed (#{e.class}: #{e.message})")
      pbMessage(_INTL("The match could not go on."))
    ensure
      (host.finish(0, "abort") rescue nil) if host
      KIF::Coop.cmd_wait, KIF::Coop.sw_wait = waits if waits
      $PokemonSystem.autobattler = auto if auto
      $PokemonTemp.clearBattleRules
      $game_player.straighten if $game_player
      @running = false
    end

    # Nuzlocke has no say in a match: nobody is buried, no place is used, a loss is not a whiteout (copies fight: nothing to restore)
    def self.suspended(&blk)
      return yield unless defined?(KIF::Nuzlocke) && KIF::Nuzlocke.respond_to?(:suspended)
      return KIF::Nuzlocke.suspended(restore: false, &blk)
    end

    # the end, on both games; d is the decision as this player saw it (1 won, 2 lost, 5 draw, else no result)
    def self.result(d, who)
      t = case d
          when 1 then _INTL("You won the match against {1}!", who)
          when 2 then _INTL("You lost the match against {1}.", who)
          when 5 then _INTL("The match against {1} was a draw.", who)
          else _INTL("The match against {1} didn't finish.", who)
          end
      t += "\n" + _INTL("No Exp, money or Pokemon were won or lost.") if [1, 2, 5].include?(d)
      pbMessage(t)
    end

    #---------------------------------------------------------------------------
    # The other game: join the runner's match
    #---------------------------------------------------------------------------
    def self.join_msg(id, team)
      return { "id" => id, "name" => $Trainer.name.to_s[0, 24], "type" => $Trainer.trainer_type.to_s[0, 48],
               "tid" => $Trainer.id.to_i & 0xffffffff, "party" => team.map { |p| KIF::Coop::Mon.dump(p, true) }, "items" => {} }
    end

    def self.join(st, ask)
      s = session or return
      a = st[:acc]
      st[:acc] = nil
      post("co_join", join_msg(ask["id"], a[:team]), a[:with])
      g = Guest.new(s, ask["id"], $Trainer, a[:team].map { |p| ready(p, a[:lv]) }.compact, nil, runner: a[:with])
      KIF::Coop.guest = g
      @running = true
      begin
        g.beat_start
        g.run
      rescue StandardError, SystemStackError => e
        log("match screen failed (#{e.class}: #{e.message})")
        (post("co_act", { "id" => ask["id"], "d" => { "b" => -1, "a" => "auto" } }, a[:with]) rescue nil)
      ensure
        KIF::Coop.guest = nil
        g.beat_stop
        @running = false
      end
    end

    #---------------------------------------------------------------------------
    # The host's side of the battle
    #---------------------------------------------------------------------------
    # extended onto this match's battle object only
    module Rules
      def pbItemMenu(_idxBattler, _firstAction)
        pbDisplay(_INTL("Items can't be used in this battle."))
        return false
      end

      # the end lines are the host's own: the other game words its own
      def pbEndOfBattle(*args)
        c = @kif_coop
        return c ? c.quietly { super } : super
      end
    end

    class Host < KIF::Coop::Host
      def attach(battle)
        beat_start
        @battle = battle
        battle.instance_variable_set(:@kif_coop, self)
        battle.extend(Rules)
        sc = battle.scene
        sc.extend(KIF::Coop::Capture)   # (no IntentShow: nobody sees the other's pick)
        sc.instance_variable_set(:@kif_coop, self)
      end

      # the other player's Pokemon are the foe side; the whole foe party is theirs
      def start; 0; end
      def guest_party; @battle.pbParty(1); end
      def slot?(abs); abs.is_a?(Integer) && abs >= 0 && abs < guest_party.length; end
      def owner(i); @battle.opposes?(i) ? 1 : 0; end

      def guest?(idx)
        return idx.is_a?(Integer) && @battle && @battle.battlers[idx] && @battle.opposes?(idx) ? true : false
      end

      def order
        o = @battle.pbPartyOrder(1)
        return guest_party.each_index.map { |j| o[j] || j }
      end

      def party_state
        guest_party.map { |p| p ? [p.hp, p.status.to_s, p.totalhp] : nil }
      end

      def partner_intent; nil; end
      def send_intent(_clear = false); end

      def begin_battle
        b = @battle
        d = { "w" => 0, "sz" => [b.pbSideSize(0), b.pbSideSize(1)], "env" => b.environment.to_s, "bd" => b.backdrop.to_s,
              "bb" => b.backdropBase.to_s, "tm" => b.time.to_i, "ht" => trainer_h(b.player[0]),
              "hp" => b.pbParty(0).map { |p| disp(p) }, "gs" => b.pbParty(0).length, "gn" => guest_party.length,
              "bt" => b.battlers.each_with_index.map { |x, i| x ? [i, x.pokemonIndex] : nil }.compact,
              "cl" => 1, "cr" => 0, "mg" => 0, "eg" => 0, "pv" => 1 }
        m = ($game_system.getPlayingBGM rescue nil)
        d["bgm"] = [m.name.to_s[0, 80], m.volume.to_i, m.pitch.to_i] if m && !m.name.to_s.empty?
        post("co_begin", "d" => d)
      end

      # no "let the game choose": it would hand the other player's turn to the AI whenever this player pressed B
      def waiting_choice(change)
        sc = @battle.scene
        hide = sc.respond_to?(:pbHideAllDataboxes) && !sc.instance_variable_get(:@dataBoxesHidden)
        sc.pbHideAllDataboxes if hide
        cmds = [[nil, _INTL("Keep waiting")]]
        cmds << [:change, _INTL("Change my choice")] if change
        i = (quietly { sc.pbShowCommands(_INTL("Waiting for {1}.", @name), cmds.map(&:last), 0) } rescue 0)
        return i.is_a?(Integer) && i >= 0 && cmds[i] ? cmds[i][0] : nil
      ensure
        (sc.pbShowAllDataboxes rescue nil) if hide
      end

      def wait_text(left, change = false)
        return _INTL("Waiting for {1} to choose... ({2} s)\n{3}: change your choice", @name, left, back_name) if change
        return _INTL("Waiting for {1} to choose... ({2} s)", @name, left)
      end

      # a player who gives no answer has that turn picked by the AI; it never plays on for them
      # A player whose line is alive but who gives no pick when the wait ends (a move, or a replacement) SILENT_FORFEIT
      # times in a row forfeits at once: the other side wins. A real pick starts the count again (Coop::Host counts the
      # same way, but there the AI fights on).
      def silent(why)
        return @silent = 0 if why == true
        return unless why == :time
        @silent += 1
        return if @silent < SILENT_FORFEIT || @silent_forfeit || @battle.decision != 0
        @silent_forfeit = true
        KIF::Coop.log("#{@name} gave no pick #{SILENT_FORFEIT} times in a row: the match is a forfeit")
        (quietly { @battle.pbDisplayPaused(_INTL("{1} did not choose for {2} turns. You win.", @name, SILENT_FORFEIT)) } rescue nil)
        @battle.decision = 1
      end

      # a dropped line is said when the match ends (the AI picks the missing side meanwhile)
      def lose
        return if @lost
        @lost = true
        KIF::Coop.log("lost #{@name} during the match")
      end

      # A pick of "forfeit" ends the wait at once, and so does a silence of PvP.silence seconds: that player forfeits (its
      # game, its line or the lobby host that passes the frames on has stopped). Any frame of this match from that player
      # is a sign of life; its "still here" (see Guest#beat_start) is only that, so it is not kept (the box holds 32).
      def collect
        note_life
        r = super || @answers.values.any? { |a| a["a"] == "forfeit" }
        return r if r || @pending.empty? || KIF::Net.now - (@heard ||= KIF::Net.now) <= PvP.silence
        @gone = true
        return true
      end

      def note_life
        box = KIF::Coop.host_box
        mine = box.select { |_t, m, f| m["id"] == @id && (f.nil? || @slot.nil? || f == @slot) }
        @heard = KIF::Net.now unless mine.empty?
        box.reject! { |t, m, _f| t == "co_act" && m["d"].is_a?(Hash) && m["d"]["a"] == "beat" && mine.any? { |x| x[1].equal?(m) } }
      end

      # the other player picks Run: they forfeit; no items
      def apply(i, a)
        case a["a"]
        when "forfeit"
          @battle.pbDisplayPaused(_INTL("{1} forfeited the match!", @name))
          @battle.decision = 1
          return true
        when "item", "run" then return false
        end
        return super
      end

      # the match is over for a player whose line dropped (the other wins) or whose game can't show it (no result)
      def take_commands
        @heard = KIF::Net.now   # (the silence counts from the start of this wait: the frames of a long message of this game are read first)
        @gone = false
        super
        connected?   # notices a dropped line
        return unless @battle.decision == 0 && (@lost || @auto || @gone)
        # Between two guests the lobby host passes every frame on, so this game can't always tell the other player's fault
        # from the host's. A lost line with the host still there (the roster says the player left) is the player's: a win.
        # The line to the host gone, or a silent player while the host's game has said nothing for a few roster beats
        # (it is in a menu or stalled; its thread still answers pings), is nobody's: no result. A host from before the roster
        # beat (host_quiet nil) is taken as answering.
        relay = PvP.relayed?(@slot, @s)
        q = relay && @s.respond_to?(:host_quiet) ? @s.host_quiet : nil
        down = relay && !@s.connected?
        stale = q && q > 3 * @s.roster_every
        if @lost && !down
          @battle.pbDisplayPaused(_INTL("{1} lost the connection. You win.", @name))
          @battle.decision = 1
        elsif down || (@gone && stale)
          @battle.pbDisplayPaused(_INTL("{1} can't be reached through the lobby host's game. The match ends with no result.", @name))
          @battle.decision = 3
        elsif @gone
          @battle.pbDisplayPaused(_INTL("{1} is not answering. You win.", @name))
          @battle.decision = 1
        else
          @battle.pbDisplayPaused(_INTL("{1}'s game can't show the battle. The match is over.", @name))
          @battle.decision = 3
        end
      end

      def finish(decision, why = nil)
        return if @done
        flush if @battle
        @done = true
        (@beat.kill rescue nil) if @beat
        d = { "dc" => decision.to_i }
        d["x"] = why if why
        d["f"] = 1 if @silent_forfeit   # (the other game says why it lost)
        post("co_end", "d" => d) if connected?
        KIF::Coop.log("match #{@id} over (#{why || decision})")
      end
    end

    #---------------------------------------------------------------------------
    # The other player's side of the battle: the host's battle from the other side
    #---------------------------------------------------------------------------
    class Guest < KIF::Coop::Guest
      # party: copies of the picked Pokemon (at the level rule); runner: the lobby slot of the player whose game runs the match
      def initialize(session, id, trainer, party, view = nil, runner: nil)
        super(session, id, trainer, view, runner: runner)
        @party = party
        @max = nil
        @view ||= View.new(self)
      end

      # "Still here" to the runner every PvP.beat_every seconds, from a thread (a menu or a message that waits for a key
      # doesn't stop it): the runner counts a player it hears nothing from as gone (PvP.silence). It only queues a frame.
      def beat_start
        @beat = Thread.new do
          at = KIF::Net.now
          until @done || @stopped
            sleep 0.1
            next if KIF::Net.now - at < PvP.beat_every
            at = KIF::Net.now
            begin
              gpost("co_act", "id" => @id, "d" => { "a" => "beat" })   # (no "b": -1 means "can't show the battle" to a replacement wait)
            rescue StandardError
              nil
            end
          end
        end
        @beat.report_on_exception = false
      end

      def beat_stop; (@beat.kill rescue nil) if @beat; @beat = nil; end

      def intent; nil; end

      # the two sides swap: the host's i is this copy's i ^ 1 (single, double: 0 <-> 1, 2 <-> 3)
      def bat(i); i.is_a?(Integer) && i >= 0 && i <= 5 ? i ^ 1 : i; end

      def party_index(pi, side)
        return nil unless pi.is_a?(Integer) && pi >= 0
        return pi < (side == 1 ? @hn : @gn) ? pi : nil
      end

      def start_event; end   # (no Exp, so no levels to remember)

      # the host's word is final on a copy
      def take_state(_j, pk, hp, st)
        pk.instance_variable_set(:@hp, hp)
        pk.instance_variable_set(:@status, hp > 0 ? (st || :NONE) : :NONE)
        return true
      end

      def sync_party(d)
        (d["pt"].is_a?(Array) ? d["pt"] : []).first(@gn).each_with_index do |x, j|   # (the host's totals: its IV and EV modes may differ)
          pk = @party[j]
          pk.instance_variable_set(:@totalhp, int(x[2], 1, 99_999, pk.totalhp)) if pk && x.is_a?(Array)
        end
        super
      end

      def build(d)
        return false unless d.is_a?(Hash)
        sz = d["sz"]
        return false unless sz.is_a?(Array) && sz.length == 2 && sz[0] == sz[1] && [1, 2, 3].include?(sz[0])
        @hn = int(d["gs"], 1, 6) or return false
        @gn = int(d["gn"], 1, 6) or return false
        return false unless @gn == @party.length && d["hp"].is_a?(Array) && d["hp"].length == @hn
        host_party = d["hp"].map { |h| load_mon(h) }
        return false if host_party.include?(nil)
        host = trainer_from(d["ht"]) or return false
        host.trainer_type = Mon.partner_type(d["ht"]["ty"])
        host.party = host_party
        host.define_singleton_method(:full_name) { name }
        @view.make_scene if @view.respond_to?(:make_scene)
        m = PokeBattle_Battle.new(@view.scene, @party, host_party, [@trainer], [host])
        m.party1starts = [0]
        m.party2starts = [0]
        m.instance_variable_set(:@sideSizes, sz)
        m.backdrop = d["bd"] if d["bd"].is_a?(String) && d["bd"] =~ /\A[A-Za-z0-9_ ]{1,40}\z/
        m.backdrop = "Field" if m.backdrop.to_s.empty?
        m.backdropBase = d["bb"] if d["bb"].is_a?(String) && d["bb"] =~ /\A[A-Za-z0-9_ ]{1,40}\z/
        env = Mon.sym(d["env"], GameData::Environment)
        m.environment = env if env
        m.time = int(d["tm"], 0, 2, 0)
        m.internalBattle = true
        m.canLose = true
        m.canRun = false
        m.moneyGain = false
        m.expGain = false
        @bgm = battle_bgm(d["bgm"])
        @mirror = m
        return false unless d["bt"].is_a?(Array)
        d["bt"].each do |e|
          next unless e.is_a?(Array) && e.length == 2
          mi = bat_checked(e[0]) or next
          mp = party_index(e[1], mi % 2) or next
          pk = m.pbParty(mi)[mp]
          next unless pk && !pk.egg? && m.battlers[mi].nil?
          m.pbCreateBattler(mi, pk, mp)
        end
        return false unless m.battlers[0] && own?(m.battlers[0].pokemonIndex)
        m.battlers.each { |b| m.pbSetSeen(b) if b && b.opposes? }
        return true
      rescue StandardError => e
        KIF::Coop.log("match setup failed (#{e.class}: #{e.message})")
        return false
      end

      # [index, hp, total, status, level] from the host, for every battler: the host's numbers decide (its modes, its rules)
      def apply_snap(snap)
        return unless snap.is_a?(Array) && @mirror
        snap.each do |e|
          next unless e.is_a?(Array) && e.length >= 5
          b = battler(e[0]) or next
          pk = b.pokemon or next
          th = int(e[2], 1, 99_999, b.totalhp)
          hp = int(e[1], 0, th) or next
          [b, pk].each { |o| o.instance_variable_set(:@totalhp, th) }
          lv = int(e[4], 1, GameData::GrowthRate.max_level)
          b.instance_variable_set(:@level, lv) if lv
          st = hp > 0 ? (Mon.sym(e[3], GameData::Status) || :NONE) : :NONE
          [b, pk].each { |o| o.instance_variable_set(:@hp, hp); o.instance_variable_set(:@status, st) }
        end
      end

      # a sendout entry [host index, host party index, shown Pokemon]: this player's own copy, or the host's as shown
      def send_in(e)
        return nil unless e.is_a?(Array) && e.length >= 3
        mi = bat_checked(e[0]) or return nil
        mp = party_index(e[1], mi % 2) or return nil
        pk = mi.even? ? @party[mp] : load_mon(e[2])
        return nil unless pk && !pk.egg?
        @mirror.pbParty(mi)[mp] = pk
        if @mirror.battlers[mi]
          @mirror.battlers[mi].pbInitialize(pk, mp)
        else
          @mirror.pbCreateBattler(mi, pk, mp)
        end
        return [mi, pk]
      end

      # the host's decision, as this player sees it (1 and 2 swap); nothing is applied to anything
      def finish(d)
        @done = true
        d = {} unless d.is_a?(Hash)
        dc = int(d["dc"], 0, 5, 0)
        @decision = { 1 => 2, 2 => 1, 5 => 5 }[dc] || 0
        KIF::Coop.log("#{@host_name}'s match #{@id} over (#{d['x'] ? Mon.name(d['x']) : dc})")
        @forfeit = d["f"] == 1 && @decision == 2
        if d["x"] || !@begun
          @aborted = true
          @forfeit = false
          @decision = 0
          KIF::Coop.tell(:party, _INTL("{1}'s game didn't take your team: it has a move, ability or item that game doesn't have (a mod's, or another KIF's), or the match didn't fit.", @host_name)) if d["x"] == "party"
        end
      end

      def after_battle
        pbMessage(_INTL("You did not choose for {1} turns. You forfeit the match.", PvP::SILENT_FORFEIT)) if @forfeit
        PvP.result(@decision.to_i, @host_name)
      end
    end

    #---------------------------------------------------------------------------
    # The battle screen of the other player. The host words its lines from its own side; here this player's Pokemon
    # are "the opposing X" there and the host's are plain: swapped back, with "your team" / "the opposing team".
    #---------------------------------------------------------------------------
    class View < KIF::Coop::SceneView
      def mine(t)
        t = Mon.text(t)
        m = @g.mirror or return t
        me = m.player[0].name.to_s
        host = m.opponent[0].name.to_s
        own = m.pbParty(0).compact.map { |p| p.name.to_s }.reject(&:empty?)
        hon = m.pbParty(1).compact.map { |p| p.name.to_s }.reject(&:empty?)
        act = [0, 1].map { |s| m.battlers.select { |b| b && b.index % 2 == s }.map { |b| b.name.to_s } }
        table = swaps(me, host, own, hon, act)
        lines = t.split("\n", -1)
        return lines.map { |l| table[l] || generic(l, own, hon) }.join("\n")
      rescue StandardError => e
        KIF::Coop.log("line not reworded (#{e.class}: #{e.message})") unless @warned_mine
        @warned_mine = true
        return Mon.text(t)
      end

      # whole lines the host says about the two trainers, as this player's game says them
      def swaps(me, host, own, hon, act)
        t = {}
        t[_INTL("You are challenged by {1}!", me)] = _INTL("You are challenged by {1}!", host)
        own.each do |x|
          t[_INTL("{1} withdrew {2}!", me, x)] = _INTL("{1}, come back!", x)
          t[_INTL("{1} sent out {2}!", me, x)] = _INTL("Go! {1}!", x)
        end
        hon.each do |x|
          t[_INTL("Go! {1}!", x)] = _INTL("{1} sent out {2}!", host, x)
          [_INTL("Good job, {1}! Come back!", x), _INTL("OK, {1}! Come back!", x), _INTL("{1}, that's enough! Come back!", x),
           _INTL("{1}, come back!", x), _INTL("{1}, switch out! Come back!", x)].each { |l| t[l] = _INTL("{1} withdrew {2}!", host, x) }
          [_INTL("You're in charge, {1}!", x), _INTL("Go for it, {1}!", x), _INTL("Just a little more! Hang in there, {1}!", x),
           _INTL("Your opponent's weak! Get 'em, {1}!", x)].each { |l| t[l] = _INTL("{1} sent out {2}!", host, x) }
        end
        # the start: all of one side's Pokemon at once
        a, h = act
        t[send_line(me, a)] = go_line(a) if a.length > 1
        t[go_line(h)] = send_line(host, h) if h.length > 1
        return t
      end

      def send_line(who, names)
        return _INTL("{1} sent out {2}!", who, names[0]) if names.length == 1
        return _INTL("{1} sent out {2} and {3}!", who, names[0], names[1]) if names.length == 2
        return _INTL("{1} sent out {2}, {3} and {4}!", who, names[0], names[1], names[2])
      end

      def go_line(names)
        return _INTL("Go! {1}!", names[0]) if names.length == 1
        return _INTL("Go! {1} and {2}!", names[0], names[1]) if names.length == 2
        return _INTL("Go! {1}, {2} and {3}!", names[0], names[1], names[2])
      end

      # "The opposing X" is this player's X; a host Pokemon's plain name gets "the opposing"; the teams swap
      def generic(l, own, hon)
        keep = []
        own.uniq.sort_by { |x| -x.length }.each do |x|
          l = l.gsub(/[Tt]he opposing #{Regexp.escape(x)}(?![[:alnum:]])/) { keep << x; "\u0001#{keep.length - 1}\u0002" }
        end
        hon.uniq.sort_by { |x| -x.length }.each do |x|
          l = l.gsub(/(?<![[:alnum:]\u0001])#{Regexp.escape(x)}(?![[:alnum:]\u0002])/) do
            at = $~.begin(0)
            (at == 0 || l[0, at] =~ /[.!?] \z/ ? _INTL("The opposing {1}", x) : _INTL("the opposing {1}", x))
          end
        end
        l = l.gsub(/\u0001(\d+)\u0002/) { keep[$1.to_i] }
        your, theirs = _INTL("your team"), _INTL("the opposing team")
        return l.gsub(/#{Regexp.escape(your)}|#{Regexp.escape(theirs)}|#{Regexp.escape(your.capitalize)}|#{Regexp.escape(theirs.capitalize)}/) do |w|
          sw = w.downcase == your ? theirs : your
          w[0] == w[0].upcase ? sw.capitalize : sw
        end
      end

      def show(ev)
        type, args = ev
        return if %w[tw ws].include?(type)   # the host's win fanfare: this player's result is its own
        ev = [type, [args[0] ^ 1] + args[1..-1], ev[2]] if type == "pl" && args.is_a?(Array) && args[0].is_a?(Integer)   # (the lineups' sides swap)
        return super(ev)
      end

      def bag(_mi, _b)
        call(:pbDisplayPausedMessage, _INTL("Items can't be used in this battle."))
        return nil
      end

      def run_choice(_m, _req)
        return confirm(_INTL("Would you like to forfeit the match and quit now?")) == true ? { "a" => "forfeit" } : nil
      end
    end
  end
end

# The base PokemonSelection.choose builds its rules without its acceptFainted argument, so a party with fainted
# Pokemon had too few to pick from and the pick ended at once (a silent No). The match pick asks for them
# (PvP.pick_team sets the flag for its own call only).
module PokemonSelection
  module KifPvpFainted
    def rules(min = 1, max = 6, canCancel = false, acceptFainted = false)
      return super(min, max, canCancel, acceptFainted || KIF::PvP.pick_fainted)
    end
  end
  singleton_class.prepend(KifPvpFainted) unless singleton_class.include?(KifPvpFainted)
end

# no autosave while a match runs on this game (a win autosaves in a normal trainer battle)
module Kernel
  class << self
    alias kif_pvp_tryAutosave tryAutosave unless method_defined?(:kif_pvp_tryAutosave)

    def tryAutosave(*args)
      return if KIF::PvP.running?
      return kif_pvp_tryAutosave(*args)
    end
  end
end

Events.onMapUpdate += proc { |_sender, _e|
  if KIF::Net.session
    begin
      KIF::PvP.map_tick
    rescue StandardError => e
      KIF::PvP.log("map step failed (#{e.class}: #{e.message})")
    end
  end
}
