#===============================================================================
# F-NET-01 – Multiplayer: setting, pause-menu entry and the connection screens
# (mockups: Claude Docs/Base KIF/mockups/Multiplayer mockups, MP1-MP6)
#
# Setting: Options > System > Multiplayer: Off / On (default Off). PC only for
# now: hidden on phones until someone tests the network there.
# Pause menu "Multiplayer": Host a game / Join with a code / Join by address /
# Find on this network. Hosting and the connection go on while you play;
# Multiplayer shows them again. Phase 1 has one thing to do once connected:
# "Send hello" (the partner sees "<name> says hello!").
#===============================================================================
KIF::Options.define(:kif_multiplayer, 0, :global)   # 0 Off, 1 On

KIF::Options.add(:graphics, :global) {   # placed under System > Multiplayer (015_KIF_SettingsData)
  next nil if KIF.mobile?
  EnumOption.new(_INTL("Multiplayer"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_multiplayer },
                 proc { |value| $PokemonSystem.kif_multiplayer = value },
                 [_INTL("No Multiplayer entry in the pause menu."),
                  _INTL("Multiplayer in the pause menu: play with a friend over the internet or your network.")])
}

module KIF
  module Net
    @session = nil
    @pm = nil
    @pm_thread = nil
    @lan = nil
    @notes = []
    @cleanup = []

    class << self
      attr_reader :session, :pm, :notes
    end

    def self.menu_on?
      return false if KIF.mobile?
      return (($PokemonSystem.kif_multiplayer rescue 0) || 0).to_i == 1
    end

    def self.my_name
      n = ($Trainer.name rescue nil).to_s
      return n.empty? ? "Player" : n
    end

    def self.version; defined?(KIF::PORT_VERSION) ? KIF::PORT_VERSION : "?"; end

    def self.new_session
      stop
      @notes.clear
      return Session.new(my_name, version)
    end

    # Host directly: listen, then open the router in the background
    def self.start_hosting
      s = new_session
      port = s.host(Crypto.random(4)) or return nil
      @session = s
      @local = PortMap.local_ip
      @pm_thread = Thread.new { PortMap.open(port, local: @local) }
      @pm_thread.report_on_exception = false
      @lan = LAN.responder(my_name, lan_code) if lan_code
      log("hosting on port #{port}")
      return port
    end

    def self.start_relay_host(rhost, rport)
      s = new_session
      s.host_relay(rhost, rport, Crypto.random(16), Crypto.random(8))
      @session = s
      log("hosting through a relay")
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

    def self.stop
      if @session
        @session.close
        log("stopped")
      end
      @session = nil
      (@lan.close rescue nil) if @lan
      @lan = nil
      if @pm_thread
        t = @pm_thread
        @cleanup << Thread.new {
          m = (t.value rescue nil)
          PortMap.close(m[:mapping]) if m && m[:mapping]
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
    end

    # every frame on the map and in the screens below; never waits
    def self.update
      return unless @session
      if @pm.nil? && @pm_thread && !@pm_thread.alive?
        @pm = (@pm_thread.value rescue nil) || { status: :closed }
        @renew_at = now + 3600
        log("router: #{@pm[:status]}#{@pm[:via] ? " (#{@pm[:via]})" : ''}")
      end
      if @pm && @pm[:mapping] && now > @renew_at
        @renew_at = now + 3600
        m = @pm[:mapping]
        Thread.new { PortMap.renew(m) }.report_on_exception = false
      end
      s = @session
      s.poll.each do |ev|
        case ev[0]
        when :join_request
          log("#{ev[1]} asks to join")
        when :connected
          log("connected to #{ev[1]} (#{s.via})")
          KIF::SoulLink.on_connect(s) if defined?(KIF::SoulLink)
        when :message
          if ev[1] == "wave"
            @notes << _INTL("{1} says hello!", s.partner)
          elsif ev[1].start_with?("sl_") && defined?(KIF::SoulLink)
            begin
              KIF::SoulLink.receive(ev[1], ev[2])
            rescue => e
              log("Soul Link message failed (#{e.class}: #{e.message})")
            end
          end
        when :disconnected
          KIF::SoulLink.on_disconnect if defined?(KIF::SoulLink)
          @notes << (ev[1] == :bye ? _INTL("Your friend disconnected.") : _INTL("Lost the connection to your friend."))
          log("disconnected (#{ev[1]})")
        when :failed
          @failed = ev[1]
          log("joining failed (#{ev[1]})")
        end
      end
    end

    def self.take_failure; f = @failed; @failed = nil; f; end

    # "Let <name> join?" for a player who knew the code; called from the
    # screens below and on the map when nothing else is going on
    def self.ask_join
      s = @session
      return unless s&.asking? && !@asking
      begin
        @asking = true
        yes = pbConfirmMessage(_INTL("{1} wants to join your game. Let {1} join?", s.partner))
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

    def self.lan_code
      return nil unless @session && @session.via == :direct && @local && PortMap.ip_kind(@local) != :invalid
      return JoinCode.make(:v4, ip: @local, port: @session.port, secret: @session.secret)
    end

    def self.v6_code
      ip = PortMap.global_ipv6
      return nil unless ip && @session && @session.via == :direct
      return JoinCode.make(:v6, ip: ip, port: @session.port, secret: @session.secret)
    end

    # The code to send: through the router when it's open (or opened by
    # hand: the external address is known), else for this network only
    def self.code
      s = @session or return nil
      return JoinCode.make(:relay, room: s.room, secret: s.secret) if s.via == :relay
      return nil unless @pm
      ext = @pm[:external_ip]
      if @pm[:status] == :open
        return JoinCode.make(:v4, ip: ext, port: @pm[:external_port], secret: s.secret)
      elsif @pm[:status] == :closed && PortMap.ip_kind(ext) == :public
        return JoinCode.make(:v4, ip: ext, port: s.port, secret: s.secret)
      end
      return lan_code
    end

    def self.lan_only?; @pm && code == lan_code; end

    # "host:port", "[v6]:port", "v6" or "host"
    def self.parse_address(text, default_port)
      t = text.to_s.strip
      m = t.match(/\A\[([0-9a-fA-F:.]+)\](?::(\d{1,5}))?\z/) ||
          (t.count(":") >= 2 ? t.match(/\A([0-9a-fA-F:.]+)()\z/) : t.match(/\A([A-Za-z0-9.\-]+)(?::(\d{1,5}))?\z/))
      return nil unless m
      port = m[2].to_s.empty? ? default_port : m[2].to_i
      return nil unless port.between?(1, 65_535)
      return [m[1], port]
    end

    #===========================================================================
    # Screens
    #===========================================================================
    class Screen
      HEAD_H = 128
      HELP_H = 96

      def initialize
        @vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @vp.z = 99_990
        @head = Window_UnformattedTextPokemon.newWithSize("", 0, 0, Graphics.width, HEAD_H, @vp)
        @cmd = Window_CommandPokemon.newWithSize([""], 0, HEAD_H, Graphics.width, Graphics.height - HEAD_H - HELP_H, @vp)
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
        @cmd.index = 0
        @cmds = cmds.dup
      end

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
        [@head, @cmd, @help].each(&:dispose)
        @vp.dispose
      end
    end

    module Menu
      module_function

      def open
        unless Net.available?
          return pbMessage(_INTL("Multiplayer needs the game's network library, which this copy of the game doesn't have."))
        end
        @scr = Screen.new
        begin
          s = Net.session
          if s&.connected? then connected
          elsif s&.hosting? then hosting
          end
          main
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
          cmds = [_INTL("Host a game"), _INTL("Join with a code"), _INTL("Join by address"),
                  _INTL("Find on this network"), _INTL("Back")]
          case pick(_INTL("Play with a friend\nOne of you hosts, the other joins.\nNo account and no server needed."),
                    cmds, _INTL("Host: your friend joins your game.\nJoin: use the code your friend sent you."))
          when 0 then host
          when 1 then join_code
          when 2 then join_address
          when 3 then find_lan
          else return
          end
        end
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
          # a relay code (41 characters) doesn't fit on one line: Copy / Show
          lines = [_INTL("Host a game"), _INTL("Your code: {1}", relay ? _INTL("ready (Copy or Show)") : code || "...")]
          if relay
            lines << _INTL("Relay: {1}", s.relay.join(":"))
            lines << (s.state == :connecting ? _INTL("Connecting to the relay...") : _INTL("Friend joined: Not yet"))
          else
            lines << _INTL("Port: {1}    Router port: {2}", s.port, router_text(pm))
          end
          cmds = []
          acts = []
          add = proc { |text, act| cmds << text; acts << act }
          if relay || pm.nil? || pm[:status] == :open
            lines << _INTL("Friend joined: Not yet") if !relay && pm
            help = if !relay && pm.nil? then _INTL("Opening your router...\nThis takes a few seconds.")
                   elsif copied then _INTL("Code copied. Waiting for them to join...")
                   else _INTL("Ready. Send this code to your friend.\nWaiting for them to join...")
                   end
            if code
              add.call(_INTL("Copy code"), :copy)
              add.call(_INTL("Show code bigger"), :big)
            end
          elsif pm[:status] == :shared
            help = _INTL("Your internet provider shares one address between many homes, so nobody can reach this PC. Joining still works.")
            add.call(_INTL("Ask your friend to host instead"), :swap)
            add.call(_INTL("Use a relay"), :relay)
            add.call(_INTL("Copy IPv6 code"), :v6) if Net.v6_code
            add.call(_INTL("Copy code for this network"), :copy) if code
          else
            help = _INTL("Your router didn't let the game open a door for your friend, so they can't reach you yet.")
            add.call(_INTL("Ask your friend to host instead"), :swap)
            add.call(_INTL("Open port {1} yourself (how?)", s.port), :how)
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
            copied = (Input.clipboard = code rescue nil) ? true : false
            pbMessage(_INTL("Copying didn't work. Your code is:\n{1}", code)) unless copied
          when :v6
            c = Net.v6_code
            pbMessage(_INTL("This code works if your friend also has IPv6:\n{1}", c)) unless (Input.clipboard = c rescue nil)
          when :big
            pbMessage(_INTL("Your code:\n{1}", code))
          when :how then how_to_open(s.port)
          when :swap
            next unless pbConfirmMessage(_INTL("Stop hosting and join with your friend's code instead?"))
            Net.stop
            return join_code
          when :relay
            r2 = ask_relay or next
            Net.start_relay_host(*r2)
          when :stop
            next unless pbConfirmMessage(_INTL("Stop hosting?"))
            Net.stop
            return
          end
        end
      end

      def how_to_open(port)
        local = PortMap.local_ip || "?"
        gw = PortMap.gateway_guess(local) || "192.168.1.1"
        pbMessage(_INTL("1. Open your router's page in a browser (often {1}, on its sticker).\n2. Find \"Port forwarding\".", gw))
        pbMessage(_INTL("3. Add: port {1}, TCP, to this PC: {2}.\n4. Save, then host again.", port, local))
        pbMessage(_INTL("Do this once. The game will find it open next time you host."))
      end

      #-------------------------------------------------------------------------
      # Relay (MP6a)
      #-------------------------------------------------------------------------
      def ask_relay
        text = ""
        loop do
          lines = _INTL("Use a relay\nBoth of you use the same address.\n{1}", text.empty? ? "_" : text)
          r = pick(lines, [_INTL("Type the address"), _INTL("Paste"), _INTL("Connect"), _INTL("Back")],
                   _INTL("A relay is a PC run by someone else that passes messages between you. KIF has none built in."))
          case r
          when 0 then text = (pbMessageFreeText(_INTL("Relay address:"), text, false, 80) || text).strip
          when 1 then text = (Input.clipboard.to_s rescue "").strip[0, 80]
          when 2
            addr = Net.parse_address(text, Net::RELAY_PORT)
            return addr if addr
            pbMessage(_INTL("That isn't an address. It looks like relay.example.net or 203.0.113.5:52413."))
          else return nil
          end
        end
      end

      #-------------------------------------------------------------------------
      # Joining (MP5a, MP5b, MP5c)
      #-------------------------------------------------------------------------
      def join_code(address = nil)
        clip = (Input.clipboard.to_s rescue "").strip
        text = Net::JoinCode.read(clip).is_a?(Hash) ? clip : ""
        loop do
          st = text.empty? ? nil : Net::JoinCode.read(text)
          help = if st.nil? then _INTL("Type or paste the code your friend sent.")
                 elsif st.is_a?(Hash) then _INTL("Code looks right.")
                 elsif st == :typo then _INTL("A letter or number in the code is wrong. Check it with your friend.")
                 else _INTL("That isn't a join code. Join codes start with KIF-.")
                 end
          head = _INTL("Join with a code\n{1}", text.empty? ? "_" : text.scan(/.{1,30}/).join("\n"))
          head += "\n" + _INTL("Address: {1}", address.join(":")) if address
          case pick(head, [_INTL("Type the code"), _INTL("Paste"), _INTL("Connect"), _INTL("Back")], help)
          when 0 then text = (pbMessageFreeText(_INTL("Join code:"), text, false, 60) || text).strip
          when 1 then text = (Input.clipboard.to_s rescue "").strip[0, 60]
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
        t = pbMessageFreeText(_INTL("Address of your friend's game (for example 100.101.102.103):"), "", false, 60)
        return if t.nil? || t.strip.empty?
        addr = Net.parse_address(t, Net::PORT)
        return pbMessage(_INTL("That isn't an address. It looks like 100.101.102.103 or 100.101.102.103:52411.")) unless addr
        pbMessage(_INTL("Now the code your friend sent: it holds the key. The address you typed is used instead of the one in the code."))
        join_code(addr)
      end

      # :done when connected and back from the connected screen
      def connect(info, relay, address)
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
            wait: _INTL("Too many wrong codes were tried from here. Try again in 10 minutes."),
            relay: _INTL("The relay didn't accept you. Check the address, or ask your friend to host on it again."),
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
        until t.join(0)
          pick_once(_INTL("Find on this network\nLooking for games on this network..."), [_INTL("Cancel")], "")
        end
        list = (t.value rescue []) || []
        if list.empty?
          return pbMessage(_INTL("No games found on this network. Your friend needs to host first, and both PCs need to be on the same network."))
        end
        names = list.map { |n, _| n } + [_INTL("Back")]
        i = pbMessage(_INTL("Games on this network:"), names, names.length)
        connect(list[i][1], nil, nil) if i < list.length
      end

      def pick_once(head, cmds, help)
        @scr.show(head, cmds, help)
        @scr.frame
      end

      #-------------------------------------------------------------------------
      # Connected (MP5b, MP6b)
      #-------------------------------------------------------------------------
      def connected
        loop do
          s = Net.session
          unless s&.connected?
            pbMessage(Net.notes.shift || _INTL("The connection ended."))
            Net.notes.clear
            Net.stop unless s&.hosting?
            return
          end
          relay = s.via == :relay
          lines = [_INTL("Connected"), _INTL("Connected to: {1}", s.partner),
                   relay ? _INTL("Connection: Through relay ({1})", s.relay.join(":")) : _INTL("Connection: Direct")]
          if s.partner_ver != Net.version
            lines << _INTL("{1} has KIF {2}, you have KIF {3}.", s.partner, s.partner_ver, Net.version)
          end
          help = Net.notes.shift ||
                 (relay ? _INTL("Connected through relay.\nPlay works the same, just a bit slower.")
                        : _INTL("Connected to {1} (direct).\nYour games talk to each other directly.", s.partner))
          sl = defined?(KIF::SoulLink) && KIF::SoulLink.on?
          cmds = [_INTL("Send hello"), _INTL("Disconnect")]
          cmds.unshift(_INTL("Soul Link")) if sl
          r = pick(lines.join("\n"), cmds, help, proc { [Net.session&.connected?, Net.notes.length] })
          next if r.nil?
          return if r < 0
          r -= 1 if sl
          case r
          when -1
            KIF::SoulLink::Menu.open(@scr) if sl
          when 0
            s.post("wave")
            Net.notes.unshift(_INTL("Sent hello to {1}.", s.partner))
          when 1
            next unless pbConfirmMessage(_INTL("Disconnect from {1}?", s.partner))
            Net.stop
            return
          else return
          end
        end
      end
    end
  end
end

KIF::PauseMenu.add(:kif_multiplayer, "Multiplayer", icon: "menuIcons/PLAYER", order: 60,
  condition: proc { KIF::Net.menu_on? },
  handler: proc { |_scene|
    KIF::Net::Menu.open
    :stay
  })

Events.onMapUpdate += proc { |_sender, _e|
  if KIF::Net.session
    KIF::Net.update
    KIF::Net.ask_join if KIF::Net.session&.asking? && KIF::Net.quiet?
  end
}

at_exit { KIF::Net.shutdown rescue nil }
