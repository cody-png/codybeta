#===============================================================================
# F-BATTLE-05 – Soul Link screens (mockups: Soul Link mockups SL3, Multiplayer
# mockups MP7a/MP7b). Pause menu "Soul Link" while Soul Link and Nuzlocke are
# On; also "Soul Link" on the Multiplayer connected screen.
#   Not linked: Link with <partner> (connected) / Show my link code / Enter
#     partner's link code. Linking shows the pairing screen (SL3).
#   Linked: Share update code / Paste partner's code (MP7a, MP7b) / Pairs /
#     Soul Link log / Unlink.
# Phase 4 (2026-10-24): pairs list and log (lists with columns), the death
# card (SL2), the partner's icon and a dot on each party panel and a Soul Link
# box in the party screen (SL1), "Soul Link: <partner>" on the load screen.
#===============================================================================

# A list whose rows may have columns: [[text, x, width, align], ...], with
# :grey last for a greyed row. Text rows draw as usual.
class Window_KifSLRows < Window_CommandPokemon
  def drawItem(index, count, rect)
    row = @commands[index]
    return super unless row.is_a?(Array)
    rect = drawCursor(index, rect)
    base, shadow = row.last == :grey ? KIF::SoulLink::Menu.grey(windowskin) : [baseColor, shadowColor]
    pbSetSmallFont(contents)
    row.each { |c| pbDrawShadowText(contents, rect.x + c[1], rect.y, c[2], rect.height, c[0].to_s, base, shadow, c[3] || 0) if c.is_a?(Array) }
    pbSetSystemFont(contents)
  end
end

