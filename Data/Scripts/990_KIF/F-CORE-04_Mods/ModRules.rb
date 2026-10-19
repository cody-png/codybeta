#===============================================================================
# What a mod's mod.json asks of KIF (2026-10-16). Read for every folder mod
# that is On, right before its scripts load:
#
#   "requires_kif": ">=0.21.52"      the KIF versions it works with. A plain
#                                    version means "this one or newer";
#                                    several are joined with commas
#                                    (">=0.21.52, <0.23").
#   "incompatible": ["other_mod"]    mods it doesn't work with (mod.json id
#                                    or folder name)
#   "replaces":     ["F-BATTLE-08_LevelCaps"]   KIF features it takes over
#                                    (KIF::Features, 000_Core/011)
#   "locks":        {"shinyodds": 16}           settings it sets
#   "modules":      {"auto_battle": "off"}      modules it sets
#                                    (KIF::Locks, 000_Core/002)
#   "catalog":      "owner/repo@branch"         its own mod catalog, listed
#                                    in Browse (ModCatalog.rb)
#   "load_after":   ["other_mod"]    load after these mods when they are
#                                    installed (an order only, nothing is
#                                    required; Mods.rb NativeSource#order)
#
# A mod whose KIF version doesn't match, that clashes with a mod that is On,
# or that needs a mod that couldn't load, isn't loaded: Mods shows it as
# BLOCKED with the reason. Its replaces / locks are undone if its scripts
# fail. Mod Manager's mods (it loads them itself) get their replaces, locks
# and modules applied after they load.
#===============================================================================
module KIF
  module ModRules
    module_function

    def kif_version
      return defined?(KIF::PORT_VERSION) ? KIF::PORT_VERSION.to_s : "0"
    end

    def parts(v)
      return v.to_s.scan(/\d+/).map(&:to_i)
    end

    def compare(a, b)
      x = parts(a)
      y = parts(b)
      n = [x.length, y.length].max
      return (x + [0] * (n - x.length)) <=> (y + [0] * (n - y.length))
    end

    # ">=0.21.52, <0.23" -> [[">=", "0.21.52"], ["<", "0.23"]]
    def constraints(spec)
      list = spec.is_a?(Array) ? spec : spec.to_s.split(",")
      return list.map do |c|
        c = c.to_s.strip
        next nil if c.empty?
        op = c[/\A(>=|<=|==|=|>|<|~>)/] || ">="
        [op, c.sub(/\A(>=|<=|==|=|>|<|~>)\s*/, "")]
      end.compact
    end

    def version_ok?(spec, have = kif_version)
      return true if spec.nil? || spec.to_s.strip.empty?
      constraints(spec).all? do |op, v|
        c = compare(have, v)
        case op
        when ">=" then c >= 0
        when ">"  then c > 0
        when "<=" then c <= 0
        when "<"  then c < 0
        when "~>" then c >= 0 && parts(have)[0, [parts(v).length - 1, 1].max] == parts(v)[0, [parts(v).length - 1, 1].max]
        else c == 0
        end
      end
    end

    # "KIF 0.21.52 or newer" (for messages)
    def version_text(spec)
      list = constraints(spec)
      return list.map do |op, v|
        case op
        when ">=" then _INTL("KIF {1} or newer", v)
        when ">"  then _INTL("a KIF newer than {1}", v)
        when "<=" then _INTL("KIF {1} or older", v)
        when "<"  then _INTL("a KIF older than {1}", v)
        when "~>" then _INTL("KIF {1}.x", parts(v)[0, [parts(v).length - 1, 1].max].join("."))
        else _INTL("KIF {1}", v)
        end
      end.join(_INTL(" and "))
    end

    def ids_in(list)
      return Array(list).map { |x| x.is_a?(Hash) ? x["id"].to_s : x.to_s }.reject(&:empty?)
    end

    def json_for(e)
      return nil unless e.kind == :folder || e.kind == :mod_manager
      j = File.join(e.path.to_s, "mod.json")
      return File.file?(j) ? KIF::Mods.read_json(j) : nil
    end

    # Why a mod can't load, or nil. on: {id or folder => name} of mods that
    # are On; blocked: ids / folders of mods that won't load
    def blocked_reason(e, json, on, blocked = {})
      return nil unless json
      spec = json["requires_kif"]
      unless version_ok?(spec)
        return _INTL("Needs {1} (this is KIF {2}).", version_text(spec), kif_version)
      end
      mine = [e.id, json["id"].to_s].reject(&:empty?)
      bad = ids_in(json["incompatible"]).reject { |x| mine.include?(x) }.select { |x| on.has_key?(x) }
      unless bad.empty?
        return _INTL("Doesn't work with {1}. Switch one of them Off.", bad.map { |x| on[x] }.uniq.join(", "))
      end
      dead = ids_in(json["dependencies"]).select { |x| blocked.has_key?(x) }
      unless dead.empty?
        return _INTL("Needs {1}, which couldn't start.", dead.map { |x| blocked[x] }.uniq.join(", "))
      end
      return nil
    end

    # replaces / locks / modules of one mod
    def apply(owner, name, json)
      return unless json.is_a?(Hash)
      Array(json["replaces"]).each { |f| KIF::Features.replace(f.to_s, :by => name, :owner => owner) }
      if json["locks"].is_a?(Hash)
        json["locks"].each { |k, v| KIF::Locks.set(k, v, :by => name, :owner => owner) }
      end
      if json["modules"].is_a?(Hash)
        json["modules"].each { |k, v| KIF::Locks.set_module(k, v, :by => name, :owner => owner) }
      end
      # the mod's own catalog: Browse lists it, its updates come from there
      if json["catalog"].is_a?(String) && defined?(KIF::ModCatalog)
        c = KIF::ModCatalog.parse_catalog(json["catalog"])
        KIF::ModCatalog.add_catalog(c.local? ? c.path : c.repo, :branch => c.branch, :name => name) if c
      end
    end

    def release(owner)
      KIF::Features.release(owner)
      KIF::Locks.release(owner)
    end

    # Mod Manager loads its own mods; their rules apply once it has
    def apply_mod_manager
      return unless defined?(::ModManager) && ::ModManager.respond_to?(:registry) && ::ModManager.respond_to?(:load_order)
      ::ModManager.load_order.each do |id|
        info = (::ModManager.registry[id] rescue nil)
        next unless info && info.respond_to?(:folder_path)
        j = File.join(info.folder_path.to_s, "mod.json")
        next unless File.file?(j)
        apply("mm:#{id}", info.name.to_s, KIF::Mods.read_json(j))
      end
    rescue StandardError => e
      KIF.log("Mod rules: Mod Manager's mods not read (#{e.class}: #{e.message})")
    end
  end
end
