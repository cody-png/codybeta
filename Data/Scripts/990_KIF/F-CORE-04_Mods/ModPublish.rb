#===============================================================================
# F-CORE-04 – Publish a mod (2026-10-22)
# Options > Mods > Installed > Publish a mod (PC only; not on phones). For
# modders: sends a mod to the community catalog (cody-png/kif-discord-mods)
# through the modder's own GitHub account, without using GitHub by hand. Asked for by Stonewall;
# the idea follows Mod Manager 2.0's Modder Tools (create / update / upload).
#   1. pick a folder in Mods/ (or in ModDev/ next to the game)
#   2. name, version (Raise version for an update), author, description and
#      tags (Mod Manager 2.0's tag names), saved to its mod.json
#   3. the catalog's own checks (ModCheck.rb) run; problems are shown and
#      nothing is uploaded until they're fixed
#   4. the pull request form's answers (permission, tested, notes)
#   5. Tools/publish_mod.bat (.sh on Linux) opens in its own window and does
#      the GitHub part with the GitHub CLI under the player's own account:
#      sign in (browser), then either straight to main (catalog contributors,
#      their own mod's folder only; Cody, 2026-10-22) or fork, branch, push
#      and a pull request that is reviewed.
# KIF never sees or stores a GitHub sign-in: gh keeps it.
#===============================================================================
module KIF
  module ModPublish
    REPO = "cody-png/kif-discord-mods"
    # Mod Manager 2.0's tags (001_ModData.rb VALID_TAGS), so modders know them
    TAGS = ["Gameplay", "Visual", "Audio", "QoL", "Balance", "Difficulty",
            "Fusion", "Multiplayer", "UI", "Cosmetic", "Bug Fix", "Content"].freeze
    TOOLS = "Tools"
    MODDEV = "ModDev"

    module_function

    def log(msg); KIF.log("Publish a mod: #{msg}"); end
    def t(s); return KIF::PixelFont.utf8(s.to_s); end
    # the folder the game runs in (Mods, ModDev, Tools; Paths.root is its parent in the "Game Files" layout)
    def root; return File.expand_path("."); end   # JoiPlay rewrites the usual working-folder call

    # phones never start programs; neither does a game without a way to
    def available?
      return false if KIF.mobile?
      return windows? || wine? || RUBY_PLATFORM =~ /linux|darwin/i ? true : false
    end

    def win; return defined?(KIF::Updater::Win) ? KIF::Updater::Win : nil; end
    def windows?; return win && win.available? && !win.wine? ? true : false; end
    def wine?; return win && win.available? && win.wine? ? true : false; end

    #---------------------------------------------------------------------------
    # Folders and mod.json
    #---------------------------------------------------------------------------
    # [[label, path]] of the mod folders a modder can publish
    def folders
      out = []
      [[File.join(root, KIF::Mods::FOLDER), "Mods"], [File.join(root, MODDEV), "ModDev"]].each do |dir, where|
        next unless File.directory?(dir)
        Dir.children(dir).sort.each do |c|
          p = File.join(dir, c)
          next unless File.directory?(p) && !c.start_with?(".", "_") && !KIF::Mods::SKIP_DIRS.include?(c)
          next unless File.file?(File.join(p, "mod.json")) || !Dir.glob(File.join("**", "*.rb"), base: p).empty?
          out << ["#{c} (#{where})", p]
        end
      end
      return out
    end

    # mod.json as a Hash, a new one when there is none, nil when it can't be
    # read (never overwritten then: the modder's file would be lost)
    def load_json(path)
      j = File.join(path, "mod.json")
      unless File.file?(j)
        id = File.basename(path).downcase.gsub(/[^a-z0-9_\-]+/, "_").sub(/\A[_\-]+/, "")
        rbs = Dir.glob("*.rb", base: path).sort   # base: a [ ] { } in the path isn't read as a pattern
        h = { "id" => id, "name" => File.basename(path).tr("_", " "), "version" => "1.0.0", "author" => "", "description" => "" }
        h["scripts"] = rbs unless rbs.empty?
        return h
      end
      json, _why = KIF::ModCheck.parse_json(File.read(j, encoding: "UTF-8"))
      return json.is_a?(Hash) ? json : nil
    rescue StandardError
      return nil
    end

    def save_json(path, json)
      f = File.join(path, "mod.json")
      tmp = f + ".kif_tmp"
      File.open(tmp, "wb") { |io| io.write(to_json(json) + "\n") }
      File.delete(f) if File.file?(f)
      File.rename(tmp, f)
      return true
    rescue StandardError => e
      log("mod.json not saved in #{path} (#{e.class}: #{e.message})")
      return false
    end

    def json_str(s)
      esc = { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\t" => "\\t", "\r" => "\\r" }
      return '"' + s.to_s.gsub(/[\\"\x00-\x1f]/) { |c| esc[c] || format("\\u%04x", c.ord) } + '"'
    end

    # mod.json as people write it: two spaces, short lists on one line
    def to_json(v, ind = "")
      case v
      when Hash
        return "{}" if v.empty?
        return "{\n" + v.map { |k, x| "#{ind}  #{json_str(k)}: #{to_json(x, ind + '  ')}" }.join(",\n") + "\n#{ind}}"
      when Array
        return "[]" if v.empty?
        return "[" + v.map { |x| to_json(x) }.join(", ") + "]" unless v.any? { |x| x.is_a?(Hash) || x.is_a?(Array) }
        return "[\n" + v.map { |x| "#{ind}  #{to_json(x, ind + '  ')}" }.join(",\n") + "\n#{ind}]"
      when String then return json_str(v)
      when nil then return "null"
      else return v.to_s
      end
    end

    # "1.2" + :patch -> "1.2.1"; :minor -> "1.3.0"; :major -> "2.0.0"
    def raise_version(v, part)
      a, b, c = (KIF::ModRules.parts(v) + [0, 0, 0])[0, 3]
      return case part
             when :major then "#{a + 1}.0.0"
             when :minor then "#{a}.#{b + 1}.0"
             else "#{a}.#{b}.#{c + 1}"
             end
    end

    #---------------------------------------------------------------------------
    # The catalog (what Browse already read; nothing is fetched when Mod
    # Manager 2.0 runs the browser instead)
    #---------------------------------------------------------------------------
    def catalog_items(repo = REPO)
      return [] unless defined?(KIF::ModCatalog) && KIF::ModCatalog.available?
      KIF::ModCatalog.load if KIF::ModCatalog.items.nil?
      return (KIF::ModCatalog.items || []).select { |it| it.catalog && it.catalog.repo.to_s.casecmp(repo) == 0 }
    rescue StandardError => e
      log("catalog not read (#{e.class}: #{e.message})")
      return []
    end

    # the same mod in the catalog (an update), or nil
    def published(json, items)
      return items.find { |it| it.id == json["id"].to_s }
    end

    # [errors, warnings] for the folder as it would be uploaded
    def check(path, json, items)
      old = published(json, items)
      folder = old ? old.folder : File.basename(path)
      others = {}
      items.each { |it| others[it.folder] = it.id }
      errs, warns = KIF::ModCheck.check(path, folder, others)
      if old && KIF::ModRules.compare(json["version"], old.version) <= 0
        errs << "\"version\" must be higher than the catalog's #{old.version} for players to get the update"
      end
      # Browse lists a mod from the first catalog that has its id or folder
      # (KIF-Mods first): players would get that one
      first = (KIF::ModCatalog.items || []).find do |it|
        !items.include?(it) && (it.id == json["id"].to_s || it.folder == folder)
      end rescue nil
      warns << "\"#{json['id']}\" is also in the #{first.catalog.name} catalog (#{first.folder}); Browse shows that one first" if first
      return [errs, warns]
    end

    #---------------------------------------------------------------------------
    # Pull request text and the helper script
    #---------------------------------------------------------------------------
    # [title, body]; a: {:own, :tested, :notes}
    def pr_text(json, folder, old, a, warns = [])
      # no " or ! in the title: publish_mod.bat passes it on a command line
      name = json["name"].to_s.gsub(/[\x00-\x1f"!]+/, " ").strip
      ver = json["version"].to_s
      title = old ? "Update #{name} #{ver}" : "Add #{name} #{ver}"
      desc = json["description"].is_a?(Array) ? json["description"].join(" ") : json["description"].to_s
      box = proc { |on| on ? "[x]" : "[ ]" }
      notes = a[:notes].to_s.strip
      lines = [
        "## Mod", "",
        "- **Name:** #{name}",
        "- **Folder:** #{folder}",
        "- **New mod or update:** #{old ? "Update (catalog has #{old.version}, this is #{ver})" : 'New mod'}",
        "- **What it does (one or two lines):** #{desc.gsub(/\s+/, ' ').strip}", "",
        "## Checklist", "",
        "- #{box.call(a[:own])} I made this mod, or I have the author's permission to share it (credited in mod.json)",
        "- [x] `mod.json` has `id`, `name`, `version`, `author` and `description`",
        "- #{box.call(true)} For an update: `version` is higher than before",
        "- #{box.call(a[:tested])} Tested in KIF: it loads, a battle works, the game saves and loads",
        "- [x] KIF version I tested with: #{KIF::ModRules.kif_version}", "",
        "## Anything the reviewer should know", "",
        notes.empty? ? "(nothing)" : notes
      ]
      unless warns.empty?
        lines += ["", "Worth a look (the game's check):"] + warns.first(20).map { |w| "- #{w}" }
      end
      lines += ["", "_Sent with Publish a mod in KIF #{KIF::ModRules.kif_version}._"]
      return [title, lines.join("\n") + "\n"]
    end

    def branch_for(json)
      v = json["version"].to_s.gsub(/\.{2,}/, ".").sub(/[.\-]+\z/, "")
      return "mod/#{json['id']}-#{v}"
    end

    def request_dir
      d = File.join(root, "Cache", "Publish")
      KIF.mkdir_p(d)
      return d
    end

    # writes the commit message (title, blank line, body) and the pull request
    # body; [message file, body file]
    def write_request(title, body)
      d = request_dir
      msg = File.join(d, "message.txt")
      bod = File.join(d, "body.md")
      File.open(msg, "wb") { |f| f.write("#{title}\n\n#{body}") }
      File.open(bod, "wb") { |f| f.write(body) }
      return [msg, bod]
    end

    def script(ext); return File.join(root, TOOLS, "publish_mod.#{ext}"); end

    # Wine runs Linux under drive Z:
    def unix_path(p); return p.to_s.tr("\\", "/").sub(/\A[Zz]:/, ""); end

    def sh_command(args)
      return (["bash", script("sh")] + args).map { |a| "'" + unix_path(a).gsub("'", "'\\\\''") + "'" }.join(" ")
    end

    # Starts the script in a window of its own. :started, :manual (the
    # player runs it: the command is in Cache/Publish/command.txt) or false.
    def launch(args)
      return false if KIF.mobile?
      if windows?
        bat = script("bat")
        return false unless File.file?(bat)
        # paths with Windows slashes; the branch (mod/...) stays as it is
        q = proc { |s| "\"" + (s.to_s =~ %r{\A([A-Za-z]:)?/} ? s.to_s.tr("/", "\\") : s.to_s) + "\"" }
        # cmd /s /c "..." drops the outer quotes and runs the rest as typed
        line = "cmd.exe /d /s /c \"#{([q.call(bat)] + args.map { |a| q.call(a) }).join(' ')}\""
        log("starting #{line}")
        h = win.spawn(line, KIF::Updater::Win::CREATE_NEW_CONSOLE, root.tr("/", "\\"))
        return false unless h
        win.close(h[0]) if h[0]
        return :started
      end
      cmd = sh_command(args)
      if !wine? && RUBY_PLATFORM =~ /linux/i
        term = %w[x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm].find do |x|
          ENV["PATH"].to_s.split(":").any? { |d| File.executable?(File.join(d, x)) }
        end
        if term
          argv = term == "gnome-terminal" ? [term, "--", "bash", "-c", cmd] : [term, "-e", "bash", "-c", cmd]
          log("starting #{argv.join(' ')}")
          pid = Process.spawn(*argv)
          Process.detach(pid)
          return :started
        end
      end
      # Wine, macOS, or no terminal found: the player runs it
      File.open(File.join(request_dir, "command.txt"), "wb") { |f| f.write(cmd + "\n") }
      log("command written for the player: #{cmd}")
      return :manual
    rescue StandardError => e
      log("couldn't start the script (#{e.class}: #{e.message})")
      return false
    end

    #---------------------------------------------------------------------------
    # The screens (message boxes and the game's own text entry)
    #---------------------------------------------------------------------------
    def ask(text, cmds); return pbMessage(t(text), cmds.map { |c| t(c) }, cmds.length); end

    def enter(text, current, max)
      v = pbMessageFreeText(t(text), current.to_s, false, max)
      return v.nil? ? nil : v.to_s.strip
    end

    def pick_tags(tags)
      sel = Array(tags).map(&:to_s)
      loop do
        rows = TAGS.map { |g| (sel.include?(g) ? "[X] " : "[  ] ") + g } + [_INTL("Done")]
        c = ask(_INTL("Tags (choose to switch one on or off):"), rows)
        break if c.nil? || c < 0 || c >= TAGS.length
        g = TAGS[c]
        sel.include?(g) ? sel.delete(g) : sel << g
      end
      # tags it already had that aren't in the list stay (first)
      return sel.sort_by { |g| TAGS.index(g) || -1 }
    end

    def pick_version(json, old)
      v = json["version"].to_s
      head = old ? _INTL("Version {1}. The catalog has {2}.", v, old.version) : _INTL("Version {1}.", v)
      base = old && KIF::ModRules.compare(old.version, v) > 0 ? old.version : v
      ups = [:patch, :minor, :major].map { |p| raise_version(base, p) }
      c = ask(head, ups.map { |u| _INTL("Raise to {1}", u) } + [_INTL("Type a version"), _INTL("Cancel")])
      return ups[c] if c && c >= 0 && c < 3
      return enter(_INTL("Version (like 1.0 or 1.2.3):"), v, 20) if c == 3
      return nil
    end

    # the details screen; true when the modder chose to check and publish
    def edit(path, json, old)
      loop do
        desc = json["description"].is_a?(Array) ? json["description"].join(" ") : json["description"].to_s
        tags = Array(json["tags"])
        rows = []
        bad_id = json["id"].to_s !~ KIF::ModCheck::ID
        rows << [:id, _INTL("ID: {1}", json["id"].to_s)] if bad_id
        rows << [:name, _INTL("Name: {1}", json["name"])]
        rows << [:version, old ? _INTL("Version: {1} (catalog {2})", json["version"], old.version) : _INTL("Version: {1}", json["version"])]
        rows << [:author, _INTL("Author: {1}", json["author"])]
        rows << [:desc, _INTL("Description: {1}", desc.length > 30 ? desc[0, 30] + "..." : desc)]
        rows << [:tags, _INTL("Tags: {1}", tags.empty? ? _INTL("none") : tags.join(", "))]
        rows << [:go, _INTL("Check and publish")]
        rows << [:cancel, _INTL("Cancel")]
        head = old ? _INTL("Update {1} in the catalog.", json["name"]) : _INTL("New mod for the catalog: {1}.", json["name"])
        c = ask(head, rows.map { |r| r[1] })
        key = c && c >= 0 && c < rows.length ? rows[c][0] : :cancel
        case key
        when :id
          v = enter(_INTL("ID (a-z, 0-9, _ and -). It never changes once published:"), json["id"], 40)
          json["id"] = v.downcase if v && !v.empty?
        when :name
          v = enter(_INTL("Mod name:"), json["name"], 40)
          json["name"] = v if v && !v.empty?
        when :version
          v = pick_version(json, old)
          json["version"] = v if v && !v.empty?
        when :author
          v = enter(_INTL("Author:"), json["author"], 40)
          json["author"] = v if v && !v.empty?
        when :desc
          v = enter(_INTL("Description (one or two lines):"), desc, 300)
          json["description"] = v if v && !v.empty?
        when :tags
          json["tags"] = pick_tags(tags)
        when :go
          return true
        else
          return false
        end
      end
    end

    def show_problems(errs, warns)
      unless errs.empty?
        pbMessage(t(errs.length == 1 ? _INTL("1 problem to fix before the mod can be published:") :
                                       _INTL("{1} problems to fix before the mod can be published:", errs.length)))
        errs.first(8).each { |e| pbMessage(t(e)) }
        pbMessage(t(_INTL("...and {1} more (all of them are in Logs/KIF_log.txt).", errs.length - 8))) if errs.length > 8
        return false
      end
      unless warns.empty?
        pbMessage(t(_INTL("The check passed. The reviewer will read these closely; say why the mod needs them in the notes:")))
        warns.first(5).each { |w| pbMessage(t(w)) }
        pbMessage(t(_INTL("...and {1} more (in Logs/KIF_log.txt).", warns.length - 5))) if warns.length > 5
      end
      return true
    end

    def run
      return pbMessage(t(_INTL("Publishing a mod works on a computer only."))) unless available?
      list = folders
      return pbMessage(t(_INTL("No mod folders found in Mods or ModDev."))) if list.empty?
      c = ask(_INTL("Which mod do you want to publish?"), list.map(&:first) + [_INTL("Cancel")])
      return unless c && c >= 0 && c < list.length
      path = list[c][1]
      json = load_json(path)
      return pbMessage(t(_INTL("{1}'s mod.json can't be read. Fix it in a text editor first.", File.basename(path)))) unless json
      items = catalog_items
      old = nil
      loop do
        old = published(json, items)
        return unless edit(path, json, old)
        return pbMessage(t(_INTL("mod.json couldn't be saved (see Logs/KIF_log.txt)."))) unless save_json(path, json)
        old = published(json, items)
        errs, warns = check(path, json, items)
        log("#{File.basename(path)}: #{errs.length} problems, #{warns.length} to look at")
        (errs.map { |e| "problem: #{e}" } + warns.map { |w| "look at: #{w}" }).each { |l| log("  #{l}") }
        break if show_problems(errs, warns)
        return unless ask(_INTL("Change the details now? Problems in the files need fixing in the folder."), [_INTL("Change details"), _INTL("Stop")]) == 0
      end
      answers = {}
      return unless ask(_INTL("Did you make this mod, or do you have its author's permission to share it?"),
                        [_INTL("Yes"), _INTL("No")]) == 0
      answers[:own] = true
      answers[:tested] = ask(_INTL("Did you test it in KIF (it loads, a battle works, the game saves and loads)?"),
                             [_INTL("Yes"), _INTL("Not yet")]) == 0
      answers[:notes] = enter(_INTL("Notes for the reviewer (optional):"), "", 500)
      folder = old ? old.folder : File.basename(path)
      _errs, warns = check(path, json, items)
      title, body = pr_text(json, folder, old, answers, warns)
      return unless ask(_INTL("Publish {1} {2}? A window opens that signs you in to GitHub in your browser (the first time) and uploads the mod. The game stays open.",
                              json["name"], json["version"]), [_INTL("Publish"), _INTL("Cancel")]) == 0
      msg, bod = write_request(title, body)
      res = launch([path, folder, branch_for(json), msg, bod, json["id"].to_s])
      case res
      when :started
        pbMessage(t(_INTL("The publish window is open. Follow its steps; it may ask to install Git or the GitHub CLI first.")))
        pbMessage(t(_INTL("Catalog contributors publish straight away: players get the mod at their next catalog check. Everyone else gets a pull request, which opens in the browser; it is checked and reviewed before the mod goes live.")))
      when :manual
        pbMessage(t(_INTL("Open a terminal and run the command saved in Cache/Publish/command.txt (in the game folder).")))
      else
        pbMessage(t(_INTL("The publish window couldn't be opened (see Logs/KIF_log.txt). The script is Tools/publish_mod in the game folder.")))
      end
    end
  end

  # Options > Mods > Installed: the entry, under its own heading
  module SettingsScreen
    class << self
      alias kif_pub_installed_rows installed_rows unless method_defined?(:kif_pub_installed_rows)
      def installed_rows(list)
        rows = kif_pub_installed_rows(list)
        begin
          return rows unless KIF::ModPublish.available?
          opt = ButtonOption.new(_INTL("Publish a mod"), proc { KIF::ModPublish.run },
                                 _INTL("Send one of your mods to the community catalog through your GitHub account. Checks it first."))
          rows += [Row.new(:head, nil, nil, _INTL("For modders"), :mods, "For modders", 0, nil),
                   Row.new(:opt, opt, :global, opt.name, :mods, "For modders", 0, nil)]
        rescue StandardError => e
          KIF.log("Publish a mod: entry not added (#{e.class}: #{e.message})")
        end
        return rows
      end
    end
  end
end