module KIF
  module SoulLink
    module Menu
      module_function

      def open(scr = nil)
        @scr = scr || KIF::Net::Screen.new
        begin
          SoulLink.apply_pending
          loop { break unless SoulLink.on? && (SoulLink.linked? ? linked : not_linked) }
        ensure
          @scr.dispose unless scr
          @scr = nil
        end
      end

      def pick(head, cmds, help, watch = nil)
        was = watch&.call
        loop do
          @scr.show(head, cmds, help)
          r = @scr.frame
          return r if r
          return nil if watch && watch.call != was
        end
      end

      def clip; (Input.clipboard.to_s rescue "").strip; end
      def say(text); pbMessage(text); true; end
      def copy(text); (Input.clipboard = text) ? true : false; rescue StandardError; false; end

      # true: show the screen again
      def not_linked
        s = SoulLink.session
        head = [_INTL("Soul Link"), _INTL("Not linked yet.")]
        head << (s ? _INTL("Connected to: {1}", s.partner) : _INTL("Not connected"))
        cmds = []
        acts = []
        if s
          cmds << _INTL("Link with {1}", s.partner)
          acts << :net
        end
        cmds += [_INTL("Show my link code"), _INTL("Enter partner's link code"), _INTL("Back")]
        acts += [:show, :enter, :back]
        help = _INTL("Link your run with a friend's. Connect in Multiplayer first, or swap link codes.")
        r = pick(head.join("\n"), cmds, help, proc { [SoulLink.session.nil?, SoulLink.linked?] })
        return true if r.nil?
        case r < 0 ? :back : acts[r]
        when :net
          info = SoulLink.peer_info
          return say(_INTL("{1}'s game has Soul Link Off, or no Nuzlocke run.", s.partner)) unless info.is_a?(Hash)
          return true unless pairing(info, true)
          return true if SoulLink.ask_link == :linked
          wait_partner(s.partner)
        when :show
          code = SoulLink.link_code
          pbMessage(copy(code) ? _INTL("Your link code is copied. Send it to your partner:\n{1}", code) :
                                 _INTL("Your link code. Send it to your partner:\n{1}", code))
        when :enter
          text = clip
          text = (pbMessageFreeText(_INTL("Partner's link code:"), "", false, 200) || "") unless text.upcase.start_with?("KIFLINK")
          info = SoulLink.read_link_code(text)
          return say(_INTL("That isn't a link code. Link codes start with KIFLINK-.")) if info == :invalid
          return say(_INTL("A letter or number in the code is wrong. Check it with your partner.")) if info == :typo
          return say(_INTL("That's your own link code. Enter your partner's.")) if info["h"] == SoulLink.my_half
          return true unless pairing(info, false)
          SoulLink.link_with(info)
          pbMessage(_INTL("Linked with {1}. Send {1} your link code too, if you haven't yet.", info["n"]))
        else return false
        end
        return true
      end

      # SL3: true when the player picks Link
      def pairing(info, net)
        same_rules = info["set"] == SoulLink.rules_hash
        same_game = info["g"] == SoulLink.game_hash
        same_mode = info["m"] == $PokemonSystem.ch_sl_mode
        modes = [_INTL("Linked"), _INTL("Fused")]
        head = [_INTL("Soul Link"), _INTL("Partner: {1}", info["n"]),
                _INTL("Connection: {1}", net ? _INTL("Direct") : _INTL("Codes")),
                _INTL("Nuzlocke rules: {1}", same_rules ? _INTL("Same") : _INTL("Different")),
                _INTL("Game mode / randomizer: {1}", same_game ? _INTL("Same") : _INTL("Different")),
                _INTL("Link mode: {1}{2}", modes[$PokemonSystem.ch_sl_mode], same_mode ? "" : _INTL(" (theirs: {1})", modes[info["m"]])),
                _INTL("Pairs by: Place")]
        match = same_rules && same_game && same_mode
        help = match ? _INTL("Both runs match. Link with {1}?\nDeaths will be shared from now on.", info["n"]) :
                       _INTL("Your settings differ from {1}'s. You can link anyway.", info["n"])
        loop do
          r = pick(head.join("\n"), [_INTL("Link"), _INTL("Cancel")], help)
          next if r.nil?
          return false unless r == 0
          return true if match || pbConfirmMessage(_INTL("Your settings differ. Link with {1} anyway?", info["n"]))
        end
      end

      def wait_partner(name)
        loop do
          return pbMessage(_INTL("Linked with {1}. Deaths are shared from now on.", name)) if SoulLink.linked?
          return pbMessage(_INTL("The connection ended before you were linked.")) unless SoulLink.session
          r = pick(_INTL("Soul Link\nWaiting for {1} to pick Link too...", name), [_INTL("Cancel")],
                   _INTL("{1} opens Soul Link and picks Link with you.", name), proc { [SoulLink.linked?, SoulLink.session.nil?] })
          next if r.nil?
          SoulLink.instance_variable_set(:@asked, false)
          return
        end
      end

      def linked
        name = SoulLink.partner
        n = SoulLink.unsent
        head = [SoulLink.connected? ? _INTL("Soul Link: {1} (connected)", name) : _INTL("Soul Link: {1} (not connected)", name)]
        head << (SoulLink.connected? ? _INTL("Your events go to {1} as they happen.", name) :
                                       _INTL("Events {1} doesn't have yet: {2}", name, n))
        head += SoulLink.warnings
        help = SoulLink.take_notes.map { |l| l.reject(&:empty?).join(": ") }.first ||
               _INTL("No connection? Send updates as text.")
        r = pick(head.join("\n"), [_INTL("Share update code"), _INTL("Paste partner's code"), _INTL("Pairs"),
                                   _INTL("Soul Link log"), _INTL("Unlink"), _INTL("Back")],
                 help, proc { [SoulLink.connected?, SoulLink.unsent, SoulLink.pending?] })
        if r.nil?
          SoulLink.apply_pending
          return true
        end
        case r
        when 0
          code = SoulLink.my_update_code
          ok = copy(code)
          pbMessage(ok ? _INTL("Copied. Paste it to {1} in Discord.\nIt holds your {2} new events.", name, n) :
                         _INTL("Your update code ({1} new events):\n{2}", n, code))
        when 1 then paste(name)
        when 2 then pairs_list(name)
        when 3 then log_list(name)
        when 4
          return true unless pbConfirmMessage(_INTL("Unlink from {1}? Your run goes on alone.", name))
          SoulLink.unlink
        else return false
        end
        return true
      end

      #-------------------------------------------------------------------------
      # Lists: pairs and the log (Back leaves)
      #-------------------------------------------------------------------------
      def grey(skin)
        return isDarkWindowskin(skin) ? [Color.new(136, 136, 136), Color.new(64, 64, 64)] :
                                        [Color.new(168, 168, 176), Color.new(216, 216, 224)]
      end

      def table(head, rows, help)
        t = KIF::Net::Screen.new(Window_KifSLRows)
        loop do
          t.show(head, rows, help)
          r = t.frame
          break if r && r < 0
        end
      ensure
        t&.dispose
      end

      STATE_TEXT = { alive: "alive", hurt: "hurt", dead: "dead", missed: "no pair", waiting: "waiting", open: "waiting" }

      def my_name_of(id)
        p, = SoulLink.find(id)
        return p.name if p
        ev = SoulLink.state[:my_log].find { |e| e["k"] == "c" && e["i"] == id }
        return ev ? ev["n"] : "?"
      end

      # place, your Pokémon, the partner's, how the pair is; dead and lost greyed
      def pairs_rows
        SoulLink.pairs.map do |r|
          mine = r[:mine].is_a?(String) ? my_name_of(r[:mine]) : r[:mine] == :missed ? _INTL("no catch") : "-"
          theirs = r[:theirs].is_a?(Hash) ? SoulLink.their_name(r) : r[:theirs] == :missed ? _INTL("no catch") : "-"
          row = [[r[:place], 0, 150], [mine, 156, 108], [theirs, 270, 108], [_INTL(STATE_TEXT[r[:state]]), 384, 76, 1]]
          [:dead, :missed].include?(r[:state]) ? row + [:grey] : row
        end
      end

      def pairs_list(name)
        rows = pairs_rows
        return say(_INTL("No pairs yet. Your first catch in each place pairs with {1}'s first catch there.", name)) if rows.empty?
        n = SoulLink.pairs.map { |r| r[:state] }
        head = _INTL("Soul Link pairs with {1}\nPlace, your Pokémon, {1}'s Pokémon", name)
        help = _INTL("{1} alive, {2} waiting, {3} dead or without a pair.", n.count { |s| [:alive, :hurt].include?(s) },
                     n.count { |s| [:waiting, :open].include?(s) }, n.count { |s| [:dead, :missed].include?(s) })
        table(head, rows, help)
      end

      def event_text(e)
        case e["k"]
        when "c" then _INTL("Caught {1}, {2}", SoulLink.species_name(e["s"]), e["p"])
        when "m" then _INTL("No catch, {1}", e["p"])
        when "d" then e["x"] ? _INTL("{1} died with its pair", e["n"]) : _INTL("{1} died, {2}", e["n"], e["p"])
        else _INTL("Run over")
        end
      end

      # both players' events, newest first: time, who, what, Debug mark
      def log_rows(name)
        st = SoulLink.state
        evs = st[:my_log].map { |e| [e, SoulLink.my_name] } + st[:their_log].map { |e| [e, name] }
        evs.sort_by { |e, _w| [e["t"] || 0, e["q"]] }.reverse.map do |e, who|
          time = e["t"] ? Time.at(e["t"]).strftime("%m-%d %H:%M") : "--"
          [[time, 0, 92], [who, 96, 84], [event_text(e), 184, 222], [e["dbg"] ? _INTL("Debug") : nil, 410, 50, 1]]
        end
      end

      def log_list(name)
        rows = log_rows(name)
        return say(_INTL("Nothing has happened since you linked with {1}.", name)) if rows.empty?
        table(_INTL("Soul Link log with {1}\nNewest first", name), rows,
              _INTL("Debug: made while Debug mode was on."))
      end

      #-------------------------------------------------------------------------
      # SL2: the death card, above the message while it shows
      #-------------------------------------------------------------------------
      def death_card(lines, their_species, mine)
        parts = []
        begin
          vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
          vp.z = 99_999
          parts << vp
          win = Window_UnformattedTextPokemon.newWithSize("", 12, 12, 352, 84, vp)
          parts.unshift(win)
          txt = BitmapSprite.new(352, 84, vp)
          txt.x = txt.y = 12
          txt.z = 2
          parts.unshift(txt)
          pbSetSystemFont(txt.bitmap)
          base, shadow = getDefaultTextColors(win.windowskin)
          pbDrawTextPositions(txt.bitmap, [[lines[0], 76, 12, 0, base, shadow], [lines[1], 76, 42, 0, base, shadow]])
          data = their_species && GameData::Species.try_get(their_species.to_s.to_sym)
          [[data && Pokemon.new(data.id, 1), 46], [mine, 318]].each do |pk, x|
            next unless pk
            s = PokemonIconSprite.new(pk, vp)
            s.setOffset(PictureOrigin::Center)
            s.x = 12 + x
            s.y = 12 + 42
            s.z = 3
            s.tone = Tone.new(0, 0, 0, 255)   # grey
            parts.unshift(s)
          end
        rescue StandardError => e
          KIF.log("Soul Link: death card failed (#{e.class}: #{e.message})")
        end
        yield
      ensure
        parts.each { |s| s.dispose rescue nil }
      end

      #-------------------------------------------------------------------------
      # SL1: party panels and the party screen's Soul Link box
      #-------------------------------------------------------------------------
      ICON_RECT = [222, 58, 32, 32]   # the partner's icon, half size, below the HP numbers
      DOT_POS   = [238, 46]
      DOT_COLORS = { alive: [96, 216, 96], hurt: [248, 200, 40], dead: [232, 64, 64], missed: [232, 64, 64], waiting: [168, 168, 168] }
      # 5x5 at the party's 2x pixel size: o outline, x colour
      DOT_ROWS = [" ooo ", "oxxxo", "oxxxo", "oxxxo", " ooo "]

      def draw_dot(bmp, x, y, rgb)
        fill = Color.new(*rgb)
        line = Color.new(40, 40, 40)
        DOT_ROWS.each_with_index do |row, j|
          row.chars.each_with_index { |c, i| bmp.fill_rect(x + i * 2, y + j * 2, 2, 2, c == "o" ? line : fill) unless c == " " }
        end
      end

      def draw_icon(bmp, species, rect, opacity = 255)
        data = GameData::Species.try_get(species.to_s.to_sym) or return
        spr = PokemonIconSprite.new(Pokemon.new(data.id, 1))
        src = spr.bitmap
        bmp.stretch_blt(Rect.new(*rect), src, Rect.new(0, 0, src.height, src.height), opacity) if src
      rescue StandardError => e   # no icon file: the dot still shows
        KIF.log("Soul Link: no icon for #{species} (#{e.class}: #{e.message})")
      ensure
        spr&.dispose
      end

      def draw_partner(bmp, pkmn)
        r = SoulLink.pair_of(pkmn) or return
        if r[:theirs].is_a?(Hash)
          draw_icon(bmp, (r[:snap] && r[:snap][0]) || r[:theirs][:s], ICON_RECT, r[:state] == :dead ? 128 : 255)
        end
        draw_dot(bmp, *DOT_POS, DOT_COLORS[r[:state]] || DOT_COLORS[:waiting])
      end

      def party_prompts; [_INTL("Choose a Pokémon."), _INTL("Choose Pokémon or cancel.")]; end

      # [line 1, line 2] of the box: the link, then the selected Pokémon's pair
      def party_lines(pkmn)
        name = SoulLink.partner
        n = SoulLink.unsent
        top = SoulLink.connected? ? _INTL("Linked with {1} (connected)", name) :
              n > 0 ? _INTL("Linked with {1} (not connected, {2} to send)", name, n) :
                      _INTL("Linked with {1} (not connected)", name)
        return [top, ""] unless pkmn
        r = SoulLink.pair_of(pkmn)
        return [top, _INTL("{1} has no pair.", pkmn.name)] unless r
        t = r[:theirs]
        who = SoulLink.their_name(r)
        line = case r[:state]
               when :waiting then _INTL("{1}: waiting for {2}'s catch", r[:place], name)
               when :missed  then _INTL("{1}: no pair", r[:place])
               when :dead    then _INTL("{1}: dead, {2}", who, r[:place])
               else
                 s = r[:snap]
                 s ? _INTL("{1}: Lv. {2}  {3}/{4} HP, {5}", who, s[1], s[2], s[3], r[:place]) :
                     _INTL("{1} ({2}), {3}", who, SoulLink.species_name(t[:s]), r[:place])
               end
        return [top, line]
      end

      # MP7b
      def paste(name)
        text = clip
        text = (pbMessageFreeText(_INTL("{1}'s update code:", name), "", false, 2000) || "") unless text.upcase.start_with?("KIFSL")
        h = SoulLink.read_update_code(text)
        return pbMessage(_INTL("That isn't a Soul Link update code. They start with KIFSL-.")) if h == :invalid
        return pbMessage(_INTL("That code is from another link, or a letter in it is wrong.")) if h == :key
        return unless h.is_a?(Hash)
        lines, count = SoulLink.receive_update(h)
        return pbMessage(_INTL("Nothing new in that code. You're up to date.")) if count == 0
        deaths = h["e"].count { |e| e["k"] == "d" }
        rows = lines.map { |l, r| r.to_s.empty? ? l : "#{l}  -  #{r}" } + [_INTL("OK")]
        own = h["f"] == SoulLink.state[:side]
        loop do
          r = pick(own ? _INTL("Soul Link: your own events") : _INTL("Soul Link: {1}'s update", name), rows,
                   _INTL("{1} events applied, {2} of them deaths.\nNow you're up to date.", count, deaths))
          break if r && (r < 0 || r == rows.length - 1)
        end
        SoulLink.apply_pending
      end
    end
  end
