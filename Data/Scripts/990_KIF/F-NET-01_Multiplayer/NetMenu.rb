#===============================================================================
# F-NET-01 – Multiplayer: setting, pause-menu entry and the connection screens
#
# Setting: Options > System > Multiplayer: Off / On (default Off). PC only for
# now: hidden on phones until someone tests the network there.
# Pause menu "Multiplayer": Host a game / Join with a code / Join by address /
# Find on this network. Hosting and the connection go on while you play;
# Multiplayer shows them again. Phase 1 has one thing to do once connected:
# "Send hello" (the partner sees "<name> says hello!").
#===============================================================================
KIF::Options.define(:kif_multiplayer, 0, :global)   # 0 Off, 1 On
KIF::Options.define(:kif_mp_open_port, 0, :global)  # the port the player opened in the router by hand (0: none)
KIF::Options.define(:kif_mp_public_ip, "", :global) # their public address, typed when the router doesn't tell it
KIF::Options.define(:kif_mp_players, 0, :global)    # players in a game you host: 0 = 2, 1 = 3 (you and up to two friends)

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Players"), ["2", "3"],
                 proc { $PokemonSystem.kif_mp_players },
                 proc { |value| $PokemonSystem.kif_mp_players = value },
                 [_INTL("A game you host takes one friend."),
                  _INTL("A game you host takes up to two friends. They join with the same code. Takes effect the next time you host.")])
}

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Multiplayer"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_multiplayer },
                 proc { |value|
                   $PokemonSystem.kif_multiplayer = value
                   if value == 0   # Off takes the pause entry away: hosting or a connection ends with it,
                     KIF::Net.stop
                     KIF::Net.steam.shutdown   # and friends stop seeing "Playing Spacewar" (On starts Steam again)
                   end
                 },
                 [_INTL("No Multiplayer entry in the pause menu."),
                  _INTL("Multiplayer in the pause menu: play with a friend over the internet or your network.")])
}

