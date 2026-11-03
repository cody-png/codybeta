#===============================================================================
# F-CORE-10 Mod API - Mod Dev mode, tools, hot reload, template, reference
#
# Options > Others settings > "Mod Dev mode" (Off / On) and, while it is On, a
# "Mod tools" button. Mod Dev mode means:
#  - strict API checks: misuse raises into the mod's isolation, with a backtrace
#    in the log (unknown event, writing a read-only field, a hook target that
#    does not exist, data that is not plain);
#  - timings (the profile mode: calls, average and slowest time per handler);
#  - a trace of the last 500 emits (KIF::API.trace_dump writes
#    Logs/KIF_modapi_trace.txt);
#  - hot reload is allowed (KIF::API.reload_mod(key));
#  - method collisions are logged.
#
# Mod tools:
#  1. Hooks and events: events with their handlers (mod, id, priority, calls,
#     average and slowest ms, errors, ON / OFF / AUTO-OFF); switch one on or off
#     or remove it. Wrapped game methods (alias or prepend, and who hooks them).
#     Method collisions. APIs mods provide.
#  2. Reload a mod / Reload all mods.
#  3. Make a new mod: writes Mods/<Name>/ (mod.json, main.rb, README.txt).
#  4. Write API reference (Logs/KIF_API_Reference.txt) and hook report
#     (Logs/KIF_hooks.txt).
#
# Hot reload does exactly this (the screen says the same): it removes what the
# mod added THROUGH THE API (event handlers, hooks, timers, registry entries,
# provided APIs, Tune changes, when_loaded blocks; its data stores stay), loads
# its scripts again with Mods.load_file, and applies the registries again. It does
# NOT undo raw alias / def / class_eval / Events.on... += / BattleHandlers.add /
# DataLoad steps / ModSettingsMenu.register the mod made, and does not run
# GameData.load_all again. It is safe only for mods that hook through the bus: the
# result says how many places the mod patches the game directly; a restart is the
# only clean reload for those.
#===============================================================================
module KIF
  module API
    module Dev
      NAME = /\A[A-Za-z0-9][A-Za-z0-9_\-]{0,39}\z/ unless const_defined?(:NAME)

      def self.on?; return API.dev?; end

      # called when the setting changes
      def self.changed
        API.trace = API.dev? ? (API.trace || []) : nil
        API.refresh_modes!
      end

      #-------------------------------------------------------------------------
      # The trace
      #-------------------------------------------------------------------------
      def self.trace_dump
        rows = API.trace || []
        text = rows.map { |t, ev, n, ms| format("%s  :%-24s %2d handlers  %8.3f ms", Time.at(t).strftime("%H:%M:%S.%L"), ev, n, ms) }.join("\r\n")
        path = KIF::Paths.log("KIF_modapi_trace.txt")
        File.open(path, "wb") { |f| f.write("KIF Mod API trace: the last #{rows.length} emits\r\n\r\n" + text + "\r\n") }
        return path
      end

      #-------------------------------------------------------------------------
      # The inspector (data; the screen only shows it)
      #-------------------------------------------------------------------------
      def self.event_rows
        return API.events.map { |ev| { :event => ev, :subscribers => API.subscribers(ev).length, :hot => (API.event_info(ev) || {})[:hot] ? true : false } }
      end

      def self.state_of(s)
        return "AUTO-OFF" if s.auto_off
        return "OFF" if s.hook_off || (s.mod && API.mod_off?(s.mod))
        return "ON"
      end

      def self.subscriber_rows(event)
        return API.subscribers(event).map do |s|
          avg = s.calls > 0 ? (s.total_ms / s.calls) : 0.0
          { :sub => s, :mod => API::Attribution.display(s.mod), :id => s.id, :priority => s.priority, :calls => s.calls,
            :avg_ms => avg.round(3), :max_ms => s.max_ms.round(3), :errors => s.error_total, :state => state_of(s) }
        end
      end

      def self.set_state(sub, on)
        if on
          sub.auto_off = false
          sub.hook_off = false
          sub.error_row = 0
        else
          sub.hook_off = true
        end
        return state_of(sub)
      end

      # wrapped game methods: target, form, the mods that hook it
      def self.wrapped_rows
        return API::Hook.points.values.map do |pt|
          mods = pt.subs.map { |s| s.internal ? "event" : API::Attribution.display(s.mod) }.uniq
          { :target => API::Hook.text(pt.klass, pt.name, pt.single), :form => pt.form, :mods => mods, :bypassed => pt.bypassed }
        end.sort_by { |r| r[:target] }
      end

      def self.line(s); return s.to_s.encode("US-ASCII", :invalid => :replace, :undef => :replace, :replace => "?"); end

      #-------------------------------------------------------------------------
      # Hot reload
      #-------------------------------------------------------------------------
      RAW_PATCH = /^\s*(alias|alias_method)\b/ unless const_defined?(:RAW_PATCH)

      # KIF::API.reload_mod(key) -> { :ok, :files, :hooks, :raw, :message }
      def self.reload_mod(key)
        return reload_result(false, key, 0, 0, 0, "Mod Dev mode is Off.") unless API.dev?
        e = (KIF::Mods.entries.find { |x| x.id == key } rescue nil)
        return reload_result(false, key, 0, 0, 0, "No mod #{key}.") unless e
        unless e.kind == :folder && e.source.is_a?(KIF::Mods::NativeSource)
          return reload_result(false, key, 0, 0, 0, "#{e.name} is not a folder mod KIF loads (Mod Manager mods and loose files can not be reloaded).")
        end
        json = KIF::ModRules.json_for(e) || {}
        return reload_result(false, key, 0, 0, 0, "#{e.name} says hot_reload is false.") if json["hot_reload"] == false
        files = e.source.scripts(e)
        raw = 0
        files.each { |f| raw += File.readlines(f, encoding: "UTF-8").count { |l| l =~ RAW_PATCH && l.lstrip[0] != "#" } rescue 0 }
        API.unload_mod(key)
        results = files.map { |f| KIF::Mods.load_file(f, key) }
        bad = results.find { |r| r != true }
        API::Registries.apply_data
        API::Attribution.invalidate
        hooks = API.hooks.count { |h| h[3] == key } + API.events.sum { |ev| API.subscribers(ev).count { |s| s.mod == key } }
        msg = bad ? "#{e.name}: reload failed (#{bad.class}: #{bad.message[0, 100]})" : "#{e.name} reloaded: #{files.length} files, #{hooks} hooks and handlers."
        msg += " It patches the game directly in #{raw} places; a restart is the only clean reload." if raw > 0 && !bad
        KIF.log(msg)
        return reload_result(bad.nil?, key, files.length, hooks, raw, msg)
      end

      def self.reload_result(ok, key, files, hooks, raw, msg)
        return { :ok => ok, :key => key, :files => files, :hooks => hooks, :raw => raw, :message => msg }
      end

      def self.reload_all
        out = []
        (KIF::Mods.entries rescue []).each do |e|
          next unless e.kind == :folder && e.loaded
          out << reload_mod(e.id)
        end
        return out
      end

      #-------------------------------------------------------------------------
      # A new mod
      #-------------------------------------------------------------------------
      # Writes Mods/<Name>/. Returns [path, nil] or [nil, why].
      def self.make_mod(name, dir = "Mods")
        n = name.to_s.strip
        return [nil, "Use letters, digits, _ and - (at most 40)."] unless n =~ NAME
        path = File.join(dir, n)
        return [nil, "Mods/#{n} exists already."] if File.exist?(path)
        KIF.mkdir_p(path)
        id = n.downcase
        ver = KIF::ModRules.kif_version rescue "1.0"
        File.write(File.join(path, "mod.json"), template_json(n, id, ver))
        File.write(File.join(path, "main.rb"), template_main(n, id))
        File.write(File.join(path, "README.txt"), template_readme(n))
        KIF::Mods.sources.each { |s| s.instance_variable_set(:@entries, nil) if s.is_a?(KIF::Mods::NativeSource) }
        return [path, nil]
      rescue StandardError => e
        return [nil, "#{e.class}: #{e.message[0, 100]}"]
      end

      def self.template_json(name, id, ver)
        return <<-JSON
{
  "id": "#{id}",
  "name": "#{name}",
  "version": "0.1.0",
  "author": "Your name",
  "description": "What this mod does, in one sentence.",
  "api_version": #{KIF::API_LEVEL},
  "permissions": [],
  "scripts": ["main.rb"],
  "requires_kif": ">=#{ver}"
}
JSON
      end

      def self.template_main(name, id)
        return <<-RUBY
