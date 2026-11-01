#===============================================================================
# F-NET-01 – Multiplayer: co-op battles, the game that runs the battle
# (see NetCoop.rb)
#
# A battle that starts here while Fight together is on asks the partner
# (co_ask). If their game joins, the partner's party (rebuilt from checked
# fields) becomes PIF's partner trainer for this battle only
# ($PokemonGlobal.partner, as in PIF's story partner battles) and the battle
# is a double: 2v1 against one wild Pokémon or a trainer with one, 2v2
# otherwise (a trainer sends out two at once). The battle runs here as usual,
# with these additions while it lasts:
#   * the partner's battler is commanded by the partner (co_cmd / co_act),
#     sent its replacement (co_sw / co_swr); a choice that doesn't fit, no
#     answer in time (B stops waiting) or a lost connection: PIF's AI picks;
#   * what the battle scene shows goes to the partner as a log (co_ev);
#   * foes the partner's Pokémon fought are noted for its Exp (its own game
#     works the Exp out, with its own options); a Pokémon the partner's ball
#     caught goes to the partner, not here; items it used come off its Bag;
#   * PIF heals both teams after a partner battle; a co-op battle doesn't;
#   * the partner's ball is thrown in its own name; when both players throw,
#     this game's player throws first and a catch gives the partner's ball
#     back unused; a ball holds the other player's attack on that Pokémon
#     that turn (Co-op: hold attacks for a ball, the Multiplayer host's);
#   * in a wild battle a player who runs leaves alone while the other can
#     fight on: their Pokémon go back, the other finishes the battle;
#   * either player can change their pick until both have picked (B while
#     waiting), and each sees the other's pick in the battle menus;
#   * a player whose Pokémon all fainted blacks out after the battle even
#     when the other player won it.
# Exp is the partner's at the end of the battle; levels gained show then.
#===============================================================================
module KIF
  module Coop
    @hosting = false
    @pending_host = nil

    class << self
      attr_reader :pending_host
    end

    def self.hosting?; @hosting; end

    # this co-op battle: the partner's ball caught and this player's didn't
    def self.partner_caught_alone?
      h = @battle_host
      return h && !h.caught.empty? && !h.own_catch ? true : false
    end

    # this co-op battle: this player ran away and left the partner fighting
    def self.left_alone?; (h = @battle_host) && h.left?(0) ? true : false; end

    # a battle starting here may ask the partner
    def self.may_host?
      return false unless on? && !@hosting && !@guest
      return false if $PokemonGlobal.nil? || $PokemonGlobal.partner
      r = $PokemonTemp.battleRules
      return false if r["noPartner"] || r["birdboss"]
      return false if r["size"] && !%w[double 2v2 2v1].include?(r["size"])
      return false if (pbInSafari? rescue false) || (pbInBugContest? rescue false)
      return false if defined?(KIF::SelfBattle) && KIF::SelfBattle.instance_variable_get(:@active)
      return false if defined?(KIF::Endgame) && KIF::Endgame.challenge_map?   # the challenge maps are 1v1
      return false if ($Trainer.able_pokemon_count rescue 0) == 0
      return false if ($game_switches[SWITCH_TRIPLE_BOSS_BATTLE] rescue false)
      return true
    end

    # wild Pokémon in pbWildBattleCore's arguments
    def self.count_wild(args)
      n = 0
      half = false
      args.each do |a|
        if a.is_a?(Pokemon) || a.is_a?(Array) then n += 1
        elsif half then n += 1; half = false
        else half = true
        end
      end
      return n
    end

    # a random wild encounter while fighting together on one map: two foes (2v2)
    def self.co_double?
      return false unless may_host? && @their_map && $game_map && @their_map == $game_map.map_id
      return !(pbInSafari? rescue false) && !$PokemonTemp.forceSingleBattle
    end

    def self.host_battle(kind, nfoes)
      join = invite(kind)
      @host_id = nil unless join
      if !join && kind == :wild && nfoes == 2 && ($Trainer.able_pokemon_count rescue 2) <= 1 && !$PokemonTemp.battleRules["size"]
        setBattleRule("1v2")   # two foes for a pair, the partner didn't come: one Pokémon here
      end
      return yield unless join
      s = session
      return yield unless s
      @hosting = true
      host = Host.new(s, join)
      old = $PokemonGlobal.partner
      if !$PokemonTemp.battleRules["size"] && (kind == :trainer || nfoes == 1)
        setBattleRule("2v1")   # room for the partner; 2v2 once a trainer's party is known
        host.mine_size = true
      end
      $PokemonGlobal.partner = [join[:type], join[:name], join[:tid], join[:party]]
      @pending_host = host
      @battle_host = host
      log("battle #{join[:id]} with #{join[:name]} (#{kind})")
      begin
        return with_rules { KIF::Teams.with_mult(2) { yield } }   # the wild Pokémon or trainer team is made inside: with the host's settings; 2 players (3 once the lobby takes a third)
      ensure
        $PokemonGlobal.partner = old
        @pending_host = @battle_host = @host_id = nil
        @hosting = false
        (host.finish(0, "abort") rescue nil)
      end
    end

    # pbPrepareBattle: the battle exists; the partner is in it if PIF added them
    def self.prepare(battle)
      h = @pending_host or return
      @pending_host = nil
      return unless battle.player && battle.player.length == 2 && battle.pbPartyStarts(0).length == 2
      if h.mine_size
        foes = battle.pbParty(1).count { |p| p && p.able? }
        battle.setBattleMode(battle.trainerBattle? && foes >= 2 ? "double" : "2v1")
      end
      # the partner is named plainly ("Monto sent out ..."), not with a trainer class
      ally = battle.player[1]
      ally.define_singleton_method(:full_name) { name } if ally
      h.attach(battle)
    end

    #---------------------------------------------------------------------------
    # One co-op battle, on the game that runs it
    #---------------------------------------------------------------------------
    class Host
      attr_reader :id, :name, :battle, :lost, :kills, :caught, :items
      BEAT = 15.0   # seconds of quiet on the line before beat_start's thread says "still here"
      attr_accessor :mine_size, :own_catch

      def initialize(session, join)
        @s = session
        @join = join
        @id = join[:id]
        @name = join[:name]
        @buf = []
        @quiet = 0
        @kills = []
        @caught = []
        @items = Hash.new(0)
        @pending = {}
        @answers = {}
        @turn = 0
        @swn = 0
        @lost = false
        @done = false
        @left = {}       # owner (0 this player, 1 the partner) => true: ran away alone
        @thrown = []     # this turn's balls: [owner, target index or nil]
        @thrower = nil
        @mute = 0
        @bag = join[:bag].is_a?(Hash) ? join[:bag] : {}   # the battle items the partner listed when it joined: no others
        @silent = 0      # turns in a row the partner gave no answer
        @tx_at = KIF::Net.now   # when this game last sent the partner a co_ frame
      end

      # The partner's game leaves a battle whose host says nothing for 90 s. This game's own screens (a nickname, a move
      # to forget, the Bag, the end of the battle) neither read the line nor send anything, so a thread says "still
      # here" meanwhile (a co_int, as while this player chooses). It only queues a frame; no game object is touched.
      def beat_start
        @beat = Thread.new do
          until @done || @lost
            sleep 1
            next if KIF::Net.now - @tx_at.to_f < BEAT
            begin
              @s.post("co_int", "id" => @id, "d" => { "t" => @int_t.to_i, "it" => @int_it.to_s })
              @tx_at = KIF::Net.now
            rescue StandardError
              nil
            end
          end
        end
        @beat.report_on_exception = false
      end

      def attach(battle)
        beat_start
        @battle = battle
        battle.instance_variable_set(:@kif_coop, self)
        sc = battle.scene
        sc.extend(KIF::Coop::Capture)
        sc.extend(KIF::Coop::IntentShow)
        sc.instance_variable_set(:@kif_coop, self)
      end

      def owner(i); @battle.pbGetOwnerIndexFromBattlerIndex(i); end
      def owner_name(o); o == 0 ? @battle.pbPlayer.name.to_s : @name; end

      #-------------------------------------------------------------------------
      # Names: the partner's ball is thrown in the partner's name
      #-------------------------------------------------------------------------
      def throwing(name)
        old = @thrower
        @thrower = name
        return yield
      ensure
        @thrower = old
      end

      # a line the battle says in this player's name while the partner throws
      def named(t)
        return t unless @thrower && t.is_a?(String)
        me = @battle.pbPlayer.name.to_s
        return t.start_with?(me + " ") ? @thrower + t[me.length..-1] : t
      end

      # nothing shown on either screen (the lines are said again, worded for both)
      def muted
        @mute += 1
        return yield
      ensure
        @mute -= 1
      end

      def muted?; @mute > 0; end

      def start; @battle.pbPartyStarts(0)[1]; end
      def guest_party; @battle.pbParty(0)[start..-1] || []; end
      def slot?(abs); abs.is_a?(Integer) && abs >= start && abs < @battle.pbParty(0).length; end

      def guest?(idx)
        return false unless idx.is_a?(Integer) && @battle && @battle.battlers[idx] && !@battle.opposes?(idx)
        return @battle.pbGetOwnerIndexFromBattlerIndex(idx) == 1
      end

      def quiet?; @quiet > 0; end

      def quietly
        @quiet += 1
        return yield
      ensure
        @quiet -= 1
      end

      def post(type, fields)
        return false unless connected?
        @tx_at = KIF::Net.now
        @s.post(type, fields.merge("id" => @id))
      end

      def connected?
        return false if @lost
        return true if @s.connected?
        lose
        return false
      end

      def lose
        return if @lost
        @lost = true
        KIF::Coop.log("lost #{@name} during the battle")
        return unless @battle && !@done
        quietly { @battle.pbDisplayPaused(_INTL("Lost the connection to {1}. The game fights for {1}'s Pokémon now.", @name)) }
      rescue StandardError
        nil
      end

      #-------------------------------------------------------------------------
      # The log
      #-------------------------------------------------------------------------
      # [index, hp, total hp, status, level] of every battler
      def snap
        @battle.battlers.each_with_index.map { |b, i| b ? [i, b.hp, b.totalhp, b.status.to_s, b.level] : nil }.compact
      end

      def push(type, args)
        return if @lost || @done
        last = @buf.last
        if type == "r1" && last && last[0] == "r1" && last[1] == args
          last[2] = snap   # the same box drawn again
          return
        end
        @buf << [type, args, snap]
        # HP changes and faints go at once too: after a hit with no message the partner's bar waited for the next one (K6)
        flush if %w[m mp hl hp fa].include?(type) || @buf.length >= 24
      end

      def flush
        KIF::Net.update if KIF::Net.session.equal?(@s)   # notices a closed line
        return if @buf.empty?
        post("co_ev", "e" => @buf) if connected?
        @buf = []
      end

      def disp(p); p ? KIF::Coop::Mon.dump(p) : nil; end

      # a trainer battle an event started here: [map id, event id], or nil
      def trainer_event
        return nil unless @battle.trainerBattle? && $game_map
        i = (pbMapInterpreter rescue nil)
        ev = i && i.running? ? i.instance_variable_get(:@event_id).to_i : 0
        return ev > 0 ? [$game_map.map_id, ev] : nil
      end

      def trainer_h(t); { "n" => t.name.to_s[0, 24], "ty" => t.trainer_type.to_s[0, 48] }; end

      # the battle scene starts: everything the partner's game needs to show it
      def begin_battle
        b = @battle
        d = { "w" => b.wildBattle? ? 1 : 0, "sz" => [b.pbSideSize(0), b.pbSideSize(1)],
              "env" => b.environment.to_s, "bd" => b.backdrop.to_s, "bb" => b.backdropBase.to_s, "tm" => b.time.to_i,
              "ht" => trainer_h(b.player[0]), "hp" => b.pbParty(0)[0...start].map { |p| disp(p) },
              "gs" => start, "gn" => guest_party.length,
              "ft" => (b.opponent || []).map { |t| trainer_h(t) }, "fp" => b.pbParty(1).map { |p| disp(p) },
              "fs" => b.pbPartyStarts(1),
              "bt" => b.battlers.each_with_index.map { |x, i| x ? [i, x.pokemonIndex] : nil }.compact,
              "cl" => b.canLose ? 1 : 0, "cr" => b.canRun ? 1 : 0, "mg" => b.moneyGain ? 1 : 0, "eg" => b.expGain ? 1 : 0 }
        d["lo"] = 1 if guest_party.any? { |p| p&.instance_variable_get(:@kif_coop_lost) }   # the partner is told why
        m = ($game_system.getPlayingBGM rescue nil)   # the battle's music (gym leader, rival...), for the partner's game
        d["bgm"] = [m.name.to_s[0, 80], m.volume.to_i, m.pitch.to_i] if m && !m.name.to_s.empty?
        ev = trainer_event
        d["tev"] = ev if ev
        post("co_begin", "d" => d)
      end

      #-------------------------------------------------------------------------
      # Waiting for the partner: the battle scene keeps moving
      #-------------------------------------------------------------------------
      def frame
        sc = @battle.scene
        if sc.class.method_defined?(:pbUpdate)
          sc.pbUpdate
        else
          Graphics.update
          Input.update
        end
      rescue StandardError
        Graphics.update
        Input.update
      end

      WHY = { back: "B pressed", time: "time up", lost: "connection lost" }

      # true once the block is; else why not: :back (B, then let the game
      # choose), :change (B, then change this player's pick), :time or :lost
      def wait(secs, change = false, &blk)
        return wait_inner(secs, change, &blk)
      ensure
        hint_done
      end

      def wait_inner(secs, change)
        t0 = KIF::Net.now
        shown = nil   # when the hint went up
        left = nil
        loop do
          KIF::Net.update if KIF::Net.session.equal?(@s)
          return true if yield
          return :lost unless connected?
          now = KIF::Net.now
          return :time if now - t0 > secs
          if now - t0 > 0.3 && left != (secs - (now - t0)).ceil
            left = (secs - (now - t0)).ceil
            hint(wait_text(left, change), shown)
            shown ||= now
          end
          frame
          # B counts once the hint has been up 1 s (a B for this player's own menu doesn't carry over)
          next unless shown && now - shown >= 1.0 && !left?(0) && Input.trigger?(Input::BACK)   # nothing to pick for a side that left
          case waiting_choice(change)
          when :let
            KIF::Net.update if KIF::Net.session.equal?(@s)
            return yield ? true : :back   # their choice came while the question was up: it's used
          when :change
            return :change
          end
          left = shown = nil   # the hint again
        end
      end

      # the hint; then only its text changes, once a second (no retyping)
      def hint(text, again)
        w = again && (@battle.scene.instance_variable_get(:@sprites) rescue nil)&.[]("messageWindow")
        # the window stays out of letter-by-letter mode until the wait ends:
        # turned back on at once, it drew nothing new and "(90 s)" stayed up
        if w.respond_to?(:letterbyletter=) && w.respond_to?(:text=)
          @hint_win ||= [w, w.letterbyletter]
          w.letterbyletter = false
          w.text = text
        else
          (quietly { @battle.pbDisplayBrief(text) } rescue nil)
        end
      end

      def hint_done
        w, lbl = @hint_win
        @hint_win = nil
        w.letterbyletter = lbl if w && !(w.disposed? rescue true)
      end

      # B while waiting: :let (the game chooses for the partner), :change (this
      # player picks again) or nil (wait on); the cursor starts on waiting on
      def waiting_choice(change)
        sc = @battle.scene
        # EBDX draws the box under its data boxes: they step aside while it's up
        hide = sc.respond_to?(:pbHideAllDataboxes) && !sc.instance_variable_get(:@dataBoxesHidden)
        sc.pbHideAllDataboxes if hide
        q = _INTL("Waiting for {1}.", @name)
        cmds = [[nil, _INTL("Keep waiting")]]
        cmds << [:change, _INTL("Change my choice")] if change
        cmds << [:let, _INTL("Let the game choose for {1}", @name)]
        i = (quietly { sc.pbShowCommands(q, cmds.map(&:last), 0) } rescue 0)
        return i.is_a?(Integer) && i >= 0 && cmds[i] ? cmds[i][0] : nil
      ensure
        (sc.pbShowAllDataboxes rescue nil) if hide
      end

      def back_name; KIF::Coop.back_name; end

      def wait_text(left, change = false)
        return _INTL("You got away. {1} is finishing the battle.", @name) if left?(0)
        # (short: the second line fits PIF's message box)
        return _INTL("Waiting for {1} to choose... ({2} s)\n{3}: change or let the game pick", @name, left, back_name) if change
        _INTL("Waiting for {1} to choose... ({2} s)\n{3}: let the game pick", @name, left, back_name)
      end

      # the partner's game is told it was chosen for (its menu closes); the reason is logged
      def gave_up(why, what, d)
        KIF::Coop.log("no choice from #{@name} for #{what} (#{WHY[why]})")
        post("co_skip", "d" => d) if why != :lost
      end

      # a partner that never answers (a connected game that only keeps the line alive): after two
      # waits in a row the game fights for it for the rest of the battle instead of waiting 90 s a turn
      def silent(why)
        return @silent = 0 if why == true
        return if why == :lost || why == :change
        @silent += 1
        return if @silent < 2 || @auto
        @auto = true
        KIF::Coop.log("#{@name} gave no answer twice in a row: the game fights for them now")
        (quietly { @battle.pbDisplayPaused(_INTL("{1} is not answering. The game fights for {1}'s Pokemon now.", @name)) } rescue nil)
      end

      #-------------------------------------------------------------------------
      # Turns
      #-------------------------------------------------------------------------
      def order
        o = @battle.pbPartyOrder(0)
        return guest_party.each_index.map { |j| (o[start + j] || start + j) - start }
      end

      def party_state
        guest_party.map { |p| p ? [p.hp, p.status.to_s] : nil }
      end

      def request(i)
        b = @battle.battlers[i]
        mv = b.moves.each_with_index.map do |m, j|
          [m.id.to_s, m.pp.to_i, m.total_pp.to_i, @battle.pbCanChooseMove?(i, j, false) ? 1 : 0]
        end
        return { "b" => i, "t" => @turn, "mv" => mv, "fa" => @battle.pbCanShowFightMenu?(i) ? 0 : 1,
                 "sw" => @battle.pbCanSwitch?(i) ? 1 : 0, "rn" => (@battle.wildBattle? && @battle.pbCanRun?(i)) ? 1 : 0,
                 "ord" => order, "pt" => party_state }
      end

      # the command phase starts: the partner chooses while this player does
      def ask_commands
        @pending = {}
        @answers = {}
        return unless connected? && !@auto
        @turn += 1
        @int_at = KIF::Net.now
        @battle.battlers.each_with_index do |b, i|
          next unless b && guest?(i)
          next unless @battle.choices[i][0] == :None && @battle.pbCanShowCommands?(i)
          @pending[i] = @turn
          flush
          post("co_cmd", "d" => request(i))
        end
      end

      def collect
        while (r = KIF::Coop.take_host(@id, ["co_act", "co_undo"]))
          d = r[1]["d"]
          if d["b"] == -1 && d["a"] == "auto"
            @auto = true   # the partner's game can't show the battle: the AI fights for it
            next
          end
          next unless @pending[d["b"]] && d["t"] == @pending[d["b"]]
          r[0] == "co_undo" ? @answers.delete(d["b"]) : @answers[d["b"]] = d   # a new pick replaces the old one
        end
        return @auto || @pending.keys.all? { |i| @answers[i] }
      end

      # the partner's pick this turn for this player's battle menus: its text,
      # "" (not chosen yet) or nil (nothing asked of the partner)
      def partner_intent
        return nil if @pending.empty? || @auto || @lost || @done
        send_intent if @battle && KIF::Net.now - (@int_at ||= KIF::Net.now) > 15   # also tells the partner this game is still here (its watchdog)
        KIF::Net.update if KIF::Net.session.equal?(@s)   # this player's own menu doesn't read the line
        it = nil
        @pending.each_key { |i| it = @answers[i] && @answers[i]["it"] }
        KIF::Coop.host_box.each do |t, m|   # not taken yet: the newest says
          d = m["d"]
          next unless %w[co_act co_undo].include?(t) && m["id"] == @id && d.is_a?(Hash) && @pending[d["b"]] && d["t"] == @pending[d["b"]]
          it = t == "co_act" ? d["it"] : nil
        end
        return KIF::Coop.intent_line(@name, it.is_a?(String) ? it : "")
      end

      # this player's picks, for the partner's menus ("" while choosing again)
      def send_intent(clear = false)
        return if @pending.empty? || !connected? || @auto
        it = ""
        unless clear
          @battle.battlers.each_with_index do |b, i|
            next unless b && !@battle.opposes?(i) && owner(i) == 0
            t = KIF::Coop.intent_text(@battle, i)
            it = t if t
          end
        end
        @int_at = KIF::Net.now
        @int_t, @int_it = @turn, it.to_s[0, 60]
        post("co_int", "d" => { "t" => @int_t, "it" => @int_it })
      end

      # this player's battlers that picked something it can take back
      def can_change?
        return @battle.battlers.each_with_index.any? do |b, i|
          b && !@battle.opposes?(i) && owner(i) == 0 && !b.fainted? && @battle.choices[i] && @battle.pbCanShowCommands?(i) &&
            ![:None, :Run].include?(@battle.choices[i][0])
        end
      end

      # this player picks again (B while waiting): the picks go back, the menus open again
      def change_picks
        @battle.battlers.each_with_index do |b, i|
          next unless b && !@battle.opposes?(i) && owner(i) == 0 && @battle.choices[i] && @battle.choices[i][0] != :None
          next unless @battle.pbCanShowCommands?(i)   # a move locked in from last turn (Outrage, Fly, Hyper Beam) was not picked now: it stays
          @battle.pbCancelChoice(i)
        end
        send_intent(true)
        @battle.kif_coop_pbCommandPhaseLoop(true)
      end

      # before the AI chooses: the partner's choices, or none (the AI picks)
      def take_commands
        return if @pending.empty?
        if connected? && !@auto
          flush
          send_intent
          why = nil
          loop do
            why = wait(KIF::Coop.cmd_wait, can_change?) { collect }
            break unless why == :change
            change_picks
            break if @battle.decision != 0
            send_intent
          end
          if why != true
            @pending.each_key { |i| gave_up(why, "turn #{@turn}", { "b" => i, "t" => @pending[i] }) unless @answers[i] || why == :change }
          end
          silent(why)
          # the partner's menu can't take its pick back from here on
          @pending.each_key { |i| post("co_lock", "d" => { "b" => i, "t" => @pending[i] }) if @answers[i] }
        end
        @pending.each_key do |i|
          a = @answers[i]
          next unless a
          ok = begin
                 apply(i, a)
               rescue StandardError => e
                 KIF::Coop.log("#{@name}'s choice failed (#{e.class}: #{e.message})")
                 false
               end
          @battle.pbClearChoice(i) unless ok || @battle.choices[i][0] == :None
          break if @battle.decision != 0
        end
        @pending = {}
      end

      def int(v, lo, hi, d = nil); KIF::Coop::Mon.int(v, lo, hi, d); end

      # a number from the partner in range, else nil (nothing is clamped into a valid pick)
      def pick(v, lo, hi); (v.is_a?(Integer) && v.between?(lo, hi)) ? v : nil; end

      # a choice from the partner, checked like the player's own; false: the AI picks
      def apply(i, a)
        b = @battle.battlers[i]
        case a["a"]
        when "move"
          m = pick(a["m"], -1, 3) or return false
          return @battle.pbAutoChooseMove(i, false) if m < 0 || !@battle.pbCanShowFightMenu?(i)
          return false unless b.moves[m] && b.moves[m].id && @battle.pbRegisterMove(i, m, false)
          t = a["tg"]
          if t.is_a?(Integer) && t >= 0 && t < @battle.battlers.length && @battle.battlers[t] &&
             @battle.pbMoveCanTarget?(i, t, b.moves[m].pbTarget(b))
            @battle.pbRegisterTarget(i, t)
          end
          return true
        when "switch"
          p = pick(a["p"], 0, 5)
          return false unless p && slot?(start + p)
          return @battle.pbRegisterSwitch(i, start + p)
        when "item" then return apply_item(i, b, a)
        when "run"
          return false unless @battle.wildBattle?
          r = @battle.pbRun(i)
          @battle.choices[i][0] = :Run if r < 0   # didn't get away: the turn is used, as the player's is
          return r != 0
        end
        return false
      end

      # items that end the whole battle (it is the host's too): a partner leaves with a run
      FLEE_ITEMS = %i[POKEDOLL FLUFFYTAIL POKETOY]

      def apply_item(i, b, a)
        it = KIF::Coop::Mon.sym(a["i"], GameData::Item) or return false
        return false if FLEE_ITEMS.include?(it)
        return false unless @bag[it].to_i - @items[it].to_i > 0   # only what the partner listed at join (this game never sees its Bag)
        use = GameData::Item.get(it).battle_use.to_i
        mv = a.key?("mv") ? pick(a["mv"], -1, 3) : -1
        return false unless mv
        case use
        when 1, 2, 3, 6, 7, 8
          p = pick(a["p"], 0, 5)
          return false unless p && slot?(start + p)
          abs = start + p
          bt = @battle.pbFindBattler(abs, i)
          if [3, 8].include?(use)
            return false unless bt && ItemHandlers.hasBattleUseOnBattler(it)
            pk = bt.pokemon
          else
            return false unless ItemHandlers.hasBattleUseOnPokemon(it)
            pk = @battle.pbParty(i)[abs]
          end
          return false unless pk && @battle.pbCanUseItemOnPokemon?(it, pk, bt, @battle.scene, false)
          return false unless ItemHandlers.triggerCanUseInBattle(it, pk, bt, mv, true, @battle, @battle.scene, false)
          return @battle.pbRegisterItem(i, it, abs, mv)
        when 4, 9
          # its own game already checked the ball against its own rules (Nuzlocke, room in the PC)
          t = a["tb"]
          return false unless @battle.wildBattle? && t.is_a?(Integer) && @battle.battlers[t] && @battle.opposes?(t) && !@battle.battlers[t].fainted?
          return @battle.pbRegisterItem(i, it, t, -1)
        when 5, 10
          return false unless ItemHandlers.triggerCanUseInBattle(it, b.pokemon, b, -1, true, @battle, @battle.scene, false)
          return @battle.pbRegisterItem(i, it, i, -1)
        end
        return false
      end

      #-------------------------------------------------------------------------
      # Running from a wild battle: one player leaves, the other fights on
      #-------------------------------------------------------------------------
      def left?(o); @left[o] ? true : false; end
      def left_any?; !@left.empty?; end

      # able Pokémon of one player's team here
      def able_of(o)
        st = @battle.pbPartyStarts(0)
        party = @battle.pbParty(0)
        return (party[st[o]...(st[o + 1] || party.length)] || []).count { |p| p && p.able? }
      end

      # a run from battler i leaves only its player: a wild battle the other
      # player is still in (connected, with Pokémon that can fight)
      def may_leave?(i)
        return false unless @battle && @battle.wildBattle? && !@battle.opposes?(i) && !@done
        o = owner(i)
        return false if left?(o) || left?(1 - o)
        return false if o == 0 && (!connected? || @auto)   # nobody would play the partner's side
        return false if o == 1 && !connected?
        return able_of(1 - o) > 0
      end

      # i's player got away: their Pokémon go back (they keep their HP), the battle goes on
      def leave(i)
        o = owner(i)
        @left[o] = true
        @battle.instance_variable_set(:@decision, 0)
        KIF::Coop.log("#{o == 0 ? 'this player' : @name} ran from battle #{@id} alone")
        @battle.battlers.each do |b|
          next unless b && !@battle.opposes?(b.index) && owner(b.index) == o
          next if b.fainted?
          (@battle.scene.pbRecall(b.index) rescue nil)
          b.instance_variable_set(:@hp, 0)        # the battler only: the Pokémon keeps its HP
          b.instance_variable_set(:@fainted, true)
          @battle.pbClearChoice(b.index)
        end
        t = _INTL("{1} got away safely!", owner_name(o))
        o == 0 ? push("mp", [t]) : @battle.pbDisplayPaused(t)   # this player saw PIF's own line
        finish(3) if o == 1   # the partner's game ends its battle now, with what it had
      end

      #-------------------------------------------------------------------------
      # Balls: this player's first; a catch keeps the partner's; a ball holds
      # the other player's attack on that Pokémon this turn
      #-------------------------------------------------------------------------
      def ball_choice?(i)
        ch = @battle.choices[i]
        return ch && ch[0] == :UseItem && ch[1] && (GameData::Item.get(ch[1]).is_poke_ball? rescue false)
      end

      # the partner's balls when this player throws one too: [[index, choice]]
      def later_balls
        side = @battle.battlers.each_with_index.select { |b, i| b && !@battle.opposes?(i) && ball_choice?(i) }.map(&:last)
        return [] unless side.any? { |i| owner(i) == 0 } && side.any? { |i| owner(i) == 1 }
        return side.select { |i| owner(i) == 1 }.map { |i| [i, @battle.choices[i].dup] }
      end

      def ball_thrown(user, target)
        @thrown << [owner(user.index), target.is_a?(Integer) && target >= 0 && @battle.opposes?(target) ? target : nil]
      end

      def new_turn; @thrown = []; end

      # a ball the partner didn't need: back in its Bag (not counted as used)
      def ball_unused(i, ch, foe)
        @battle.pbReturnUnusedItemToBag(ch[1], i)
        it = GameData::Item.get(ch[1]).name
        @battle.pbDisplay(_INTL("{1} was already caught by {2}, so {3}'s {4} wasn't used.", foe, owner_name(0), @name, it))
      end

      # after the balls: the other player's attacks on a Pokémon a ball was thrown at wait
      def hold_attacks
        return if @thrown.empty? || KIF::Coop.rule(:kif_coop_hold) != 1
        @battle.battlers.each_with_index do |b, i|
          next unless b && !b.fainted? && !@battle.opposes?(i)
          next unless @battle.pbCanShowCommands?(i)   # a locked move (Outrage, Fly, Hyper Beam) can't be put off without losing it
          ch = @battle.choices[i]
          next unless ch && ch[0] == :UseMove && ch[2] && ch[2].damagingMove?
          t = ch[3].to_i
          th = @thrown.find { |o, ti| o != owner(i) && (ti.nil? || t < 0 || t == ti) } or next
          @battle.pbClearChoice(i)
          @battle.pbDisplay(_INTL("{1} held back its attack for {2}'s Poké Ball.", b.pbThis, owner_name(th[0])))
        end
      end

      # the partner's replacement (party index), -1 (cancelled) or nil (the AI picks)
      def choose_switch(idx, lax, cancel)
        return nil unless connected? && !@auto
        flush
        @swn += 1
        n = @swn
        post("co_sw", "d" => { "b" => idx, "n" => n, "c" => cancel ? 1 : 0, "ord" => order, "pt" => party_state })
        ans = nil
        got = wait(KIF::Coop.sw_wait) do
          while (r = KIF::Coop.take_host(@id, ["co_swr", "co_act"]))
            if r[0] == "co_act"
              @auto = true if r[1]["d"]["b"] == -1
              next
            end
            ans = r[1]["d"] if r[1]["d"]["n"] == n
          end
          ans || @auto
        end
        gave_up(got, "a replacement", { "b" => idx, "n" => n }) if got != true
        silent(got)
        return nil unless got == true && ans
        p = ans["p"]
        return -1 if cancel && p == -1
        return nil unless p.is_a?(Integer) && p >= 0 && slot?(start + p)
        abs = start + p
        ok = lax ? @battle.pbCanSwitchLax?(idx, abs) : @battle.pbCanSwitch?(idx, abs)
        return ok ? abs : nil
      end

      #-------------------------------------------------------------------------
      # Exp, catches, items
      #-------------------------------------------------------------------------
      # pbGainExp is about to pay out: note each defeated foe (the partner's
      # game pays its own Pokémon: participants, Exp Share, Exp All)
      def note_kills
        return unless @battle.internalBattle && @battle.expGain
        @battle.battlers.each do |b|
          next unless b && b.opposes? && b.pokemon && !b.participants.empty? && (b.fainted? || b.captured)
          # all of them, as host party indices: the partner's Exp Share needs a fought foe too
          @kills << { "s" => b.pokemon.species.to_s, "l" => b.level, "p" => b.participants.first(12), "m" => KIF::Teams.foe_mult(@battle, b) } if @kills.length < 60
        end
      end

      def caught_by_guest(list)
        @caught.concat(list)
        KIF::Coop.log("#{@name} caught #{list.map(&:name).join(', ')}") unless list.empty?
      end

      # consumed items the partner used (+1) or got back (-1)
      def item_used(item, n)
        use = GameData::Item.get(item).battle_use.to_i rescue 0
        @items[item] += n if use.between?(1, 5)
      end

      def finish(decision, why = nil)
        return if @done
        flush if @battle
        @done = true
        (@beat.kill rescue nil) if @beat
        d = { "dc" => decision.to_i }
        if @battle && !why
          d["cl"] = @battle.canLose ? 1 : 0
          d["pt"] = guest_party.map { |p| p ? [p.hp, p.status.to_s, p.statusCount.to_i, KIF::Coop::Mon.pp_list(p)] : nil }
          d["k"] = @kills
          d["c"] = @caught.first(6).map { |p| KIF::Coop::Mon.dump(p, true) }
          d["it"] = @items.select { |_k, v| v > 0 }.map { |k, v| [k.to_s, v] }
        end
        d["x"] = why if why
        post("co_end", "d" => d) if connected?
        KIF::Coop.log("battle #{@id} over (#{why || decision})")
      end
    end

    #---------------------------------------------------------------------------
    # The host's battle scene (this battle's object only): each thing it shows
    # goes into the log. Only the outermost call counts (sending out plays the
    # shiny animation itself), and nothing while the battle is quiet (this
    # player's Exp, money, catches, questions only this player answers).
    #---------------------------------------------------------------------------
    module Capture
      def kif_rec(always = false)
        c = @kif_coop
        return unless c && @kif_cap_depth.to_i == 0 && (always || !c.quiet?)
        ev = yield
        c.push(ev[0], ev[1]) if ev
      rescue StandardError => e
        KIF::Coop.log("log entry skipped (#{e.class}: #{e.message})")
      end

      def kif_in
        @kif_cap_depth = @kif_cap_depth.to_i + 1
        return yield
      ensure
        @kif_cap_depth -= 1
      end

      def kif_i(b); b.respond_to?(:index) ? b.index : (b.is_a?(Integer) ? b : -1); end
      def kif_t(m); KIF::Coop::Mon.text(m.to_s); end

      def pbStartBattle(*args, &blk)
        (@kif_coop.begin_battle rescue KIF::Coop.log("begin not sent (#{$!.class}: #{$!.message})")) if @kif_coop
        kif_in { super }
      end

      def pbDisplayMessage(*args, &blk)
        return if @kif_coop&.muted?
        args[0] = @kif_coop.named(args[0]) if @kif_coop
        kif_rec { ["m", [kif_t(args[0]), args[1] ? 1 : 0]] }
        kif_in { super }
      end

      def pbDisplayPausedMessage(*args, &blk)
        return if @kif_coop&.muted?
        args[0] = @kif_coop.named(args[0]) if @kif_coop
        kif_rec { ["mp", [kif_t(args[0])]] }
        kif_in { super }
      end

      def pbSendOutBattlers(*args, &blk)
        kif_rec do
          list = (args[0] || []).map do |i, pk|
            b = @battle.battlers[i]
            shown = (b.effects[PBEffects::Illusion] rescue nil) || pk
            [i, b.pokemonIndex, KIF::Coop::Mon.dump(shown)]
          end
          ["so", [list, args[1] ? 1 : 0]]
        end
        kif_in { super }
      end

      def pbRecall(*args, &blk)
        kif_rec { ["rc", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbHPChanged(*args, &blk)
        kif_rec { ["hp", [kif_i(args[0]), args[1].to_i, args[2] ? 1 : 0]] }
        kif_in { super }
      end

      def pbDamageAnimation(*args, &blk)
        kif_rec { ["da", [kif_i(args[0]), args[1].to_i]] }
        kif_in { super }
      end

      def pbHitAndHPLossAnimation(*args, &blk)
        kif_rec { ["hl", [(args[0] || []).map { |t| [kif_i(t[0]), t[1].to_i, t[2].to_i] }]] }
        kif_in { super }
      end

      def pbFaintBattler(*args, &blk)
        kif_rec { ["fa", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbAnimation(*args, &blk)
        kif_rec do
          t = args[2]
          t = [t] unless t.is_a?(Array)
          ["an", [args[0].to_s, kif_i(args[1]), t.compact.map { |x| kif_i(x) }, args[3].to_i]]
        end
        kif_in { super }
      end

      def pbCommonAnimation(*args, &blk)
        kif_rec do
          t = args[2].is_a?(Array) ? args[2][0] : args[2]
          ["ca", [args[0].to_s, args[1] ? kif_i(args[1]) : -1, t ? kif_i(t) : -1]]
        end
        kif_in { super }
      end

      def pbShowAbilitySplash(*args, &blk)
        kif_rec do
          name = args[1..-1].find { |a| a.is_a?(String) } || (args[0].abilityName rescue "")
          ["ab", [kif_i(args[0]), args[1] == true ? 1 : 0, name.to_s[0, 40]]]
        end
        kif_in { super }
      end

      def pbHideAbilitySplash(*args, &blk)
        kif_rec { ["abh", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbReplaceAbilitySplash(*args, &blk)
        kif_rec { ["ab", [kif_i(args[0]), 0, (args[0].abilityName rescue "").to_s[0, 40]]] }
        kif_in { super }
      end

      def pbChangePokemon(*args, &blk)
        kif_rec { ["ch", [kif_i(args[0]), KIF::Coop::Mon.dump(args[1])]] if args[1].is_a?(Pokemon) }
        kif_in { super }
      end

      def pbRefresh(*args, &blk)
        kif_rec { ["rf", []] }
        kif_in { super }
      end

      def pbRefreshOne(*args, &blk)
        kif_rec { ["r1", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbShowOpponent(*args, &blk)
        kif_rec { ["op", [args[0].to_i]] }
        kif_in { super }
      end

      def pbShowPartyLineup(*args, &blk)
        kif_rec { ["pl", [args[0].to_i, args[1] ? 1 : 0]] }
        kif_in { super }
      end

      def pbThrow(*args, &blk)
        kif_rec { ["th", [args[0].to_s, args[1].to_i, args[2] ? 1 : 0, kif_i(args[3]), args[4] ? 1 : 0]] }
        kif_in { super }
      end

      def pbThrowSuccess(*args, &blk)
        kif_rec { ["ts", []] }
        kif_in { super }
      end

      def pbHideCaptureBall(*args, &blk)
        kif_rec { ["hc", [kif_i(args[0])]] }
        kif_in { super }
      end

      def pbThrowAndDeflect(*args, &blk)
        kif_rec { ["td", [args[0].to_s, kif_i(args[1])]] }
        kif_in { super }
      end

      def pbWildBattleSuccess(*args, &blk)
        kif_rec(true) { ["ws", []] }
        kif_in { super }
      end

      def pbTrainerBattleSuccess(*args, &blk)
        kif_rec(true) { ["tw", []] }
        kif_in { super }
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Hooks (each is the plain PIF path unless this battle is a co-op one)
#-------------------------------------------------------------------------------
alias kif_coop_pbWildBattleCore pbWildBattleCore unless defined?(kif_coop_pbWildBattleCore)
alias kif_coop_pbTrainerBattleCore pbTrainerBattleCore unless defined?(kif_coop_pbTrainerBattleCore)
alias kif_coop_pbPrepareBattle pbPrepareBattle unless defined?(kif_coop_pbPrepareBattle)
alias kif_coop_pbAfterBattle pbAfterBattle unless defined?(kif_coop_pbAfterBattle)

def pbWildBattleCore(*args)
  return kif_coop_pbWildBattleCore(*args) unless KIF::Coop.may_host?
  KIF::Coop.host_battle(:wild, KIF::Coop.count_wild(args)) { kif_coop_pbWildBattleCore(*args) }
end

def pbTrainerBattleCore(*args)
  return kif_coop_pbTrainerBattleCore(*args) unless KIF::Coop.may_host?
  KIF::Coop.host_battle(:trainer, nil) { kif_coop_pbTrainerBattleCore(*KIF::Teams.extend_waiting(args)) }
end

def pbPrepareBattle(battle)
  ret = kif_coop_pbPrepareBattle(battle)
  begin
    KIF::Coop.prepare(battle) if KIF::Coop.pending_host
  rescue => e
    KIF::Coop.log("couldn't set up the co-op battle (#{e.class}: #{e.message})")
  end
  return ret
end

# PIF heals both teams after a partner battle; a co-op battle doesn't
def pbAfterBattle(decision, canLose)
  return kif_coop_pbAfterBattle(decision, canLose) unless KIF::Coop.hosting?
  # only the partner caught: the encounter was theirs (their Nuzlocke place, their
  # Soul Link catch); this player's place stays open, as theirs does when this player catches
  KIF::Nuzlocke.pending = nil if defined?(KIF::Nuzlocke) && KIF::Coop.partner_caught_alone?
  # this player ran away alone and the partner lost on: not this player's loss
  decision = 3 if [2, 5].include?(decision) && KIF::Coop.left_alone?
  old = $PokemonGlobal.partner
  $PokemonGlobal.partner = nil
  begin
    ret = kif_coop_pbAfterBattle(decision, canLose)
    KIF::Coop.black_out_check(decision, canLose)
    return ret
  ensure
    $PokemonGlobal.partner = old
  end
end

class PokeBattle_Battle
  attr_reader :kif_coop

  alias kif_coop_pbCommandPhaseLoop pbCommandPhaseLoop unless method_defined?(:kif_coop_pbCommandPhaseLoop)
  alias kif_coop_pbSwitchInBetween pbSwitchInBetween unless method_defined?(:kif_coop_pbSwitchInBetween)
  alias kif_coop_pbGainExp pbGainExp unless method_defined?(:kif_coop_pbGainExp)
  alias kif_coop_pbUsePokeBallInBattle pbUsePokeBallInBattle unless method_defined?(:kif_coop_pbUsePokeBallInBattle)
  alias kif_coop_pbRegisterItem pbRegisterItem unless method_defined?(:kif_coop_pbRegisterItem)
  alias kif_coop_pbReturnUnusedItemToBag pbReturnUnusedItemToBag unless method_defined?(:kif_coop_pbReturnUnusedItemToBag)
  alias kif_coop_pbConsumeItemInBag pbConsumeItemInBag unless method_defined?(:kif_coop_pbConsumeItemInBag)
  alias kif_coop_pbEndOfBattle pbEndOfBattle unless method_defined?(:kif_coop_pbEndOfBattle)
  alias kif_coop_pbAttackPhaseItems pbAttackPhaseItems unless method_defined?(:kif_coop_pbAttackPhaseItems) || private_method_defined?(:kif_coop_pbAttackPhaseItems)
  alias kif_coop_pbRun pbRun unless method_defined?(:kif_coop_pbRun) || private_method_defined?(:kif_coop_pbRun)
  alias kif_coop_pbAbleCount pbAbleCount unless method_defined?(:kif_coop_pbAbleCount) || private_method_defined?(:kif_coop_pbAbleCount)
  alias kif_coop_pbCanChooseNonActive? pbCanChooseNonActive? unless method_defined?(:kif_coop_pbCanChooseNonActive?) || private_method_defined?(:kif_coop_pbCanChooseNonActive?)

  # balls: this player's first, the partner's after unless that caught; then
  # the other player's attacks on a Pokémon a ball was thrown at wait
  def pbAttackPhaseItems
    c = @kif_coop
    return kif_coop_pbAttackPhaseItems unless c && wildBattle?
    c.new_turn
    later = c.later_balls
    foes = {}
    aimed = {}   # the Pokémon each later ball was thrown at
    later.each do |i, ch|
      aimed[i] = (@battlers[ch[2]] && @battlers[ch[2]].pokemon) rescue nil
      foes[i] = aimed[i] ? aimed[i].name : "?"
      pbClearChoice(i)
    end
    kif_coop_pbAttackPhaseItems
    later.each do |i, ch|
      b = @battlers[i]
      t = ch[2].is_a?(Integer) ? @battlers[ch[2]] : nil
      gone = !t || t.fainted? || !t.pokemon.equal?(aimed[i])   # caught by the first ball
      if @decision == 0 && gone && KIF::Coop.rule(:kif_coop_second_ball) == 1
        c.ball_unused(i, ch, foes[i])   # Co-op: second ball = Back to Bag
      elsif @decision == 0 && b && !b.fainted?
        @choices[i] = ch
        pbUsePokeBallInBattle(ch[1], ch[2], b)
      elsif @decision == 4
        c.ball_unused(i, ch, foes[i])
      else
        pbReturnUnusedItemToBag(ch[1], i)
      end
    end
    c.hold_attacks if @decision == 0
  end

  # a wild battle: a player who gets away leaves alone while the other fights on
  def pbRun(idxBattler, duringBattle = false)
    c = @kif_coop
    return kif_coop_pbRun(idxBattler, duringBattle) unless c && c.may_leave?(idxBattler)
    o = c.owner(idxBattler)
    # this player's own run says PIF's lines here; the partner's is worded for both
    r = o == 0 ? c.quietly { kif_coop_pbRun(idxBattler, duringBattle) } : c.muted { kif_coop_pbRun(idxBattler, duringBattle) }
    if r == 1 && @decision == 3
      c.leave(idxBattler)
    elsif r != 0
      t = _INTL("{1} couldn't get away!", c.owner_name(o))
      o == 0 ? c.push("mp", [t]) : pbDisplayPaused(t)
    end
    return r
  end

  # a player who ran away alone: their Pokémon don't count for this side
  def pbAbleCount(idxBattler = 0)
    c = @kif_coop
    return kif_coop_pbAbleCount(idxBattler) unless c && c.left_any? && !opposes?(idxBattler)
    return [0, 1].sum { |o| c.left?(o) ? 0 : c.able_of(o) }
  end

  def pbCanChooseNonActive?(idxBattler)
    c = @kif_coop
    return false if c && c.left_any? && !opposes?(idxBattler) && c.left?(c.owner(idxBattler))
    return kif_coop_pbCanChooseNonActive?(idxBattler)
  end

  # player first (the partner is asked at the same time), then the AI
  def pbCommandPhaseLoop(isPlayer)
    c = @kif_coop
    if c
      begin
        isPlayer ? c.ask_commands : c.take_commands
      rescue => e
        KIF::Coop.log("turn step failed (#{e.class}: #{e.message})")
      end
    end
    return kif_coop_pbCommandPhaseLoop(isPlayer)
  end

  def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
    c = @kif_coop
    if c && c.guest?(idxBattler)
      r = (c.choose_switch(idxBattler, checkLaxOnly, canCancel) rescue nil)
      return r if r
    end
    return kif_coop_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
  end

  def pbGainExp(*args)
    c = @kif_coop
    return kif_coop_pbGainExp(*args) unless c
    (c.note_kills rescue nil)
    return c.quietly { kif_coop_pbGainExp(*args) }
  end

  # the partner's ball: thrown in the partner's name, a catch is the partner's
  def pbUsePokeBallInBattle(item, idxBattler, userBattler)
    c = @kif_coop
    return kif_coop_pbUsePokeBallInBattle(item, idxBattler, userBattler) unless c && userBattler
    c.ball_thrown(userBattler, idxBattler)
    return kif_coop_pbUsePokeBallInBattle(item, idxBattler, userBattler) unless c.guest?(userBattler.index)
    n = @caughtPokemon.length
    ret = c.throwing(c.name) { kif_coop_pbUsePokeBallInBattle(item, idxBattler, userBattler) }
    c.caught_by_guest(@caughtPokemon.slice!(n..-1) || [])
    return ret
  end

  def pbRegisterItem(idxBattler, item, idxTarget = nil, idxMove = nil)
    c = @kif_coop
    c.item_used(item, 1) if c && item && c.guest?(idxBattler)
    return kif_coop_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
  end

  def pbReturnUnusedItemToBag(item, idxBattler)
    c = @kif_coop
    c.item_used(item, -1) if c && item && c.guest?(idxBattler)
    return kif_coop_pbReturnUnusedItemToBag(item, idxBattler)
  end

  # the partner's items come off its own Bag in its own game: not an NPC trainer's used items (the Hoenn rematch code reads those)
  def pbConsumeItemInBag(item, idxBattler)
    c = @kif_coop
    return if c && item && c.guest?(idxBattler)
    return kif_coop_pbConsumeItemInBag(item, idxBattler)
  end

  def pbEndOfBattle(*args)
    @kif_coop.own_catch = !@caughtPokemon.empty? if @kif_coop   # the partner's catches were taken out already
    ret = kif_coop_pbEndOfBattle(*args)
    (@kif_coop.finish(@decision) rescue KIF::Coop.log("result not sent (#{$!.class}: #{$!.message})")) if @kif_coop
    return ret
  end

  # this player's own money, catches and moves: not in the partner's log
  [:pbGainMoney, :pbLoseMoney, :pbGainCosmeticsMoney, :pbRecordAndStoreCaughtPokemon, :pbLearnMove].each do |m|
    next unless method_defined?(m)
    orig = :"kif_coop_q_#{m}"
    alias_method orig, m unless method_defined?(orig)
    define_method(m) do |*args, &blk|
      c = @kif_coop
      return send(orig, *args, &blk) unless c
      return c.quietly { send(orig, *args, &blk) }
    end
  end
end

# fighting together on one map: a random wild encounter has two foes (2v2),
# whatever either player's Battle Format says
class PokemonEncounters
  alias kif_coop_have_double_wild_battle? have_double_wild_battle? unless method_defined?(:kif_coop_have_double_wild_battle?) || private_method_defined?(:kif_coop_have_double_wild_battle?)

  def have_double_wild_battle?
    return true if (KIF::Coop.co_double? rescue false)
    return kif_coop_have_double_wild_battle?
  end
end