module KIF
  module Net
    stop if respond_to?(:stop)   # the scripts run again (F12 off Windows): end the old line, its threads keep going
    @session = nil
    @pm = nil
    @pm_thread = nil
    @lan = nil
    @notes = []
    @cleanup = []
    @renew_thread = nil
    @clip_code = nil
    @pm_lock = Mutex.new   # a renewal and a removal of the mapping never overlap

    class << self
      attr_reader :session, :pm, :notes
    end

    WAVE_EVERY = 30   # seconds between two "says hello" boxes from the partner

    def self.menu_on?
      return false if KIF.mobile?
      return (($PokemonSystem.kif_multiplayer rescue 0) || 0).to_i == 1
    end

    def self.my_name
      n = ($Trainer.name rescue nil).to_s
      return n.empty? ? "Player" : n
    end

    def self.version; defined?(KIF::PORT_VERSION) ? KIF::PORT_VERSION : "?"; end

    # players in a game this PC hosts: 2, or 3 (this player and up to two friends)
    def self.max_players
      return (($PokemonSystem.kif_mp_players rescue 0) || 0).to_i == 1 ? 3 : 2
    end

    def self.new_session
      stop
      @notes.clear
      s = Session.new(my_name, version)
      s.max_peers = max_players - 1 if s.respond_to?(:max_peers=)   # (a stand-in session in the tests has none)
      return s
    end

    # the slot of the player an action is for: the only one in, or the one picked; nil when nobody is in or on Back
    def self.pick_peer(prompt = nil)
      s = @session or return nil
      list = s.peers
      return nil if list.empty?
      return list[0][0] if list.length == 1
      names = list.map { |_, n, _| n } + [_INTL("Back")]
      i = pbMessage(prompt || _INTL("Who?"), names, names.length)
      return i >= 0 && i < list.length ? list[i][0] : nil
    end

    # the clipboard as text that can't raise (bytes that aren't text are dropped)
    def self.clipboard_text
      return (Input.clipboard.to_s.scrub("").strip rescue "")
    end

    # Host directly: listen, then open the router in the background. The IPv6
    # door stays shut until the player asks for an IPv6 code (Session#open_ipv6).
    def self.start_hosting
      s = new_session
      port = s.host(Crypto.random(4), ipv6: false) or return nil
      @session = s
      @local = PortMap.local_ip
      @pm_thread = Thread.new { PortMap.open(port, local: @local) }
      @pm_thread.report_on_exception = false
      if lan_code   # a lobby with no place left is not listed
        @lan = s.respond_to?(:lobby?) && s.lobby? ? LAN.responder(my_name, lan_code, full: proc { s.full? }) : LAN.responder(my_name, lan_code)
      end
      log("hosting on port #{port}")
      return port
    end

    def self.start_relay_host(rhost, rport)
      s = new_session
      s.host_relay(rhost, rport, Crypto.random(16), Crypto.random(8))
      @session = s
      log("hosting through a relay")
    end

    # Where a join code or a Find entry points, before this PC dials it: nil
    # (fine), :refuse (no game is hosted there) or :self (this PC). A host the
    # player typed is theirs to choose; only the port can still come from the code.
    def self.dial_problem(host, port, host_from_code:, port_from_code:)
      return :refuse if port_from_code && (port.nil? || port < 1024)
      return nil unless host_from_code
      case addr_kind(host)
      when :unspecified, :multicast, :linklocal, :invalid then return :refuse
      when :loopback then return :self
      end
      return nil
    end

    # A relay address the player typed or was given: :refuse (a port no relay uses, or an address nobody can be at),
    # :ask (this PC or a private network: fine for a relay at home, but say so first) or nil
    def self.relay_problem(host, port)
      return :refuse if port.nil? || port < 1024
      h = host.to_s.downcase
      return :ask if h == "localhost" || h.end_with?(".localhost")
      case addr_kind(host)   # a name is :invalid here, and is the resolver's to judge
      when :unspecified, :multicast, :linklocal then return :refuse
      when :loopback, :private then return :ask
      end
      return nil
    end

    # info: a read join code; address: [host, port] typed by the player
    def self.start_join(info, relay: nil, address: nil)
      s = new_session
      if info[:kind] == :relay
        s.join_relay(relay[0], relay[1], info[:secret], info[:room])
      else
        host, port = address || [info[:ip], info[:port]]
        s.join(host, port || info[:port], info[:secret])
      end
      @session = s
    end

    #---------------------------------------------------------------------------
    # Steam (NetSteam.rb): only with Multiplayer On (friends see "Playing
    # Spacewar" from then on); none on phones or without Steam
    #---------------------------------------------------------------------------
    def self.steam; @steam_layer || Steam; end   # tests put a stand-in in @steam_layer
    def self.steam?; menu_on? && steam.start ? true : false; end

    def self.start_steam_host
      s = new_session
      s.host_steam(steam, steam_tags)
      @session = s
      log("hosting on Steam")
    end

    # friend: the one picked or who invited; the lobby's owner must be them
    def self.start_steam_join(lobby, friend)
      s = new_session
      s.join_steam(steam, lobby, friend)
      @session = s
      log("joining a friend on Steam")
    end

    def self.game_mode
      (getCurrentGameModeSymbol.to_s.split("_").map(&:capitalize).join(" ") rescue "?")
    end

    def self.difficulty
      return "Easy" if $game_switches && $game_switches[SWITCH_GAME_DIFFICULTY_EASY]
      return "Hard" if $game_switches && $game_switches[SWITCH_GAME_DIFFICULTY_HARD]
      return "Normal"
    rescue StandardError
      return "?"
    end

    # the mods this session loaded (folder and loose file names), sorted
    def self.mod_names
      (KIF::Mods.loaded_dirs.map { |d| File.basename(d) } + KIF::Mods.loaded_root.map { |f| File.basename(f, ".rb") }).sort.join(",")
    rescue StandardError
      ""
    end

    # the lobby's data: what friends see before joining (never the secret)
    def self.steam_tags
      mods = mod_names
      { "kif" => "1", "ver" => version, "mode" => game_mode, "diff" => difficulty, "mods" => mods[0, 200],
        "modh" => Crypto.hex(Crypto.sha256(mods))[0, 8], "name" => my_name[0, 24] }.merge(
        max_players > 2 ? { "pl" => "1", "mx" => max_players.to_s } : {})   # a game for three: players in now and most (Session#steam_players keeps pl)
    end

    # a KIF lobby's tags as shown text, or nil (not KIF, or its data hasn't come)
    def self.lobby_tags(lobby)
      sl = steam
      return nil unless sl.lobby_data(lobby, "kif") == "1"
      t = { "ver" => 16, "mode" => 16, "diff" => 8, "mods" => 200, "modh" => 8, "name" => 24, "pl" => 1, "mx" => 1 }.to_h do |k, n|
        [k, safe_text(sl.lobby_data(lobby, k), n).delete("\n")]
      end
      t.delete("pl") if t["mx"].empty?   # a game for two has neither
      t.delete("mx") if t["mx"].empty?
      return t
    end

    # what differs from this game, one line each (empty: nothing)
    def self.steam_mismatch(t)
      out = []
      out << _INTL("They have KIF {1}, you have KIF {2}.", t["ver"], version) if t["ver"] != version
      out << _INTL("Their game is {1}, yours is {2}.", t["mode"], game_mode) if t["mode"] != game_mode
      out << _INTL("Their difficulty is {1}, yours is {2}.", t["diff"], difficulty) if t["diff"] != difficulty
      if t["modh"] != steam_tags["modh"]
        mine = mod_names[0, 200]
        out << _INTL("Their mods: {1}", t["mods"].empty? ? _INTL("none") : t["mods"])
        out << _INTL("Your mods: {1}", mine.empty? ? _INTL("none") : mine)
      end
      return out
    end

    # once a frame after the session: an invite is kept for the map; events
    # nobody took are dropped (a lobby made for a hosting that ended is left)
    def self.steam_leftovers(sl)
      sl.take(:lobby_created).each { |_, ok, lobby| sl.leave_lobby(lobby) if ok && lobby != @session&.lobby }
      inv = sl.take(:invite).last
      if inv && menu_on?
        @invite = inv[1, 2]
        log("Steam: a friend's invite came")
      end
      sl.clear
    end

    # on the map: "<friend> invited you. Join?"
    def self.ask_invite
      lobby, friend = @invite
      @invite = nil
      return unless steam.ready?
      who = shown_name(steam.name(friend))
      q = live? ? _INTL("{1} invited you to play on Steam. Leave this game and join them?", who)
                : _INTL("{1} invited you to play on Steam. Join them?", who)
      Menu.open(steam_lobby: [lobby, friend]) if pbConfirmMessage(q)
    end

    def self.stop
      if @session
        @session.close
        log("stopped")
      end
      @session = nil
      (@lan.close rescue nil) if @lan
      @lan = nil
      @cleanup.reject! { |c| !c.alive? }
      rt = @renew_thread
      @renew_thread = nil
      rt[:kif_stop] = true if rt
      if @pm_thread
        t = @pm_thread
        t[:kif_stop] = true   # the opening ends at its next step (it may be waiting for a router)
        @cleanup << Thread.new {
          m = (t.value rescue nil)
          @pm_lock.synchronize { PortMap.close(m[:mapping]) } if m && m[:mapping]
        }
        @cleanup.last.report_on_exception = false
      end
      @pm_thread = nil
      @pm = nil
    end

    # game closing: stop and give the router up to 3 s to drop the mapping
    def self.shutdown
      stop
      stop_at = now + 3
      @cleanup.each { |t| t.join([stop_at - now, 0].max) }
      steam.shutdown if steam.ready?
    end

    # every frame on the map and in the screens below; never waits
    def self.update
      clear_copied_code
      sl = steam.ready? ? steam : nil
      sl&.pump
      poll_session if @session
      steam_leftovers(sl) if sl
    end

    # every frame, wherever the game loops (Graphics.update): a lobby host in the Bag, a menu or a long event still
    # passes frames between its two guests, else the guest-vs-guest match hears nothing. Does nothing on the map (Net.update
    # just ran), for a guest, or with fewer than two guests; see Session#pump_due?
    def self.pump
      s = @session
      return if @pumping || s.nil? || !s.respond_to?(:pump_due?) || !s.pump_due?
      @pumping = true
      begin
        sl = steam.ready? ? steam : nil
        sl&.pump
        s.pump
        steam_leftovers(sl) if sl
      rescue StandardError => e
        log("relay pump failed (#{e.class}: #{e.message})")
      ensure
        @pumping = false
      end
    end

    def self.poll_session
      if @pm.nil? && @pm_thread && !@pm_thread.alive?
        @pm = (@pm_thread.value rescue nil) || { status: :closed }
        @renew_at = now + 3600
        log("router: #{@pm[:status]}#{@pm[:via] ? " (#{@pm[:via]})" : ''}")
      end
      if @pm && @pm[:mapping] && now > @renew_at
        @renew_at = now + 3600
        m = @pm[:mapping]
        @renew_thread = Thread.new do
          ok = @pm_lock.synchronize { Thread.current[:kif_stop] ? true : PortMap.renew(m) }
          log("router: the port's lease wasn't renewed") unless ok
        end
        @renew_thread.report_on_exception = false
      end
      s = @session
      evs = s.poll
      t0 = now
      evs.each_with_index do |ev, i|
        if i > 0 && now - t0 > POLL_BUDGET   # costly messages (a code to unpack) must not pile up in one frame: the rest comes next frame
          s.defer(evs[i..-1])
          break
        end
        case ev[0]
        when :join_request
          log("#{ev[1]} asks to join")
        when :connected
          log("connected to #{ev[1]} (#{s.via})")
          joined(s, ev[2])
        when :peer_joined   # a guest hears of the other guest from the host's roster
          log("#{ev[2]} joined the lobby")
          joined(s, ev[1])
        when :peer_left
          left(s, ev[1], ev[3], ev[2])
        when :message
          from = ev[3]   # the sender's slot (0 is the host); nil from a stand-in session: the one partner
          if ev[1] == "wave"
            if s.wave_at.nil? || now - s.wave_at >= WAVE_EVERY   # a partner that keeps waving shows one box in 30 s
              s.wave_at = now
              t = _INTL("{1} says hello!", (from && s.respond_to?(:name_of) && s.name_of(from)) || s.partner)
              @notes << t unless @notes.include?(t)   # shown on the map too: one at a time
            end
          elsif ev[1].start_with?("sl_") && defined?(KIF::SoulLink)
            begin
              KIF::SoulLink.receive(ev[1], ev[2], from && s.respond_to?(:peer) ? s.peer(from) : s)
            rescue => e
              log("Soul Link message failed (#{e.class}: #{e.message})")
            end
          elsif ev[1].start_with?("pr_") && defined?(KIF::Presence)
            begin
              KIF::Presence.receive(ev[1], ev[2], from)
            rescue StandardError, ScriptError, SystemStackError => e   # one bad message doesn't cost the others in this batch
              log("presence message failed (#{e.class}: #{e.message})")
            end
          elsif ev[1].start_with?("mod_") && defined?(ModShare)
            begin
              ModShare.receive(s, ev[1], ev[2], from)
            rescue StandardError, ScriptError, SystemStackError => e
              log("mod share message failed (#{e.class}: #{e.message})")
            end
          elsif ev[1].start_with?("sp_") && defined?(KIF::NetSprite)
            begin
              KIF::NetSprite.receive(s, ev[1], ev[2], from)
            rescue => e
              log("sprite message failed (#{e.class}: #{e.message})")
            end
          elsif ev[1].start_with?("tr_") && defined?(KIF::Trade)
            begin
              KIF::Trade.receive(ev[1], ev[2], from)
            rescue => e
              log("trade message failed (#{e.class}: #{e.message})")
            end
          elsif ev[1].start_with?("co_") && defined?(KIF::Coop)
            begin
              KIF::Coop.receive(ev[1], ev[2], from)
            rescue => e
              log("co-op message failed (#{e.class}: #{e.message})")
            end
          end
        when :disconnected
          in_slots(s).clear
          KIF::SoulLink.on_disconnect(s) if defined?(KIF::SoulLink)
          KIF::Presence.on_disconnect if defined?(KIF::Presence)
          KIF::Coop.on_disconnect if defined?(KIF::Coop)
          KIF::Trade.on_disconnect if defined?(KIF::Trade)
          @notes << (ev[1] == :removed ? _INTL("The host took you out of the game.") :
                     ev[1] == :bye ? _INTL("Your friend disconnected.") : _INTL("Lost the connection to your friend."))
          log("disconnected (#{ev[1]})")
        when :failed
          @failed = ev[1]
          log("joining failed (#{ev[1]})")
        end
      end
    end

    # A player is in. The first one starts every feature fresh; a second one (a lobby of three) is told to
    # the features one by one (what they sent before is sent again for the newcomer).
    def self.in_slots(s); s.instance_variable_get(:@kif_in) || s.instance_variable_set(:@kif_in, []); end

    def self.joined(s, slot)
      here = in_slots(s)
      first = here.empty?
      here << slot unless slot.nil? || here.include?(slot)
      if first
        KIF::SoulLink.on_connect(slot.nil? ? s : s.peer(slot)) if defined?(KIF::SoulLink)
        KIF::Presence.on_connect if defined?(KIF::Presence)
        KIF::Coop.on_connect(s) if defined?(KIF::Coop)
        begin
          ModShare.on_connect(s) if defined?(ModShare)
        rescue StandardError, ScriptError, SystemStackError => e
          log("mod share failed (#{e.class}: #{e.message})")
        end
        KIF::NetSprite.on_connect(s) if defined?(KIF::NetSprite)
        KIF::Trade.on_connect(s) if defined?(KIF::Trade)
      else
        KIF::SoulLink.on_peer_joined(s.peer(slot)) if defined?(KIF::SoulLink) && KIF::SoulLink.respond_to?(:on_peer_joined)
        KIF::Presence.on_peer_joined(slot) if defined?(KIF::Presence)
        KIF::Coop.on_peer_joined(slot) if defined?(KIF::Coop)
        begin
          ModShare.on_peer_joined(s, slot) if defined?(ModShare)
        rescue StandardError, ScriptError, SystemStackError => e
          log("mod share failed (#{e.class}: #{e.message})")
        end
        KIF::Trade.on_peer_joined(slot) if defined?(KIF::Trade)
      end
    rescue StandardError => e
      log("a player joining failed in a feature (#{e.class}: #{e.message})")
    end

    # A player of a lobby is gone (the lobby goes on). The last one leaving also comes as :disconnected.
    def self.left(s, slot, name, why = nil)
      in_slots(s).delete(slot)
      KIF::SoulLink.on_peer_left(s.peer(slot)) if defined?(KIF::SoulLink) && KIF::SoulLink.respond_to?(:on_peer_left)
      KIF::Presence.on_peer_left(slot) if defined?(KIF::Presence)
      KIF::Coop.on_peer_left(slot) if defined?(KIF::Coop)
      KIF::Trade.on_peer_left(slot) if defined?(KIF::Trade)
      @notes << (why == :removed ? _INTL("{1} was taken out of the game.", name) : _INTL("{1} left the game.", name)) if name
      log("#{name} left the lobby (#{why})")
    rescue StandardError => e
      log("a player leaving failed in a feature (#{e.class}: #{e.message})")
    end

    def self.take_failure; f = @failed; @failed = nil; f; end

    # hosting or connected (a joiner's ended session can still be held)
    def self.live?; s = @session; s && (s.connected? || s.hosting?) ? true : false; end

    # "Let <name> join?" for a player who knew the code; called from the
    # screens below and on the map when nothing else is going on
    def self.ask_join
      s = @session
      return unless s&.asking? && !@asking
      begin
        @asking = true
        yes = pbConfirmMessage(_INTL("{1} wants to join your game. Let {1} join?", s.asking_name || s.partner))
      ensure
        @asking = false
      end
      return unless @session.equal?(s) && s.asking?   # gone or timed out meanwhile
      yes ? s.accept : s.decline
    end

    # the map and the player are idle: a question cuts nothing off
    def self.quiet?
      return false unless $scene.is_a?(Scene_Map)
      return false if $game_temp.message_window_showing || $game_temp.in_menu
      return false if pbMapInterpreterRunning?
      return false if $game_player.moving? || $game_player.move_route_forcing
      return true
    rescue StandardError
      return false
    end

    # every frame on the map
    def self.map_update
      clear_copied_code
      steam.start if menu_on?   # once a game; then invites can come
      update
      ask_invite if @invite && quiet?
      return unless @session
      ask_join if @session&.asking? && quiet?
      pbMessage(@notes.shift) if !@notes.empty? && quiet?   # "<name> says hello!", a disconnect
    end

    # "Find on this network" gives out this code's port only (LAN.responder)
    def self.lan_code
      return nil unless @session && @session.via == :direct && @local && PortMap.ip_kind(@local) != :invalid
      return JoinCode.make(:v4, ip: @local, port: @session.port, secret: @session.secret)
    end

    # the code goes on the clipboard and is taken off again after a minute
    # (clipboard history and cloud clipboards keep what is on it)
    def self.copy_code(code)
      Input.clipboard = code
      @clip_code = code
      @clip_at = now
      return true
    rescue StandardError
      @clip_code = nil
      return false
    end

    def self.clear_copied_code
      return unless @clip_code && now - @clip_at >= 60
      forget_copied_code
    end

    def self.forget_copied_code
      c = @clip_code
      @clip_code = nil
      (Input.clipboard = "") if c && (Input.clipboard rescue nil) == c
    rescue StandardError
      nil
    end

    def self.v6_code
      ip = PortMap.global_ipv6
      return nil unless ip && @session && @session.via == :direct
      return JoinCode.make(:v6, ip: ip, port: @session.port, secret: @session.secret)
    end

    # "I opened port N myself" was picked for the port this game hosts on
    def self.opened_by_hand?
      s = @session
      return s && s.via == :direct && ($PokemonSystem.kif_mp_open_port rescue 0).to_i == s.port ? true : false
    end

    # the public address the player typed (checked again: settings can be old)
    def self.typed_address
      a = ($PokemonSystem.kif_mp_public_ip rescue "").to_s
      return PortMap.public_ip?(a) ? a : nil
    end

    # The code to send: through the router when it's open (or opened by
    # hand: the external address is known, or typed), else for this network only
    def self.code
      s = @session or return nil
      return JoinCode.make(:relay, room: s.room, secret: s.secret) if s.via == :relay
      return nil unless @pm
      ext = @pm[:external_ip]
      if @pm[:status] == :open && PortMap.ip_kind(ext) != :invalid
        return JoinCode.make(:v4, ip: ext, port: @pm[:external_port], secret: s.secret)
      elsif @pm[:status] == :closed && PortMap.ip_kind(ext) == :public
        return JoinCode.make(:v4, ip: ext, port: s.port, secret: s.secret)
      elsif @pm[:status] == :closed && opened_by_hand? && (a = typed_address)
        s.open_ipv6 if a.include?(":")   # an IPv6 code needs a door that listens on IPv6
        return JoinCode.make(a.include?(":") ? :v6 : :v4, ip: a, port: s.port, secret: s.secret)
      end
      return lan_code
    end

    def self.lan_only?; @pm && code == lan_code; end

    # "host:port", "[v6]:port", "v6" or "host"
    def self.parse_address(text, default_port)
      t = text.to_s.strip
      return nil if t =~ /\AKIF[6R]?(-[0-9A-Z]{1,4}){3,}\z/i   # a join code left on the clipboard is not a host name (it would go to the resolver)
      m = t.match(/\A\[([0-9a-fA-F:.]+)\](?::(\d{1,5}))?\z/) ||
          (t.count(":") >= 2 ? t.match(/\A([0-9a-fA-F:.]+)()\z/) : t.match(/\A([A-Za-z0-9.\-]+)(?::(\d{1,5}))?\z/))
      return nil unless m
      port = m[2].to_s.empty? ? default_port : m[2].to_i
      return nil unless port.nil? || port.between?(1, 65_535)   # nil: the port comes from the code
      return [m[1], port]
    end

    #===========================================================================
    # Screens
    #===========================================================================
    class Screen
      HEAD_H = 128
      HELP_H = 96

      @open = []      # screens on view (nested: Soul Link's list over the connected screen)
      @hushed = 0     # message windows up

      # PIF's message box is see-through: the help text under it is hidden
      # while one is up (pbCreateMessageWindow / pbDisposeMessageWindow below)
      def self.hush(n)
        @hushed = [@hushed + n, 0].max
        @open.each { |s| s.help_visible = @hushed == 0 }
      end

      def self.opened(scr); @hushed = 0 if @open.empty?; @open << scr; end
      def self.closed(scr); @open.delete(scr); end

      attr_accessor :start_at   # the row a new list starts on (-1: the last); used once

      def initialize(list = Window_CommandPokemon)   # Soul Link lists pass a window with columns
        Screen.opened(self)
        @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @vp.z = 99_999   # same z as the pause menu and PIF's map name box, made later: drawn over them; messages made later go on top
        @head = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, HEAD_H, @vp)
        @cmd = list.newWithSize([""], 0, HEAD_H, Graphics.width, Graphics.height - HEAD_H - HELP_H, @vp)
        @help = Window_UnformattedTextPokemon.newWithSize("", 0, Graphics.height - HELP_H, Graphics.width, HELP_H, @vp)
        @cmds = nil
      end

      # the top box is as tall as its lines; the list gets the rest (it scrolls)
      def show(head, cmds, help)
        if @head.text != head
          h = [(head.count("\n") + 1) * 32 + 32, Graphics.height - HELP_H - 96].min
          if h != @head.height
            @head.height = h
            @cmd.y = h
            @cmd.height = Graphics.height - HELP_H - h
          end
          @head.text = head
        end
        @help.text = help if @help.text != help
        return if cmds == @cmds
        @cmd.commands = cmds   # a new list starts at the top
        @cmd.index = @start_at ? @start_at % cmds.length : 0
        @start_at = nil
        @cmds = cmds.dup
      end

      def help_visible=(v); @help.visible = v unless @help.disposed?; end

      # one frame: the chosen row, -1 for Back, or nil
      def frame
        Graphics.update
        Input.update
        @cmd.update
        KIF::Net.update
        KIF::Net.ask_join
        if Input.trigger?(Input::USE)
          pbPlayDecisionSE
          return @cmd.index
        end
        if Input.trigger?(Input::BACK)
          pbPlayCancelSE
          return -1
        end
        return nil
      end

      def dispose
        Screen.closed(self)
        [@head, @cmd, @help].each(&:dispose)
        @vp.dispose
      end

      # hidden while another screen is on top (the windows let it show through)
      def visible=(value); @vp.visible = value; end
    end

    module Menu
      module_function

      # steam_lobby: [lobby, friend] of a friend's invite accepted on the map
      def open(steam_lobby: nil)
        unless Net.available?
          return pbMessage(_INTL("Multiplayer needs the game's network library, which this copy of the game doesn't have."))
        end
        @scr = Screen.new
        begin
          s = Net.session
          if steam_lobby then return steam_join(*steam_lobby)
          elsif s&.connected? then connected
          elsif s&.hosting? then s.via == :steam ? steam_hosting : hosting
          end
          main unless Net.live?   # B leaves a game that goes on: Host or Join from main would end it
        ensure
          @scr.dispose
          @scr = nil
        end
      end

      # the chosen row, -1 for Back, or nil when watch's value changes (the
      # screen is drawn again)
      def pick(head, cmds, help, watch = nil)
        was = watch&.call
        loop do
          @scr.show(head, cmds, help)
          r = @scr.frame
          return r if r
          return nil if watch && watch.call != was
        end
      end

      def main
        loop do
          rows = [[_INTL("Host a game"), :host], [_INTL("Join with a code"), :code], [_INTL("Join by address"), :address],
                  [_INTL("Find on this network"), :lan], [_INTL("Back"), nil]]
          steam = Net.steam?
          rows.unshift([_INTL("Host on Steam"), :steam_host], [_INTL("Join a Steam friend"), :steam_join]) if steam
          help = steam ? _INTL("Steam: host and invite a Steam friend, or join one.\nCode: your friend joins with the code you send.")
                       : _INTL("Host: your friend joins your game.\nJoin: use the code your friend sent you.")
          r = pick(steam ? _INTL("Play with a friend\nOne of you hosts, the other joins.\nNo server needed.")
                         : _INTL("Play with a friend\nOne of you hosts, the other joins.\nNo account and no server needed."),
                   rows.map(&:first), help)
          case (r && r >= 0 ? rows[r][1] : nil)
          when :steam_host then steam_host
          when :steam_join then steam_join_list
          when :host then host
          when :code then join_code
          when :address then join_address
          when :lan then find_lan
          else return
          end
          return if Net.live?
        end
      end

      #-------------------------------------------------------------------------
      # Steam: host, invite, join a friend
      #-------------------------------------------------------------------------
      def steam_host
        Net.start_steam_host
        steam_hosting
      end

      # returns when hosting stops or the player leaves (hosting goes on)
      def steam_hosting
        watch = proc { [Net.session&.state, Net.notes.length] }
        loop do
          s = Net.session
          unless s&.hosting?
            pbMessage(_INTL("Steam didn't make a lobby. Check that Steam is running and online, then try again.")) if Net.take_failure
            Net.stop if s
            return
          end
          return connected if s.connected?
          lines = [_INTL("Host on Steam"), s.lobby ? _INTL("Lobby: Friends only") : _INTL("Making a Steam lobby..."),
                   _INTL("Friend joined: Not yet")]
          lines << _INTL("Players: up to {1}", Net.max_players) if Net.max_players > 2
          cmds = s.lobby ? [_INTL("Invite a Steam friend"), _INTL("Stop hosting")] : [_INTL("Stop hosting")]
          help = Net.notes.shift || _INTL("Invite a Steam friend, or they pick Join a Steam friend.\nWaiting for them to join...")
          r = pick(lines.join("\n"), cmds, help, watch)
          next if r.nil?
          return if r < 0
          if cmds.length == 2 && r == 0
            steam_invite(s.lobby)
          elsif pbConfirmMessage(_INTL("Stop hosting?"))
            Net.stop
            return
          end
        end
      end

      # Steam's invite window when its overlay is in this game window; the
      # friend list here always (InviteUserToLobby needs no overlay)
      def steam_invite(lobby)
        sl = Net.steam
        overlay = sl.overlay?
        list = sl.friends_online.first(200)
        names = list.map { |_, n| Net.shown_name(n) }
        rows = (overlay ? [_INTL("Open Steam's invite window")] : []) + names + [_INTL("Back")]
        if !overlay && list.empty?
          return pbMessage(_INTL("None of your Steam friends are online right now."))
        end
        msg = overlay ? _INTL("Invite a Steam friend:") : _INTL("Steam's overlay can't show in this game window, so pick the friend here. They get a Steam invite.")
        i = pbMessage(msg, rows, rows.length)
        i -= 1 if overlay
        if i == -1
          sl.invite_dialog(lobby)
          Net.log("Steam: invite window opened")
        elsif i >= 0 && i < list.length
          ok = sl.invite(lobby, list[i][0])
          Net.log("Steam: invite #{ok ? 'sent' : 'not sent'}")
          pbMessage(ok ? _INTL("Invite sent to {1}. When they accept it in Steam, their game joins yours.", names[i])
                       : _INTL("Steam didn't send the invite. Try again."))
        end
      end

      def steam_join_list
        sl = Net.steam
        found = sl.friend_lobbies
        found.each { |_, l| sl.request_lobby_data(l) }
        unless found.empty?   # a friend's lobby data comes in a moment; a friend in another game's lobby never has KIF's
          wait_for(_INTL("Join a Steam friend\nLooking for friends hosting KIF..."), 2) { found.all? { |_, l| Net.lobby_tags(l) } }
        end
        games = found.filter_map { |f, l| (t = Net.lobby_tags(l)) && [f, l, t] }
        if games.empty?
          return pbMessage(_INTL("None of your Steam friends are hosting KIF right now. Ask them to pick Host on Steam and invite you."))
        end
        names = games.map do |f, _, t|
          mx = t["mx"].to_i
          mx >= 3 ? _INTL("{1} ({2}, KIF {3}, {4} of {5})", Net.shown_name(sl.name(f)), t["mode"], t["ver"], t["pl"].to_i, mx)
                  : _INTL("{1} ({2}, KIF {3})", Net.shown_name(sl.name(f)), t["mode"], t["ver"])
        end + [_INTL("Back")]
        i = pbMessage(_INTL("Friends hosting KIF:"), names, names.length)
        steam_join(games[i][1], games[i][0], games[i][2]) if i < games.length
      end

      # friend: picked or who invited; tags: the lobby's (read again when nil); differences are shown first
      def steam_join(lobby, friend, tags = nil)
        unless tags
          Net.steam.request_lobby_data(lobby)
          wait_for(_INTL("Join on Steam\nReading your friend's game..."), 3) { Net.lobby_tags(lobby) }
          tags = Net.lobby_tags(lobby) or return pbMessage(_INTL("That Steam game isn't a KIF game, or it has closed."))
        end
        warn = Net.steam_mismatch(tags)
        unless warn.empty?
          pbMessage(_INTL("{1}'s game is different from yours:", tags["name"]) + "\n" + warn.join("\n"))
          return unless pbConfirmMessage(_INTL("Join anyway?"))
        end
        Net.start_steam_join(lobby, friend)
        loop do
          s = Net.session
          break unless s && s.state != :closed && !s.connected?
          head = s.state == :waiting ? _INTL("Join on Steam\nWaiting for your friend to let you in...")
                                     : _INTL("Join on Steam\nConnecting to your friend's game...")
          r = pick(head, [_INTL("Cancel")], _INTL("Through Steam."), proc { Net.session&.state })
          next if r.nil?
          return Net.stop
        end
        return connected if Net.session&.connected?
        why = Net.take_failure
        Net.stop
        pbMessage({
          busy: _INTL("Someone else is playing with them right now."),
          full: _INTL("Their game is full."),
          timeout: _INTL("Their game didn't answer in time (in a battle or a menu?). Try again when they're on the map."),
          declined: _INTL("Your friend didn't let you in (they said no, or didn't answer in time)."),
          host_code: _INTL("That Steam game isn't a KIF game, or it has closed."),
          not_host: _INTL("Your friend is in someone else's game, not hosting one. Ask them to pick Host on Steam.")
        }[why] || _INTL("Couldn't get into your friend's Steam lobby. It may have closed."))
      end

      # frames until the block is true or secs pass (Cancel or B stops early)
      def wait_for(head, secs)
        stop = Net.now + secs
        until yield
          return false if Net.now > stop || pick_once(head, [_INTL("Cancel")], "")
        end
        return true
      end

      #-------------------------------------------------------------------------
      # Hosting (MP2a, MP2b, MP3a, MP3b, MP4)
      #-------------------------------------------------------------------------
      def host
        port = Net.start_hosting
        unless port
          return pbMessage(_INTL("Couldn't host: ports {1} to {2} are used by another program.",
                                 Net::PORT, Net::PORT + Net::PORT_TRIES - 1))
        end
        hosting
      end

      def router_text(pm)
        return _INTL("Opening...") unless pm
        case pm[:status]
        when :open
          { upnp: _INTL("Opened (UPnP)"), natpmp: _INTL("Opened (NAT-PMP)") }[pm[:via]] || _INTL("Not needed")
        when :shared then _INTL("Can't help here")
        else _INTL("Not opened")
        end
      end

      # returns when hosting stops or the player leaves (hosting goes on)
      def hosting
        copied = false
        watch = proc { [Net.session&.state, Net.pm.nil?, Net.notes.length] }
        loop do
          s = Net.session
          unless s&.hosting?
            why = Net.take_failure
            if why == :code
              pbMessage(_INTL("Someone tried your relay room with a wrong code, so it closed. Host on the relay again for a new code."))
            elsif why == :relay_busy
              pbMessage(_INTL("The relay is busy right now. Try again in a few minutes."))
            elsif why && s&.via == :relay
              pbMessage(_INTL("Couldn't reach the relay, or it closed the line. Check the address and try again."))
            end
            Net.stop if s
            return
          end
          return connected if s.connected?
          pm = Net.pm
          relay = s.via == :relay
          code = Net.code
          by_hand = !relay && pm && pm[:status] == :closed && Net.opened_by_hand?
          no_address = by_hand && Net.lan_only?   # the router doesn't tell it and none was typed
          # the code stays off the screen (a stream or a screenshot would show it): Copy / Show
          lines = [_INTL("Host a game"), _INTL("Your code: {1}", relay || code ? _INTL("ready (Copy or Show)") : "...")]
          if relay
            lines << _INTL("Relay: {1}", s.relay.join(":"))
            lines << (s.state == :connecting ? _INTL("Connecting to the relay...") : _INTL("Friend joined: Not yet"))
          else
            lines << _INTL("Port: {1}    Router port: {2}", s.port, by_hand ? _INTL("Opened by you") : router_text(pm))
            lines << _INTL("Players: up to {1} (both friends use this code)", Net.max_players) if Net.max_players > 2
          end
          cmds = []
          acts = []
          add = proc { |text, act| cmds << text; acts << act }
          if relay || pm.nil? || pm[:status] == :open || by_hand
            lines << _INTL("Friend joined: Not yet") if !relay && pm
            help = if !relay && pm.nil? then _INTL("Opening your router...\nThis takes a few seconds.")
                   elsif no_address then _INTL("Your router doesn't tell the game your public address. Type it so your code holds it.")
                   elsif copied then _INTL("Code copied. Waiting for them to join...")
                   else _INTL("Ready. Send the code to your friend only.\nWaiting for them to join...")
                   end
            if code && !no_address
              add.call(_INTL("Copy code"), :copy)
              add.call(_INTL("Show code bigger"), :big)
            end
            if by_hand
              if PortMap.ip_kind(pm[:external_ip]) != :public
                add.call(no_address ? _INTL("Type your public address") : _INTL("Change your public address"), :address)
              end
              add.call(_INTL("Copy code for this network"), :copy) if code && no_address
              add.call(_INTL("Port {1} isn't open after all", s.port), :not_by_hand)
            end
          elsif pm[:status] == :shared
            help = if PortMap.ip_kind(pm[:external_ip]) == :private
                     _INTL("Another router is in front of yours, so nobody can reach this PC. Joining still works.")
                   else
                     _INTL("Your internet provider shares one address between many homes, so nobody can reach this PC. Joining still works.")
                   end
            add.call(_INTL("Ask your friend to host instead"), :swap)
            add.call(_INTL("Use a relay"), :relay)
            add.call(_INTL("Copy IPv6 code"), :v6) if Net.v6_code
            add.call(_INTL("Copy code for this network"), :copy) if code
          else
            help = _INTL("Your router didn't let the game open a door for your friend, so they can't reach you yet.")
            add.call(_INTL("Ask your friend to host instead"), :swap)
            add.call(_INTL("Open port {1} yourself (how?)", s.port), :how)
            add.call(_INTL("I opened port {1} myself", s.port), :by_hand)
            add.call(_INTL("Use a relay"), :relay)
            add.call(Net.lan_only? ? _INTL("Copy code for this network") : _INTL("Copy code"), :copy) if code
          end
          add.call(_INTL("Stop hosting"), :stop)
          help = Net.notes.shift || help
          r = pick(lines.join("\n"), cmds, help, watch)
          next if r.nil?
          return if r < 0
          case acts[r]
          when :copy
            copied = Net.copy_code(code)
            pbMessage(_INTL("Copying didn't work. Your code is:\n{1}", code)) unless copied
          when :v6
            c = Net.v6_code
            next pbMessage(_INTL("Couldn't open this port for IPv6.")) unless s.open_ipv6   # shut until asked for
            pbMessage(_INTL("This code works if your friend also has IPv6:\n{1}", c)) unless Net.copy_code(c)
          when :big
            pbMessage(_INTL("Your code:\n{1}", code))
          when :how then how_to_open(s.port)
          when :by_hand
            next unless pbConfirmMessage(_INTL("Is port {1} (TCP) forwarded to this PC in your router? The game remembers it.", s.port))
            $PokemonSystem.kif_mp_open_port = s.port
            ask_address if PortMap.ip_kind(pm[:external_ip]) != :public && !Net.typed_address   # once
          when :address then ask_address
          when :not_by_hand then $PokemonSystem.kif_mp_open_port = 0
          when :swap
            next unless pbConfirmMessage(_INTL("Stop hosting and join with your friend's code instead?"))
            Net.stop
            return join_code
          when :relay
            r2 = ask_relay or next
            pbMessage(_INTL("A relay game takes one friend.")) if Net.max_players > 2
            Net.start_relay_host(*r2)
          when :stop
            next unless pbConfirmMessage(_INTL("Stop hosting?"))
            Net.stop
            @scr.start_at = -1   # the menu opens on Back: one more A doesn't host again
            return
          end
        end
      end

      # short lines, three boxes (it was seven presses to read)
      def how_to_open(port)
        local = PortMap.local_ip || "?"
        gw = PortMap.gateway_guess(local) || "192.168.1.1"
        pbMessage(_INTL("Open your router's page in a browser,\noften {1} (see its sticker).", gw))
        pbMessage(_INTL("Find Port forwarding and add port {1},\nTCP, to this PC: {2}.", port, local))
        pbMessage(_INTL("Save it there, then pick\n\"I opened port {1} myself\".", port))
      end

      # the public address for the code when the router doesn't tell it (kept; checked)
      def ask_address
        t = pbMessageFreeText(_INTL("Your public address (search \"what is my IP\" in a browser):"),
                              ($PokemonSystem.kif_mp_public_ip rescue "").to_s, false, 45)
        return if t.nil? || t.strip.empty?
        return $PokemonSystem.kif_mp_public_ip = t.strip if PortMap.public_ip?(t.strip)
        pbMessage(_INTL("That isn't a public address. It looks like 203.0.113.25 (from \"what is my IP\"), not 192.168..."))
      end

      #-------------------------------------------------------------------------
      # Relay (MP6a)
      #-------------------------------------------------------------------------
      def ask_relay
        text = ""
        loop do
          lines = _INTL("Use a relay\nBoth of you use the same address.\n{1}", text.empty? ? "_" : text)
          r = pick(lines, [_INTL("Type the address"), _INTL("Paste"), _INTL("Connect"), _INTL("Back")],
                   _INTL("A relay is someone else's PC that\npasses on your messages. KIF has none."))   # two short lines: the box shows two
          case r
          when 0 then text = (pbMessageFreeText(_INTL("Relay address:"), text, false, 80) || text).strip
          when 1 then text = Net.clipboard_text[0, 80]
          when 2
            addr = Net.parse_address(text, Net::RELAY_PORT)
            unless addr
              pbMessage(_INTL("That isn't an address. It looks like relay.example.net or 203.0.113.5:52413."))
              next
            end
            case Net.relay_problem(*addr)
            when :refuse
              pbMessage(_INTL("A relay doesn't run at that address. Ask your friend for the relay's address again."))
              next
            when :ask
              next unless pbConfirmMessage(_INTL("That relay is on this PC or on your own network. Use it anyway?"))
            end
            return addr
          else return nil
          end
        end
      end

      #-------------------------------------------------------------------------
      # Joining (MP5a, MP5b, MP5c)
      #-------------------------------------------------------------------------
      def join_code(address = nil)
        clip = Net.clipboard_text[0, 60]   # as long as the Paste button takes
        text = Net::JoinCode.read(clip).is_a?(Hash) ? clip : ""
        loop do
          st = text.empty? ? nil : Net::JoinCode.read(text)
          help = if st.nil? then _INTL("Type or paste the code your friend sent.")
                 elsif st.is_a?(Hash) then _INTL("Code looks right.")
                 elsif st == :typo then _INTL("A letter or number in the code is wrong. Check it with your friend.")
                 else _INTL("That isn't a join code. Join codes start with KIF-.")
                 end
          head = _INTL("Join with a code\n{1}", text.empty? ? "_" : text.scan(/.{1,30}/).join("\n"))
          head += "\n" + _INTL("Address: {1}", address.compact.join(":")) if address
          case pick(head, [_INTL("Type the code"), _INTL("Paste"), _INTL("Connect"), _INTL("Back")], help)
          when 0 then text = (pbMessageFreeText(_INTL("Join code:"), text, false, 60) || text).strip
          when 1 then text = Net.clipboard_text[0, 60]
          when 2
            next pbMessage(help) unless st.is_a?(Hash)
            relay = nil
            if st[:kind] == :relay
              relay = ask_relay or next
            end
            return if connect(st, relay, address) == :done
          else return
          end
        end
      end

      def join_address
        t = pbMessageFreeText(_INTL("Address of your friend's game (for example 203.0.113.25):"), "", false, 60)
        return if t.nil? || t.strip.empty?
        addr = Net.parse_address(t, nil)   # no port typed: the code's (the host may not be on 52411)
        return pbMessage(_INTL("That isn't an address. It looks like 203.0.113.25 or 203.0.113.25:52411.")) unless addr
        pbMessage(_INTL("Now the code your friend sent: it holds the key. The address you typed is used instead of the one in the code."))
        join_code(addr)
      end

      # :done when connected and back from the connected screen
      def connect(info, relay, address)
        unless relay
          host, port = address ? [address[0], address[1] || info[:port]] : [info[:ip], info[:port]]
          case Net.dial_problem(host, port, host_from_code: address.nil?, port_from_code: address.nil? || address[1].nil?)
          when :refuse
            return pbMessage(_INTL("That code points to an address no game uses. Ask your friend for the code again."))
          when :self
            return nil unless pbConfirmMessage(_INTL("That code points to this PC itself. Connect anyway?"))
          end
          return pbMessage(_INTL("This needs your friend's code.")) unless info[:secret]
        end
        loop do
          Net.start_join(info, relay: relay, address: address)
          loop do
            s = Net.session
            break unless s && s.state != :closed && !s.connected?
            head = if s.state == :waiting then _INTL("Join with a code\nWaiting for your friend to let you in...")
                   else _INTL("Join with a code\nConnecting to your friend's game...")
                   end
            r = pick(head, [_INTL("Cancel")],
                     relay ? _INTL("Through the relay {1}.", relay.join(":")) : _INTL("Code looks right.\nConnecting..."),
                     proc { Net.session&.state })
            next if r.nil?
            Net.stop
            return nil
          end
          if Net.session&.connected?
            connected
            return :done
          end
          why = Net.take_failure
          Net.stop
          text = {
            code: _INTL("Their game says the code doesn't match. Ask them for the code again."),
            host_code: _INTL("The game at that address doesn't know this code. Ask your friend for a new one."),
            busy: _INTL("Someone else is joining or playing with them right now."),
            full: _INTL("Their game is full."),
            wait: _INTL("Too many wrong codes were tried on that game, or from here. Try again in a few minutes."),
            relay: _INTL("The relay didn't accept you. Check the address, or ask your friend to host on it again."),
            relay_busy: _INTL("The relay is busy right now. Try again in a few minutes."),
            timeout: _INTL("Their game didn't answer in time (in a battle or a menu?). Try again when they're on the map."),
            declined: _INTL("Your friend didn't let you in (they said no, or didn't answer in time).")
          }[why] || _INTL("Their router may be closed, or the code is old (codes change sometimes).")
          r = pick(_INTL("Join with a code\nYour friend's game: Can't reach it"),
                   [_INTL("Host instead, send them your code"), _INTL("Try again"), _INTL("Use a relay"), _INTL("Back")], text)
          case r
          when 0
            host
            return :done
          when 1 then next
          when 2
            pbMessage(_INTL("A relay needs both of you. Ask your friend to pick Use a relay when hosting and send you the new code (it starts with KIFR-)."))
            return nil
          else return nil
          end
        end
      end

      def find_lan
        t = Net::LAN.find
        until (t.join(0) rescue true)   # (a search that died with an error ends the wait; join(0) would raise it here)
          return if pick_once(_INTL("Find on this network\nLooking for games on this network..."), [_INTL("Cancel")], "")   # Cancel or B: the search ends by itself
        end
        list = ((t.value rescue []) || []).select { |_, i| i[:port] >= 1024 }   # no game hosts below that
        if list.empty?
          return pbMessage(_INTL("No games found on this network. Your friend needs to host first, and both PCs need to be on the same network."))
        end
        names = list.map { |n, _| n } + [_INTL("Back")]
        i = pbMessage(_INTL("Games on this network:"), names, names.length)
        return if i >= list.length
        # the answer holds the address only: the code (the key) comes from the friend
        pbMessage(_INTL("Now the code your friend sent: it holds the key."))
        join_code(list[i][1].values_at(:ip, :port))
      end

      def pick_once(head, cmds, help)
        @scr.show(head, cmds, help)
        @scr.frame
      end

      #-------------------------------------------------------------------------
      # Connected (MP5b, MP6b)
      #-------------------------------------------------------------------------
      def connected
        note = nil   # kept when the screen is only drawn again (the watch), until a row is picked
        loop do
          s = Net.session
          unless s&.connected?
            pbMessage(Net.notes.shift || _INTL("The connection ended."))
            Net.notes.clear
            Net.stop unless s&.hosting?
            return
          end
          relay = s.via == :relay
          peers = s.respond_to?(:peers) ? s.peers : [[nil, s.partner, s.partner_ver]]   # (a stand-in session has one partner)
          lines = [_INTL("Connected"), _INTL("Connected to: {1}", peers.map { |_, n, _| n }.join(", ")),
                   relay ? _INTL("Connection: Through relay ({1})", s.relay.join(":")) :
                   s.via == :steam ? _INTL("Connection: Steam") : _INTL("Connection: Direct")]
          peers.each do |_, n, v|
            lines << _INTL("{1} has KIF {2}, you have KIF {3}.", n, v, Net.version) if v != Net.version
          end
          peers.each do |sl_, n, _|
            where = defined?(KIF::Presence) && KIF::Presence.where_line(n, sl_)
            lines << where if where
          end
          note = Net.notes.shift || note
          help = note ||
                 (relay ? _INTL("Connected through relay.\nPlay works the same, just a bit slower.") :
                  s.via == :steam ? _INTL("Connected to {1} through Steam.", s.partner)
                        : _INTL("Connected to {1} (direct).\nYour games talk to each other directly.", s.partner))
          sl = defined?(KIF::SoulLink) && KIF::SoulLink.awake?
          cmds = [_INTL("Send hello"), _INTL("Disconnect")]
          cmds.unshift(_INTL("Soul Link")) if sl
          lobby = s.respond_to?(:lobby?) && s.lobby?   # the host of a game for three
          ad = lobby && !s.full? ? cmds.length.tap { cmds << _INTL("Add a player") } : nil
          rm = lobby ? cmds.length.tap { cmds << _INTL("Remove a player") } : nil
          tr = defined?(KIF::Trade) ? cmds.length : nil   # after Disconnect, before co-op's row
          cmds << KIF::Trade.menu_label if tr
          pv = defined?(KIF::PvP) ? cmds.length : nil   # after Trade, before co-op's row
          cmds << KIF::PvP.menu_label if pv
          co = defined?(KIF::Coop) ? KIF::Coop.menu_label : nil   # last row: the rows above keep their places
          cmds << co if co
          note = KIF::Coop.take_notes.last || note if co
          help = note || help
          r = pick(lines.join("\n"), cmds, help,
                   proc { [Net.session&.connected?, Net.notes.length, co && KIF::Coop.menu_label, tr && KIF::Trade.menu_label, pv && KIF::PvP.menu_label,
                           defined?(KIF::Presence) && KIF::Presence.ghost&.map_id] })
          next if r.nil?
          note = nil
          return if r < 0
          next KIF::Coop.menu_pick if co && r == cmds.length - 1
          next KIF::Trade.menu_pick if tr && r == tr
          next KIF::PvP.menu_pick if pv && r == pv
          next add_player(s) if ad && r == ad
          next remove_player(s) if rm && r == rm
          r -= 1 if sl
          case r
          when -1
            KIF::SoulLink::Menu.open(@scr) if sl
          when 0
            s.post("wave")
            Net.notes.unshift(_INTL("Sent hello to {1}.", peers.map { |_, n, _| n }.join(" and ")))
          when 1
            next unless pbConfirmMessage(_INTL("Disconnect from {1}?", peers.map { |_, n, _| n }.join(" and ")))
            Net.stop
            return
          else return
          end
        end
      end

      # host of a game for three: the places left, and how a friend gets in (the code, or a Steam invite)
      def add_player(s)
        return pbMessage(_INTL("Your game is full.")) if s.full?
        if s.via == :steam
          return s.lobby ? steam_invite(s.lobby) : nil
        end
        code = Net.code
        return pbMessage(_INTL("The code isn't ready yet. Try again in a moment.")) unless code
        if Net.copy_code(code)
          pbMessage(_INTL("Code copied. Your next friend joins with it."))
        else
          pbMessage(_INTL("Copying didn't work. Your code is:\n{1}", code))
        end
      end

      def remove_player(s)
        slot = Net.pick_peer(_INTL("Take out which player?")) or return
        name = s.name_of(slot) or return
        return unless pbConfirmMessage(_INTL("Take {1} out of the game?", name))
        s.kick(slot)
      end
    end
  end
end

# a message box hides the help text of a Multiplayer screen under it (Screen.hush)
alias kif_net_pbCreateMessageWindow pbCreateMessageWindow unless defined?(kif_net_pbCreateMessageWindow)
alias kif_net_pbDisposeMessageWindow pbDisposeMessageWindow unless defined?(kif_net_pbDisposeMessageWindow)

def pbCreateMessageWindow(*args)
  KIF::Net::Screen.hush(1)
  return kif_net_pbCreateMessageWindow(*args)
end

def pbDisposeMessageWindow(*args)
  return kif_net_pbDisposeMessageWindow(*args)
ensure
  KIF::Net::Screen.hush(-1)
end

KIF::PauseMenu.add(:kif_multiplayer, "Multiplayer", icon: "menuIcons/PLAYER", order: 60,
  condition: proc { KIF::Net.menu_on? },
  handler: proc { |scene|
    scene.pbHideMenu if scene.respond_to?(:pbHideMenu)   # the pause menu draws over the screens (z 99999)
    KIF::Net::Menu.open
    :stay
  })

Events.onMapUpdate += proc { |_sender, _e| KIF::Net.map_update }

# the lobby host's relay (Net.pump) outside the map too
module Graphics
  class << self
    alias kif_netpump_update update unless method_defined?(:kif_netpump_update)

    def update(*args)
      r = kif_netpump_update(*args)
      KIF::Net.pump
      return r
    end
  end
end

at_exit { KIF::Net.shutdown rescue nil }