end

#-------------------------------------------------------------------------------
# SL1 hooks: each panel draws the partner's icon and a dot; the party screen's
# help box ("Choose a Pokémon.") shows the link and the selected Pokémon's
# pair instead (the help text is hidden under it, never changed)
#-------------------------------------------------------------------------------
class PokemonPartyPanel
  alias kif_sl_refresh refresh unless method_defined?(:kif_sl_refresh)

  def refresh
    redraw = @refreshBitmap
    kif_sl_refresh
    begin
      return unless redraw && @pokemon && KIF::SoulLink.linked?
      return unless @overlaysprite && !@overlaysprite.disposed? && @overlaysprite.bitmap
      KIF::SoulLink::Menu.draw_partner(@overlaysprite.bitmap, @pokemon)
    rescue StandardError => e
      KIF.log("Soul Link: party icon failed (#{e.class}: #{e.message})")
    end
  end
end

class PokemonParty_Scene
  alias kif_sl_update update unless method_defined?(:kif_sl_update)

  def update
    ret = kif_sl_update
    begin
      kif_sl_box if @sprites && !@kif_sl_failed && (@sprites["kif_sl_box"] || KIF::SoulLink.linked?)
    rescue StandardError => e
      @kif_sl_failed = true
      KIF.log("Soul Link: party box failed (#{e.class}: #{e.message})")
    end
    return ret
  end

  def kif_sl_box
    help = @sprites["helpwindow"]
    return unless help && !help.disposed?
    box = @sprites["kif_sl_box"]
    show = help.visible && KIF::SoulLink.linked? && KIF::SoulLink::Menu.party_prompts.include?(help.text)
    help.contents_opacity = show ? 0 : 255 if help.contents_opacity != (show ? 0 : 255)
    unless box
      return unless show
      box = @sprites["kif_sl_box"] = BitmapSprite.new(Graphics.width, 64, @viewport)
      box.z = help.z + 1
    end
    box.visible = show
    return unless show
    box.x = help.x
    box.y = help.y
    key = [@activecmd, Graphics.frame_count / 30]   # the pair is looked up twice a second at most
    return if key == @kif_sl_key
    @kif_sl_key = key
    pkmn = @activecmd.is_a?(Integer) && @activecmd < Settings::MAX_PARTY_SIZE ? @party[@activecmd] : nil
    lines = KIF::SoulLink::Menu.party_lines(pkmn)
    return if lines == @kif_sl_lines
    @kif_sl_lines = lines
    bmp = box.bitmap
    bmp.clear
    base, shadow = getDefaultTextColors(help.windowskin)
    pbSetSystemFont(bmp)
    pbDrawShadowText(bmp, 16, 4, help.width - 32, 26, lines[0], base, shadow)
    pbSetSmallFont(bmp)
    pbDrawShadowText(bmp, 16, 30, help.width - 32, 22, lines[1], base, shadow)
  end
