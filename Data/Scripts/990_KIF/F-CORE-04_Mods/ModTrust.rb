#===============================================================================
# F-CORE-04 - what KIF knows about each mod's safety (2026-11-01)
#
# KIF_ModTrust.json in the save folder: for every mod its state, the scan
# (ModCheck.scan) it had when it was last looked at, the permissions the
# player added by hand and whether the player said "allow anything".
#
#   grandfathered  was there before this check existed; never held
#   approved       scanned green, or the player reviewed it
#   new            scanned yellow: loads, the player is told once
#   held           scanned red (or revoked): does not load until the player
#                  allows it in Options > Mods
#
# Honest limits: this is a consent and audit system. Mods run in the game's
# own process with the player's rights; see ModGuard.rb and MODDING.md.
# Plain data only, written with the mod list's own JSON writer, read with
# MiniJSON (never the game's JSON, which parses by eval).
#===============================================================================
module KIF
  module ModTrust
    FILE         = "KIF_ModTrust.json"
    LISTS_FILE   = "KIF_ModRevoked.json"   # the catalogs' reviewed and revoked lists, as last read
    PROVENANCE   = ".kif_provenance"
    LIST_TIME    = 24 * 3600               # the lists are read at most once a day
    MAX_LIST     = 256 * 1024
    MAX_SCANS    = 400
    STATES       = %w[grandfathered approved new held revoked].freeze
    ABOUT = "Mods are programs. KIF checks each mod and shows what it says it needs. KIF cannot lock a mod in a box: " \
            "a mod runs with the same rights as the game. The checks catch honest mistakes and common tricks, not a " \
            "determined attacker. Only install mods you trust. Turn a mod Off or delete its folder to remove it. " \
            "Options > Mods > Mod protection changes how strict KIF is, and you can allow anything for a mod you trust."

    @data = nil
    @native = nil
    @first_run = false
    @reports = {}
    @pcache = {}
    @notices = []
    @lists = nil

    def self.about_text; return ABOUT; end
    def self.path; return File.join(KIF.save_dir, FILE); end
    def self.first_run?; return @first_run; end

    # Mutators (approve, allow anything, grant) are for the player's menu: a mod that calls one is stopped
    def self.deny_mod_caller!(what, locs)
      owner = KIF::ModContract.caller_owner(locs) if defined?(KIF::ModContract)
      return unless owner
      KIF::ModGuard.deny_call!(owner, what)
    end

    #---------------------------------------------------------------------------
    # The file
    #---------------------------------------------------------------------------
    def self.reset!
      @data = nil
      @native = nil
      @first_run = false
      @reports = {}
      @pcache = {}
      @notices = []
      @lists = nil
      @dirty = false
    end

    def self.reset_cache; @pcache = {}; end

    def self.fresh_data; return { "format" => 1, "mods" => {}, "scans" => {} }; end

    def self.read_file
      p = path
      return nil unless File.file?(p)
      return nil if File.size(p) > 8 * 1024 * 1024
      h = KIF::Mods::MiniJSON.parse(File.read(p, encoding: "UTF-8"))
      return nil unless h.is_a?(Hash) && h["mods"].is_a?(Hash)
      h["scans"] = {} unless h["scans"].is_a?(Hash)
      return h
    rescue StandardError => e
      KIF.log("Mod trust: #{FILE} not read (#{e.class}: #{e.message})")
      return nil
    end

    def self.data
      @data ||= fresh_data
      return @data
    end

    def self.mods; return data["mods"]; end

    # one read of the file per start; native: the Mods folder source
    def self.begin_session(native = nil)
      @native = native
      @reports = {}
      @pcache = {}
      @notices = []
      @lists = nil
      h = read_file
      @first_run = h.nil? && !File.file?(path)
      @data = h || fresh_data
      @dirty = false
    end

    def self.save!
      return unless @dirty
      p = path
      KIF.mkdir_p(File.dirname(p))
      d = data
      if d["scans"].length > MAX_SCANS
        d["scans"] = d["scans"].to_a.last(MAX_SCANS / 2).to_h
      end
      File.write(p + ".tmp", KIF::ModPublish.to_json(d), mode: "wb")
      File.rename(p + ".tmp", p)
      @dirty = false
    rescue StandardError => e
      KIF.log("Mod trust: #{FILE} not saved (#{e.class}: #{e.message})")
    end

    def self.dirty!; @dirty = true; end

    # the Mod protection setting, kept here too: mods load before the player's settings do
    def self.protection; v = data["protection"]; return v.is_a?(Integer) ? v : nil; end

    def self.set_protection(v)
      deny_mod_caller!("protection", caller_locations(1, 40))
      data["protection"] = v.to_i
      dirty!
      save!
    end

    def self.entry_for(id)
      list = (@native ? @native.entries : nil) || []
      e = list.find { |x| x.id == id }
      return e if e
      return (KIF::Mods.entries.find { |x| x.id == id } rescue nil)
    end

    #---------------------------------------------------------------------------
    # Looking at a mod when the game starts
    #---------------------------------------------------------------------------
    def self.json_of(e)
      return nil unless e.respond_to?(:kind) && e.kind == :folder
      return KIF::Mods.read_json(File.join(e.path.to_s, "mod.json"))
    end

    def self.sig_of(list)
      return KIF::ModCheck.sha1_hex(list.map { |rel, _f, lst| "#{rel}:#{lst.size}:#{lst.mtime.to_i}" }.join("|"))
    end

    # nil to let the mod load, or the plain-words reason it is held. With Mod protection on Off or Warn only nothing is
    # held back (the scan is still made and shown): the player chose to be left alone.
    def self.gate(e)
      why = gate_check(e)
      return nil if why && %i[off warn].include?(KIF::ModGuard.mode)
      return why
    end

    def self.gate_check(e)
      return nil if e.nil? || e.path.nil? || e.kind == :mod_manager
      id = e.id
      list = KIF::ModCheck.list_files(e.path.to_s)
      sig = sig_of(list)
      rec = mods[id]
      if rec.nil? && @first_run
        mods[id] = { "state" => "grandfathered", "sig" => sig, "seen" => today, "granted" => [], "allow_all" => false }
        dirty!
        return nil
      end
      return evaluate(e, rec, sig) if rec.nil? || rec["sig"] != sig
      return held_reason(e, rec)
    rescue StandardError => ex
      KIF.log("Mod trust: #{id} not checked (#{ex.class}: #{ex.message})")
      return nil
    end

    def self.today; return Time.now.strftime("%Y-%m-%d"); end

    def self.scan_entry(e)
      return KIF::ModCheck.scan(e.path.to_s, json_of(e))
    end

    # a mod the file has not seen, or whose files changed: scan it now
    def self.evaluate(e, rec, sig)
      id = e.id
      rep = scan_entry(e)
      @reports[id] = rep
      old = rec && rec["scan"].is_a?(Hash) ? KIF::ModCheck::Report.from_h(rec["scan"]) : nil
      same = rec && rec["fingerprint"] == rep.fingerprint
      rv = revoked_reason(e, rep)
      nrec = rec || { "granted" => [], "allow_all" => false }
      nrec["sig"] = sig
      nrec["fingerprint"] = rep.fingerprint
      nrec["color"] = rep.color.to_s
      nrec["scan"] = summary(rep)
      nrec["seen"] = today
      nrec["prov"] = provenance_text(e, rep)
      mods[id] = nrec
      dirty!
      @pcache.delete(id)
      if rv
        nrec["state"] = "revoked"
        nrec["reason"] = rv
        return held_reason(e, nrec)
      end
      if same && %w[approved new held revoked].include?(nrec["state"])
        return held_reason(e, nrec)
      end
      baseline = old && %w[approved grandfathered].include?(rec["state"]) ? old : nil
      worse = baseline.nil? || worse?(rep, baseline)
      if !worse
        nrec["state"] = "approved" if nrec["state"] != "grandfathered"
        return nil
      end
      case rep.color
      when :green
        nrec["state"] = "approved"
        return nil
      when :yellow
        nrec["state"] = "new"
        @notices << [id, _INTL("{1} is new or changed. It: {2}.", e.name, notice_words(rep))]
        return nil
      else
        nrec["state"] = "held"
        return held_reason(e, nrec)
      end
    end

    def self.notice_words(rep)
      w = rep.lines(2).map { |l| l.sub(/ \(.*\z/, "").sub(/\A./) { |c| c.downcase } }
      w = rep.permission_lines.first(2).map { |l| l.sub(/ \(.*\z/, "").sub(/\A./) { |c| c.downcase } } if w.empty?
      return w.empty? ? "needs a look" : w.join(", ")
    end

    # a scan that adds a permission or a worse colour than the one the player had
    def self.worse?(rep, old)
      rank = { :green => 0, :yellow => 1, :red => 2 }
      return true if rank[rep.color] > rank[old.color]
      return !(rep.held - old.held).empty?
    end

    def self.summary(rep)
      h = rep.to_h
      h.delete("stamps")
      h.delete("files")
      h["findings"] = h["findings"].first(30)
      return h
    end

    def self.held_reason(e, rec)
      return nil unless %w[held revoked].include?(rec["state"])
      what = if rec["state"] == "revoked" then rec["reason"].to_s
             else
               rep = KIF::ModCheck::Report.from_h(rec["scan"])
               first = rep.lines(1)[0].to_s.sub(/ \(.*\z/, "")
               first.empty? ? "needs a look" : first.sub(/\A./) { |c| c.downcase }
             end
      return _INTL("Needs your OK: {1}. Open Options > Mods to review it.", what)
    end

    #---------------------------------------------------------------------------
    # Reports and permissions
    #---------------------------------------------------------------------------
    def self.state(id); return (mods[id] || {})["state"]; end
    def self.record(id); return mods[id]; end

    # the scan of a mod: this session's, the saved one, or one made now
    def self.report_for(id)
      return @reports[id] if @reports[id]
      e = entry_for(id)
      rec = mods[id]
      if rec && rec["scan"].is_a?(Hash) && rec["fingerprint"]
        return @reports[id] = KIF::ModCheck::Report.from_h(rec["scan"])
      end
      return nil unless e && e.path
      rep = scan_entry(e)
      @reports[id] = rep
      if rec
        rec["fingerprint"] = rep.fingerprint
        rec["color"] = rep.color.to_s
        rec["scan"] = summary(rep)
        rec["prov"] = provenance_text(e, rep)
        dirty!
      end
      return rep
    end

    # Array of permission names the mod may use, or :all
    def self.permission_set(id)
      return @pcache[id] if @pcache.key?(id)
      rec = mods[id]
      return @pcache[id] = :all if rec && rec["allow_all"]
      e = entry_for(id)
      return @pcache[id] = :all if e.nil?
      base = e.respond_to?(:permissions) ? e.permissions : nil
      base ||= (report_for(id) ? report_for(id).inferred : [])
      return @pcache[id] = (base + Array(rec && rec["granted"])).uniq
    end

    def self.allow_all?(id); return (mods[id] || {})["allow_all"] ? true : false; end

    def self.hosts_for(id)
      e = entry_for(id)
      return (e && e.respond_to?(:network_hosts)) ? Array(e.network_hosts) : []
    end

    def self.take_notice; return @notices.shift; end
    def self.notices; return @notices.dup; end

    #---------------------------------------------------------------------------
    # The player's choices (the Options > Mods menu calls these)
    #---------------------------------------------------------------------------
    def self.rec_for(id)
      return mods[id] ||= { "state" => "approved", "granted" => [], "allow_all" => false, "seen" => today }
    end

    # the player said yes to an install that did more than it said: the mod as installed counts as reviewed
    def self.accept_folder(id)
      deny_mod_caller!("accept", caller_locations(1, 40))
      @native.instance_variable_set(:@entries, nil) if @native
      e = entry_for(id)
      return false unless e && e.path
      rep = scan_entry(e)
      rec = rec_for(id)
      rec["state"] = "approved"
      rec["sig"] = sig_of(KIF::ModCheck.list_files(e.path.to_s))
      rec["fingerprint"] = rep.fingerprint
      rec["color"] = rep.color.to_s
      rec["scan"] = summary(rep)
      rec["prov"] = provenance_text(e, rep)
      rec.delete("reason")
      @reports[id] = rep
      @pcache.delete(id)
      dirty!
      save!
      return true
    end

    def self.approve(id)
      deny_mod_caller!("approve", caller_locations(1, 40))
      rec = rec_for(id)
      rec["state"] = "approved"
      rec.delete("reason")
      @pcache.delete(id)
      dirty!
      save!
      return true
    end

    def self.set_allow_all(id, on)
      deny_mod_caller!("allow anything", caller_locations(1, 40))
      rec_for(id)["allow_all"] = on ? true : false
      @pcache.delete(id)
      dirty!
      save!
      KIF::ModGuard.reset_cache if defined?(KIF::ModGuard)
      return on ? true : false
    end

    def self.grant(id, perm)
      deny_mod_caller!("grant", caller_locations(1, 40))
      return false unless KIF::ModCheck::PERMISSION_NAMES.include?(perm.to_s)
      rec = rec_for(id)
      rec["granted"] = (Array(rec["granted"]) + [perm.to_s]).uniq
      @pcache.delete(id)
      dirty!
      save!
      return true
    end

    #---------------------------------------------------------------------------
    # Provenance: where the mod's files came from, and whether they still match
    #---------------------------------------------------------------------------
    def self.provenance_record(e)
      return nil unless e && e.kind == :folder
      p = File.join(e.path.to_s, PROVENANCE)
      return nil unless File.file?(p) && File.size(p) < 4 * 1024 * 1024
      h = KIF::Mods::MiniJSON.parse(File.read(p, encoding: "UTF-8"))
      return h.is_a?(Hash) ? h : nil
    rescue StandardError
      return nil
    end

    # "catalog:<repo> <short commit>", "changed:<n files>", "unverified:<repo>", "local" or "none"
    def self.provenance_text(e, rep)
      pr = provenance_record(e)
      return "none" unless pr
      files = pr["files"].is_a?(Hash) ? pr["files"] : {}
      return "unverified:#{pr['repo']}" unless pr["verified"] == true && files.any?
      mine = rep && !rep.files.empty? ? rep.files : KIF::ModCheck.fingerprint(e.path.to_s)[1]
      diff = (files.keys | mine.keys).count { |rel| files[rel] != mine[rel] }
      return "changed:#{diff}" if diff > 0
      return pr["commit"].to_s.empty? ? "local" : "catalog:#{pr['repo']} #{pr['commit'].to_s[0, 7]}"
    rescue StandardError
      return "none"
    end

    # plain words for the mod's page
    def self.provenance_line(id)
      rec = mods[id] || {}
      if rec["prov"].nil? && (e = entry_for(id))
        rec["prov"] = provenance_text(e, nil)
        dirty!
      end
      t = rec["prov"].to_s
      case t
      when /\Acatalog:(.*)/ then return _INTL("Matches the catalog ({1}).", $1)
      when /\Achanged:(\d+)/ then return _INTL("Changed since it was installed ({1} files).", $1)
      when /\Aunverified:(.*)/ then return _INTL("From a catalog, but its files could not be checked.")
      when "local" then return _INTL("Installed from a local catalog.")
      end
      return _INTL("Not from a catalog.")
    end

    #---------------------------------------------------------------------------
    # The catalogs' lists: reviewed.json (a person looked at this exact mod) and
    # revoked.json (do not run these). Optional files at the root of a catalog;
    # nothing breaks when they are missing.
    #---------------------------------------------------------------------------
    def self.lists
      return @lists if @lists
      @lists = { "revoked" => [], "reviewed" => {}, "fetched" => 0 }
      p = File.join(KIF.save_dir, LISTS_FILE)
      if File.file?(p) && File.size(p) < 2 * MAX_LIST
        h = (KIF::Mods::MiniJSON.parse(File.read(p, encoding: "UTF-8")) rescue nil)
        if h.is_a?(Hash)
          @lists["revoked"] = clean_revoked(h["revoked"])
          @lists["reviewed"] = clean_reviewed(h["reviewed"])
          @lists["fetched"] = h["fetched"].to_i
        end
      end
      return @lists
    end

    def self.text(v, max)
      return KIF::ModCatalog.clean_text(v, max) if defined?(KIF::ModCatalog)
      return v.to_s.gsub(/[^\x20-\x7e]/, " ")[0, max]
    end

    def self.plain_id?(id)
      return defined?(KIF::ModCatalog) ? KIF::ModCatalog.plain_id?(id) : (id.to_s =~ /\A[a-z0-9][a-z0-9_\-]{0,63}\z/ ? true : false)
    end

    def self.clean_revoked(list)
      out = []
      return out unless list.is_a?(Array)
      list.first(2000).each do |r|
        next unless r.is_a?(Hash) && r["id"].is_a?(String) && plain_id?(r["id"])
        fp = r["fingerprint"].is_a?(String) && r["fingerprint"] =~ /\A[0-9a-f]{40}\z/ ? r["fingerprint"] : nil
        vs = r["versions"].is_a?(String) && r["versions"].length <= 40 ? r["versions"] : nil
        out << { "id" => r["id"], "fingerprint" => fp, "versions" => vs, "reason" => text(r["reason"], 140), "since" => text(r["since"], 12) }
      end
      return out
    end

    def self.clean_reviewed(h)
      out = {}
      return out unless h.is_a?(Hash)
      h.first(5000).each do |id, r|
        next unless id.is_a?(String) && plain_id?(id) && r.is_a?(Hash)
        fp = r["fingerprint"].to_s
        next unless fp =~ /\A[0-9a-f]{40}\z/
        res = %w[green yellow].include?(r["result"].to_s) ? r["result"].to_s : "yellow"
        out[id] = { "fingerprint" => fp, "version" => text(r["version"], 32), "reviewed" => text(r["reviewed"], 12), "result" => res, "note" => text(r["note"], 140) }
      end
      return out
    end

    # Reads the lists from the catalogs (a folder catalog is read directly, a GitHub one from the
    # branch's head), at most once a day, and keeps the answer in the save folder. A failed read
    # keeps the old lists. fetch: a proc url -> text or nil (tests); nil uses the game's updater.
    def self.refresh_lists(force = false, fetch = nil)
      return false unless defined?(KIF::ModCatalog)
      return false if !force && Time.now.to_i - lists["fetched"].to_i < LIST_TIME
      revoked = []
      reviewed = {}
      got = false
      KIF::ModCatalog.catalogs.each do |cat|
        { "revoked.json" => :revoked, "reviewed.json" => :reviewed }.each do |name, kind|
          body = if cat.local?
                   f = File.join(cat.path, name)
                   File.file?(f) && File.size(f) <= MAX_LIST ? File.binread(f) : nil
                 elsif fetch
                   fetch.call(KIF::Updater.url_for(cat.branch_base, name))
                 elsif defined?(KIF::Updater) && KIF::Updater.channel != 2
                   KIF::Updater.fetch(KIF::Updater.url_for(cat.branch_base, name))
                 end
          next if body.nil? || body.bytesize > MAX_LIST
          got = true
          h = (KIF::Mods::MiniJSON.parse(KIF::PixelFont.utf8(body.to_s)) rescue nil)
          next unless h.is_a?(Hash) && h["format"] == 1
          if kind == :revoked then revoked.concat(clean_revoked(h["revoked"]))
          else reviewed.merge!(clean_reviewed(h["mods"])) end
        end
      end
      return false unless got
      @lists = { "revoked" => revoked, "reviewed" => reviewed, "fetched" => Time.now.to_i }
      File.write(File.join(KIF.save_dir, LISTS_FILE) + ".tmp", KIF::ModPublish.to_json(@lists), mode: "wb")
      File.rename(File.join(KIF.save_dir, LISTS_FILE) + ".tmp", File.join(KIF.save_dir, LISTS_FILE))
      return true
    rescue StandardError => e
      KIF.log("Mod trust: lists not refreshed (#{e.class}: #{e.message})")
      return false
    end

    def self.json_id(e)
      j = json_of(e)
      return j && j["id"].is_a?(String) ? j["id"] : e.id
    end

    # the revoked entry that matches this mod, or nil. id plus fingerprint when it gives one, else id plus version test.
    def self.revoked_entry(e, rep)
      id = json_id(e)
      return lists["revoked"].find do |r|
        next false unless r["id"] == id || r["id"] == e.id
        next r["fingerprint"] == rep.fingerprint if r["fingerprint"]
        next KIF::ModRules.version_ok?(r["versions"], e.version.to_s) if r["versions"] && e.version
        true
      end
    end

    def self.revoked_reason(e, rep)
      r = revoked_entry(e, rep)
      return nil unless r
      return r["reason"].to_s.empty? ? "it was withdrawn by its catalog" : r["reason"]
    end

    # a catalog item (not installed): is it revoked? item needs id, version
    def self.revoked_item(id, version, fingerprint = nil)
      return lists["revoked"].find do |r|
        next false unless r["id"] == id
        next r["fingerprint"] == fingerprint if r["fingerprint"] && fingerprint
        next false if r["fingerprint"]
        next KIF::ModRules.version_ok?(r["versions"], version.to_s) if r["versions"]
        true
      end
    end

    # "Reviewed 2026-11-01" / "Changed since it was reviewed" / nil
    def self.review_line(id)
      e = entry_for(id)
      rec = mods[id]
      return nil unless e && rec && rec["fingerprint"]
      r = lists["reviewed"][json_id(e)] || lists["reviewed"][id]
      return nil unless r
      return _INTL("Reviewed {1}.", r["reviewed"]) if r["fingerprint"] == rec["fingerprint"]
      return _INTL("Changed since it was reviewed.")
    end

    # fingerprint of an install that is not on disk yet (a catalog item's file list: path => [sha, size])
    def self.fingerprint_of_files(files)
      h = {}
      files.each { |rel, v| next if rel.split("/").any? { |s| KIF::ModCheck::SKIP_FOLDERS.include?(s) } || KIF::ModCheck::SKIP_FILES.include?(File.basename(rel)); h[rel] = v.is_a?(Array) ? v[0] : v }
      return KIF::ModCheck.fingerprint_of(h)
    end
  end
end
