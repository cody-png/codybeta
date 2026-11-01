#===============================================================================
# F-CORE-04 - what the player sees of mod safety (2026-11-01)
#
# Options > Mods: a short badge on every mod (OK, CHECK, RISK, NEEDS OK,
# TAMPERED), "What it can do", "Allow anything", "Blocked actions" and, for a
# mod KIF is holding back, "Review and allow". "Mod protection" and "About mod
# safety" are in Options > Others. A one-time notice on the map when a new or
# changed mod needs a look or the guard stopped something.
# Existing option rows and pbMessage lists only; no new drawing code.
#===============================================================================
KIF::Options.define(:kif_mod_guard, 1, :global)   # 0 Off, 1 Normal, 2 Strict, 3 Warn only

module KIF
  module ModSecurityUI
    module_function

    # short words for a line under the mod's name
    SHORT = {
      "network" => "uses the internet", "programs" => "starts programs", "native" => "calls Windows code",
      "game_files" => "changes game files", "save_files" => "changes saves and settings", "outside_files" => "reads files outside the game",
      "environment" => "reads computer settings", "clipboard" => "uses the clipboard", "load_code" => "loads outside code",
      "marshal" => "reads saved objects", "eval" => "builds code from text", "objectspace" => "looks at all loaded objects"
    }.freeze

    def active?; return defined?(KIF::ModTrust) && defined?(KIF::ModGuard) && defined?(KIF::ModCheck); end

    def rep(e)
      return nil unless active?
      return KIF::ModTrust.report_for(e.id)
    rescue StandardError
      return nil
    end

    # [text, color] for the Installed row, or nil (the row has its own BLOCKED / ERROR badges first)
    def badge(e)
      return nil unless active? && e.respond_to?(:kind) && e.kind != :mod_manager
      return [_INTL("TAMPERED"), KIF::PixelUI::DOWN] if KIF::ModGuard.tampered?(e.id)
      st = KIF::ModTrust.state(e.id)
      return [_INTL("NEEDS OK"), KIF::PixelUI::DOWN] if st == "held" || st == "revoked"
      rec = KIF::ModTrust.record(e.id)
      col = rec && rec["color"]
      return nil unless col
      return [_INTL("RISK"), KIF::PixelUI::DOWN] if col == "red"
      return [_INTL("CHECK"), KIF::PixelUI::WARN] if col == "yellow"
      return [_INTL("OK"), KIF::PixelUI::UP]
    rescue StandardError
      return nil
    end

    # "Can: uses the internet. Starts programs." for the mod's description line, and where it came from
    def describe(e)
      return nil unless active? && e.respond_to?(:kind) && e.kind != :mod_manager
      r = rep(e)
      return nil unless r
      held = r.held
      bits = []
      bits << (held.empty? ? _INTL("Can: nothing risky.") : _INTL("Can: {1}.", held.map { |p| SHORT[p] }.compact.first(4).join(", ")))
      rev = KIF::ModTrust.review_line(e.id)
      bits << rev if rev
      prov = (KIF::ModTrust.record(e.id) || {})["prov"].to_s
      bits << KIF::ModTrust.provenance_line(e.id) if prov.start_with?("changed")
      return bits.join(" ")
    rescue StandardError
      return nil
    end

    # the longer text: what the mod holds (with its own notes), what the scan found, where it came from
    def detail_text(e)
      r = rep(e)
      return _INTL("{1} has not been checked yet.", e.name) unless r
      out = []
      pl = r.permission_lines
      out << (pl.empty? ? _INTL("It does nothing KIF watches.") : _INTL("It can: {1}.", pl.join("; ")))
      notes = e.respond_to?(:permission_notes) ? e.permission_notes : {}
      notes.each { |k, t| out << "#{KIF::ModCheck::PERM_TEXT[k]}: #{t}" }
      unless r.undeclared.empty?
        out << _INTL("It does more than its mod.json says: {1}.", r.undeclared.map { |p| SHORT[p] }.compact.join(", "))
      end
      lines = r.lines(4)
      out << _INTL("KIF found: {1}", lines.join("; ")) unless lines.empty?
      out << KIF::ModTrust.provenance_line(e.id)
      rev = KIF::ModTrust.review_line(e.id)
      out << rev if rev
      st = KIF::ModTrust.state(e.id)
      out << _INTL("KIF is holding it back until you allow it.") if st == "held" || st == "revoked"
      out << _INTL("You allowed it to do anything.") if KIF::ModTrust.allow_all?(e.id)
      return out.join(" ")
    end

    def blocked_text(e)
      list = KIF::ModGuard.events(e.id)
      return _INTL("KIF stopped nothing from {1} this time.", e.name) if list.empty?
      lines = list.last(5).map { |ev| "#{ev.blocked ? 'Stopped' : 'Noted'}: #{KIF::ModGuard::WORDS[ev.permission] || ev.permission} (#{ev.detail[0, 40]})" }
      return _INTL("{1} stopped, {2} noted. Last: {3}", KIF::ModGuard.count(e.id), list.count { |ev| !ev.blocked }, lines.join("; "))
    end

    # [[key, label], ...] added to the USE menu of an installed mod
    def menu_items(e)
      return [] unless active? && e.respond_to?(:kind) && e.kind != :mod_manager && e.source.is_a?(KIF::Mods::NativeSource)
      items = [[:can, _INTL("What it can do")]]
      st = KIF::ModTrust.state(e.id)
      items << [:review, _INTL("Review and allow")] if st == "held" || st == "revoked"
      items << [:all, KIF::ModTrust.allow_all?(e.id) ? _INTL("Use its list") : _INTL("Allow anything")]
      items << [:blocked, _INTL("Blocked actions")]
      return items
    end

    def run_item(key, e)
      case key
      when :can then pbMessage(KIF::PixelFont.utf8(detail_text(e)))
      when :blocked then pbMessage(KIF::PixelFont.utf8(blocked_text(e)))
      when :review then review(e)
      when :all
        if KIF::ModTrust.allow_all?(e.id)
          KIF::ModTrust.set_allow_all(e.id, false)
          pbMessage(KIF::PixelFont.utf8(_INTL("{1} is held to its list again.", e.name)))
        elsif pbConfirmMessage(KIF::PixelFont.utf8(_INTL("Let {1} do anything, with no permission list? Only do this for a mod you trust.", e.name)))
          KIF::ModTrust.set_allow_all(e.id, true)
          pbMessage(KIF::PixelFont.utf8(_INTL("{1} may do anything now. KIF still notes what it does.", e.name)))
        end
      end
    end

    # the player looks at a held mod and lets it start (next time the game opens)
    def review(e)
      pbMessage(KIF::PixelFont.utf8(detail_text(e)))
      if pbConfirmMessage(KIF::PixelFont.utf8(_INTL("Allow {1}? It starts the next time the game opens.", e.name)))
        KIF::ModTrust.approve(e.id)
        pbMessage(KIF::PixelFont.utf8(_INTL("{1} is allowed.", e.name)))
      end
    end

    def about_text; return KIF::ModTrust.about_text; end

    # Why an install should be asked about (plain sentences, at most 6), or []: a withdrawn mod, a red
    # scan, or more than mod.json says. For an update only what is new counts.
    def install_reasons(item, rep)
      out = []
      r = KIF::ModTrust.revoked_item(item.id, item.version)
      out << _INTL("It was withdrawn: {1}.", r["reason"].to_s.sub(/[.\s]+\z/, "")) if r
      rec = KIF::ModTrust.record(item.folder)
      old = rec && rec["scan"].is_a?(Hash) ? KIF::ModCheck::Report.from_h(rec["scan"]) : nil
      low = lambda { |l| l.sub(/ \(.*\z/, "").sub(/\A./) { |c| c.downcase } }
      if old
        added = rep.held - old.held
        out << _INTL("It now also: {1}.", added.map { |p| SHORT[p] }.compact.join(", ")) unless added.empty? || rep.held.empty?
        out << _INTL("It now: {1}.", rep.lines(3).map(&low).join("; ")) if rep.color == :red && old.color != :red && rep.lines(3).any?
      else
        out << _INTL("It: {1}.", rep.lines(4).map(&low).join("; ")) if rep.color == :red
      end
      unless rep.undeclared.empty?
        out << _INTL("It uses what it did not list: {1}.", rep.undeclared.map { |p| SHORT[p] }.compact.join(", "))
      end
      return out.uniq.first(6)
    end

    # the question before an install: what the mod says it needs, and what is known about it
    def catalog_lines(item)
      return "" unless active?
      j = item.json
      perms = j["permissions"].is_a?(Array) ? (j["permissions"].select { |x| x.is_a?(String) } & KIF::ModCheck::PERMISSION_NAMES) : nil
      bits = []
      if perms.nil? then bits << _INTL("It does not list what it needs.")
      elsif perms.empty? then bits << _INTL("It says it needs nothing special.")
      else bits << _INTL("It says it: {1}.", perms.map { |p| SHORT[p] }.compact.first(5).join(", "))
      end
      r = KIF::ModTrust.revoked_item(item.id, item.version)
      bits << _INTL("It was withdrawn: {1}", r["reason"]) if r
      rv = KIF::ModTrust.lists["reviewed"][item.id]
      if rv
        bits << (rv["fingerprint"] == KIF::ModTrust.fingerprint_of_files(item.files) ? _INTL("Reviewed {1}.", rv["reviewed"]) : _INTL("Changed since it was reviewed."))
      end
      return bits.join(" ")
    rescue StandardError
      return ""
    end

    #---------------------------------------------------------------------------
    # One notice on the map: new or changed mods that need a look, and the first stop of a session
    #---------------------------------------------------------------------------
    def schedule
      return unless defined?(KIF::API) && KIF::API.respond_to?(:when_idle)
      KIF::API.when_idle("kif_mod_security") { pump }
    rescue StandardError
      nil
    end

    def pump
      msgs = []
      while (n = KIF::ModTrust.take_notice) && msgs.length < 3
        msgs << n[1]
      end
      g = KIF::ModGuard.take_notice
      msgs << g if g
      return if msgs.empty?
      pbMessage(KIF::PixelFont.utf8(msgs.join(" ")))
      if pbConfirmMessage(_INTL("Open Options > Mods to review?"))
        KIF::SettingsScreen.mods_view = 0 if KIF::SettingsScreen.respond_to?(:mods_view=)
        pbFadeOutIn { KifSettingsScreen.new(true, :mods).main }
      end
    rescue StandardError => ex
      KIF.log("Mod notice failed (#{ex.class}: #{ex.message})")
    end
  end
end

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Mod protection"), [_INTL("Off"), _INTL("Normal"), _INTL("Strict"), _INTL("Warn only")],
                 proc { $PokemonSystem.kif_mod_guard },
                 proc { |value| $PokemonSystem.kif_mod_guard = value; KIF::ModTrust.set_protection(value) },
                 [_INTL("No checks."), _INTL("Stops a mod from starting programs, using the internet or changing files it did not ask for."),
                  _INTL("Also stops it from reading your computer's settings or clipboard unasked."), _INTL("Only notes what mods do; stops nothing.")])
}

KIF::Options.add(:others, :global) {
  ButtonOption.new(_INTL("About mod safety"), proc { pbMessage(KIF::PixelFont.utf8(KIF::ModSecurityUI.about_text)) },
                   _INTL("What KIF can and cannot do about risky mods"))
}