end

#-------------------------------------------------------------------------------
# Load screen: "Soul Link: <partner>" on the Continue panel, under the name
#-------------------------------------------------------------------------------
module KIF
  module SoulLink
    class << self
      attr_accessor :load_partner   # the partner of the save the load screen shows
    end

    def self.saved_partner(save_data)
      return nil unless save_data.is_a?(Hash)
      set = save_data[:kif_save_settings]
      g = save_data[:global_metadata]
      return nil unless set.is_a?(Hash) && set[:ch_soullink] == 1 && g.respond_to?(:kif_soullink)
      st = g.kif_soullink
      return st.is_a?(Hash) && st[:key] ? st[:partner_name] : nil
    end
  end
end

class PokemonLoadScreen
  alias kif_sl_load_save_file load_save_file unless method_defined?(:kif_sl_load_save_file)

  def load_save_file(*args)
    ret = kif_sl_load_save_file(*args)
    begin
      KIF::SoulLink.load_partner = KIF::SoulLink.saved_partner(ret)
    rescue StandardError => e
      KIF::SoulLink.load_partner = nil
      KIF.log("Soul Link: save check failed (#{e.class}: #{e.message})")
    end
    return ret
  end
end

class PokemonLoadPanel
  alias kif_sl_refresh refresh unless method_defined?(:kif_sl_refresh)

  def refresh
    redraw = @refreshBitmap && !@refreshing && !disposed?
    kif_sl_refresh
    return unless redraw && @isContinue && (name = KIF::SoulLink.load_partner)
    return if @trainer.respond_to?(:kif_nz_failed) && @trainer.kif_nz_failed   # "Nuzlocke over" is there
    begin
      pbSetSmallFont(self.bitmap)
      pbDrawShadowText(self.bitmap, 112, 76, 140, 24, _INTL("Soul Link: {1}", name), TEXTCOLOR, TEXTSHADOWCOLOR)
      pbSetSystemFont(self.bitmap)
    rescue StandardError => e
      KIF.log("Soul Link: load-screen line failed (#{e.class}: #{e.message})")
    end
  end
end