# #{name} - a KIF mod made by Options > Mod tools > Make a new mod.
# It runs inside the game. Logs/KIF_API_Reference.txt lists every event and call
# (Options > Mod tools > Write API reference). The guide is Data/KIF/MODDING.md.

# 1. React to the game with an event: no alias, no copied game code.
#    ctx[:field] reads a field. ctx[:field] = value writes the fields the
#    reference marks as changeable. ctx.cancel! works on events that can be cancelled.
KIF::API.on(:battle_start, "#{id}_battle_start") do |ctx|
  # 2. Keep your own data. It is saved with the save file and survives
  #    removing the mod. Only plain data: numbers, text, true/false, nil, lists, hashes.
  store = KIF::API.data(:save)
  store["battles"] = store.fetch("battles", 0) + 1
  KIF.log("#{name}: battle number \#{store['battles']} (wild: \#{ctx[:wild]})")
end

# 3. A setting the player can change (Options > KIF Settings > Mods).
if defined?(ModSettingsMenu)
  ModSettingsMenu.register_toggle(:#{id}_enabled, "#{name}", "Turns #{name} on or off.", 1, "Quality of Life")
end

# 4. To change what a game method returns, hook it. The engine picks alias or
#    prepend for you, and several mods can hook the same method:
#      KIF::API.around("PokeBattle_Battler#pbUseMove") { |call| call.proceed }
#    Rule when you must patch a method yourself: alias OR Module#prepend, never both,
#    and write it so running the file twice does nothing bad (the F12-safe form):
#      class SomeClass
#        alias #{id}_x some_method unless method_defined?(:#{id}_x)
#        def some_method(*args)
#          #{id}_x(*args)
#        end
#      end
RUBY
      end

      def self.template_readme(name)
        perms = (defined?(KIF::ModContract) ? KIF::ModContract::PERMISSIONS : {}).map { |k, v| "  #{k}: #{v[1]}" }.join("\r\n")
        return <<-TXT
#{name}
#{'=' * name.length}

How to test
  Start the game with Mod Dev mode On (Options > Others settings). Change main.rb,
  then Options > Mod tools > Reload a mod. A mod that patches the game with alias
  needs a restart instead (the reload message says so). Logs/KIF_log.txt shows errors.

How to publish
  Options > Mods > Publish a mod. KIF checks the folder first and shows what it found.

Permissions
  List in mod.json "permissions" what the mod needs. Leave it empty if it only
  uses the game's own data. What each one means for the player:
#{perms}

Honest note
  A mod runs inside the game with the same rights as the game. KIF's checks catch
  honest mistakes and common tricks, not a determined attacker.
TXT
      end

      #-------------------------------------------------------------------------
      # The API reference (ASCII, generated from the tables)
      #-------------------------------------------------------------------------
      def self.wrap(text, indent = 4, width = 100)
        out = []
        cur = ""
        text.to_s.split(/\s+/).each do |w|
          if (cur + " " + w).length > width - indent
            out << (" " * indent) + cur
            cur = w
          else
            cur = cur.empty? ? w : cur + " " + w
          end
        end
        out << (" " * indent) + cur unless cur.empty?
        return out
      end

      INTRO = [
        "KIF Mod API, level %d",
        "",
        "What this is: names that stay the same, so a mod can react to the game, change it a little,",
        "keep data, run timers and add content without copying game code. API level 1 never renames or",
        "removes a name; a newer level only adds. Put \"api_version\": 1 in mod.json.",
        "",
        "It is not a sandbox: a mod is Ruby code running inside the game with the player's rights.",
        "A determined mod author can get around every check KIF has. The checks make dangerous behaviour",
        "visible, stop the common lazy tricks and give the player a switch; they are not a lock.",
        "",
        "THE BUS - KIF::API",
        "  on(event, id = nil, priority: 0, once: false, cancelled: false, if: nil) { |ctx| }   -> Subscription",
        "  off(subscription) / off(id, event) / off_all(mod: key)          emit(event, **fields) -> ctx",
        "  define_event(\"mymod.name\", fields: { a: :rw, b: :ro }, cancellable: false, doc: \"\")",
        "  level / supports?(event) / require_level(n)                    rescuing(label) { }",
        "  priorities: FIRST EARLY NORMAL LATE LAST MONITOR (MONITOR runs last, always, on a frozen ctx)",
        "  A handler that raises is logged with the mod's name and skipped; 5 errors in a row or 25 in a",
        "  session switch it off for the session. Hot events reuse one ctx: do not keep it.",
        "",
        "HOOKS - any game method (KIF::API.around / before / after / unhook / hooks / hooked?)",
        "  around(\"Class#method\") { |call| call.proceed }   before(...) { |call| call.skip!(value) }",
        "  after(\"Class#method\") { |call| call.result = ... }   target: \"Class#m\", \"Class.m\", \"Object#pbFunction\"",
        "  call: receiver args kwargs block proceed(*new_args) result skip!(v) called?",
        "  KIF picks alias or prepend for you; the same method is never both. A mod that REPLACES a hooked",
        "  method (plain def) wins; KIF::API.collisions says so.",
        "",
        "MODS - KIF::API.mods / mod(id) / mod_loaded?(id) / mod_version(id) / when_loaded(id) { |info| }",
        "  when_defined(\"Class#method\") { } / provide(name, object, version:) / api_of(name) / provided",
        "",
        "DATA - KIF::API.data(:save | :global) -> store ([] []= fetch delete key? keys to_h update clear",
        "  version migrate(to:) { |old| new }). Plain data only; 256 KB a mod; saved under one key.",
        "",
        "TIMERS - after(steps: / seconds:, id:, scope:) { } / every(...) { } / when_idle { } / map_idle?",
        "  Steps are logic steps (40 a second). scope :map (default) | :always | :battle.",
        "",
        "REGISTRIES - KIF::API::PauseMenu (add remove hide relabel move), PartyMenu.add, BattlerState",
        "  (register get set), Shops (add add_kuray), Items.register, Tune.set / revert, AI.score,",
        "  Fusion.after, Encounters (rate add_slot), Evolutions (register_method add), Text (swap set),",
        "  Sprites (decorate on_dispose), Theme (color register_color), Fonts.available.",
        "",
        "NOT IN THIS API: multiplayer events (net_connected, net_disconnected, coop_battle_begin,",
        "  coop_battle_end are reserved names), sprite import, new fonts at run time, the identity view of",
        "  a Pokemon (ability and type layers), battle screen decoration. Use hooks for those.",
        "",
        "EVENTS (name, since level, what it does; fields: ro = read only, RW = a handler may change it)"
      ].freeze unless const_defined?(:INTRO)

      def self.reference_text
        out = INTRO.map { |l| l.include?("%d") ? l % KIF::API_LEVEL : l }
        API::EVENTS.each do |ev, i|
          flags = []
          flags << "HOT" if i[:hot]
          flags << "extra" if i[:p] == 1
          out << ""
          out << "  :#{ev}  (since level #{i[:since]}#{flags.empty? ? '' : ', ' + flags.join(', ')})"
          out.concat(wrap(i[:doc], 4))
          out << "    ro: #{i[:ro].join(', ')}" unless i[:ro].empty?
          unless i[:rw].empty?
            out << "    RW: " + i[:rw].map { |f, (k, r)| "#{f} (#{k}#{r ? ' ' + r.to_s : ''})" }.join(", ")
          end
          out << "    cancel: #{i[:cancel]}" if i[:cancel]
        end
        out << ""
        out << "RESERVED (no code yet): #{API::RESERVED_EVENTS.map { |e| ':' + e.to_s }.join(', ')}"
        if defined?(KIF::ModContract)
          out << ""
          out << "PERMISSIONS (mod.json \"permissions\")"
          KIF::ModContract::PERMISSIONS.each { |k, (c, w)| out << "  #{k.ljust(14)} #{w} (#{c})" }
        end
        out << ""
        out << (defined?(KIF::ModTrust) && KIF::ModTrust.respond_to?(:about_text) ? KIF::ModTrust.about_text.to_s : "Only install mods you trust. Turn a mod Off or delete its folder to remove it.")
        return line(out.join("\r\n") + "\r\n")
      end

      def self.write_reference
        path = KIF::Paths.log("KIF_API_Reference.txt")
        File.open(path, "wb") { |f| f.write(reference_text) }
        return path
      end

      def self.hook_report_text
        out = ["KIF Mod API hook report", ""]
        out << "WRAPPED GAME METHODS"
        wrapped_rows.each { |r| out << "  #{r[:target].ljust(52)} #{r[:form].to_s.ljust(8)} #{r[:mods].join(', ')}#{r[:bypassed] ? '  BYPASSED' : ''}" }
        out << ""
        out << "EVENTS WITH HANDLERS"
        event_rows.select { |r| r[:subscribers] > 0 }.each do |r|
          out << "  :#{r[:event]}"
          subscriber_rows(r[:event]).each { |s| out << "    #{s[:mod]} / #{s[:id]}  prio #{s[:priority]}  #{s[:calls]} calls  avg #{s[:avg_ms]} ms  max #{s[:max_ms]} ms  errors #{s[:errors]}  #{s[:state]}" }
        end
        out << ""
        out << "METHOD COLLISIONS"
        API.collisions.each { |c| out << "  #{c[:kind]}: #{c[:target]} by #{API::Attribution.display(c[:mod])} (was #{c[:was]})" }
        out << ""
        out << "APIS MODS PROVIDE"
        API.provided.each { |n, h| out << "  #{n} v#{h[:version]} by #{API::Attribution.display(h[:mod])}" }
        return line(out.join("\r\n") + "\r\n")
      end

      def self.write_hook_report
        path = KIF::Paths.log("KIF_hooks.txt")
        File.open(path, "wb") { |f| f.write(hook_report_text) }
        return path
      end

      #-------------------------------------------------------------------------
      # The screen: nested message menus, no drawing of its own
      #-------------------------------------------------------------------------
      def self.menu(title, labels)
        return pbMessage(title, labels + [_INTL("Cancel")], labels.length + 1) rescue -1
      end

      def self.tools
        loop do
          c = menu(_INTL("Mod tools"), [_INTL("Hooks and events"), _INTL("Reload a mod"), _INTL("Reload all mods"),
                                         _INTL("Make a new mod"), _INTL("Write API reference"), _INTL("Write hook report")])
          case c
          when 0 then inspector
          when 1 then reload_menu
          when 2 then reload_all.each { |r| pbMessage(r[:message]) }
          when 3 then make_screen
          when 4 then pbMessage(_INTL("Written: {1}", write_reference))
          when 5 then pbMessage(_INTL("Written: {1}", write_hook_report))
          else break
          end
        end
      end

      def self.inspector
        loop do
          c = menu(_INTL("Hooks and events"), [_INTL("Events with handlers"), _INTL("Wrapped game methods"),
                                                _INTL("Method collisions"), _INTL("APIs mods provide")])
          case c
          when 0 then events_screen
          when 1 then pbMessage(wrapped_rows.map { |r| "#{r[:target]} (#{r[:form]}): #{r[:mods].join(', ')}" }.first(12).join("\n"))
          when 2 then pbMessage(API.collisions.map { |x| "#{x[:kind]}: #{x[:target]} (#{API::Attribution.display(x[:mod])})" }.first(8).join("\n").then { |t| t.empty? ? _INTL("None.") : t })
          when 3 then pbMessage(API.provided.map { |n, h| "#{n} v#{h[:version]} (#{API::Attribution.display(h[:mod])})" }.join("\n").then { |t| t.empty? ? _INTL("None.") : t })
          else break
          end
        end
      end

      def self.events_screen
        rows = event_rows.select { |r| r[:subscribers] > 0 }
        return pbMessage(_INTL("No event has a handler.")) if rows.empty?
        loop do
          c = menu(_INTL("Events"), rows.map { |r| ":#{r[:event]} (#{r[:subscribers]})" }.first(10))
          break if c < 0 || c >= [rows.length, 10].min
          subs = subscriber_rows(rows[c][:event])
          d = menu(_INTL("Handlers"), subs.map { |s| "#{s[:mod]}/#{s[:id]} #{s[:state]} #{s[:calls]}x #{s[:avg_ms]}ms #{s[:errors]}e" }.first(10))
          next if d < 0 || d >= [subs.length, 10].min
          s = subs[d][:sub]
          a = menu(subs[d][:id].to_s, [_INTL("Switch on"), _INTL("Switch off"), _INTL("Remove")])
          set_state(s, true) if a == 0
          set_state(s, false) if a == 1
          s.off if a == 2
        end
      end

      def self.reload_menu
        mods = (KIF::Mods.entries.select { |e| e.kind == :folder && e.loaded } rescue [])
        return pbMessage(_INTL("No folder mod is loaded.")) if mods.empty?
        c = menu(_INTL("Reload which mod?"), mods.map { |e| e.name.to_s }.first(10))
        return if c < 0 || c >= [mods.length, 10].min
        pbMessage(reload_mod(mods[c].id)[:message])
      end

      def self.make_screen
        n = pbMessageFreeText(_INTL("Name of the new mod (letters, digits, _ and -)?"), "", false, 40)
        return if n.to_s.strip.empty?
        path, why = make_mod(n)
        pbMessage(path ? _INTL("Made {1}. Edit main.rb, then restart or reload.", path) : why)
      end
    end

    def self.reload_mod(key); return Dev.reload_mod(key); end
    def self.reload_all; return Dev.reload_all; end
    def self.trace_dump; return Dev.trace_dump; end
    def self.write_reference; return Dev.write_reference; end
  end
end

# The settings (a global setting; the tools row exists only while Dev mode is On)
KIF::Options.define(:kif_mod_dev, 0, :global)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Mod Dev mode"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kif_mod_dev },
                 proc { |value| $PokemonSystem.kif_mod_dev = value; KIF::API::Dev.changed },
                 [_INTL("Normal play"),
                  _INTL("Tools for mod makers: stricter API checks, hook timings, reload, template.")])
}

KIF::Options.add(:others, :global) {
  next nil unless KIF::API.dev?
  ButtonOption.new(_INTL("Mod tools"), proc { KIF::API::Dev.tools }, _INTL("Hooks and events, reload, make a new mod, API reference"))
}
