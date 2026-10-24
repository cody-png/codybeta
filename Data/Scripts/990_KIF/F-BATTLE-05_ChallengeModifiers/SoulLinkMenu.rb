#===============================================================================
# F-BATTLE-05 – Soul Link screens (mockups: Soul Link mockups SL3, Multiplayer
# mockups MP7a/MP7b). Pause menu "Soul Link" while Soul Link and Nuzlocke are
# On; also "Soul Link" on the Multiplayer connected screen.
#   Not linked: Link with <partner> (connected) / Show my link code / Enter
#     partner's link code. Linking shows the pairing screen (SL3).
#   Linked: Share update code / Paste partner's code (MP7a, MP7b) / Unlink.
#===============================================================================
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
        same_mode = info["m"] == $PokemonSystem.ch_sl_mode
        modes = [_INTL("Linked"), _INTL("Fused")]
        head = [_INTL("Soul Link"), _INTL("Partner: {1}", info["n"]),
                _INTL("Connection: {1}", net ? _INTL("Direct") : _INTL("Codes")),
                _INTL("Nuzlocke rules: {1}", same_rules ? _INTL("Same") : _INTL("Different")),
                _INTL("Link mode: {1}{2}", modes[$PokemonSystem.ch_sl_mode], same_mode ? "" : _INTL(" (theirs: {1})", modes[info["m"]])),
                _INTL("Pairs by: Place")]
        match = same_rules && same_mode
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
        r = pick(head.join("\n"), [_INTL("Share update code"), _INTL("Paste partner's code"), _INTL("Unlink"), _INTL("Back")],
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
        when 2
          return true unless pbConfirmMessage(_INTL("Unlink from {1}? Your run goes on alone.", name))
          SoulLink.unlink
        else return false
        end
        return true
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
