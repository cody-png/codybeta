#===============================================================================
# Module gate (see 000_Core/011_KIF_Modules.rb). Loads after every feature.
#
# For each method a module's code added to or changed in a class that existed
# before the features loaded (PIF's classes), the method is replaced by a
# switch:
#   module active -> the module's version
#   module Off    -> the version the game had without that module:
#                    1. the method the module saved under another name with
#                       `alias` (keeps other modules' hooks in the chain),
#                    2. otherwise the method as it was before any feature
#                       loaded (PIF's, or a core version),
#                    3. otherwise the parent class's method.
# Methods that didn't exist before (new helpers) are left alone: only module
# code reaches them. Modules a feature prepends to a PIF class get the same
# switch, falling back to `super`.
#===============================================================================
module KIF
  module Modules
    ALIAS_RE = /^\s*alias(?:_method)?\s+:?([A-Za-z_][\w]*[?!=]?|\[\]=?|[+\-*\/<>=!~%&|^]+)\s*,?\s*:?([A-Za-z_][\w]*[?!=]?|\[\]=?|[+\-*\/<>=!~%&|^]+)/
    @alias_cache = {}
    @gated = Hash.new(0)
    class << self
      attr_reader :gated
    end

    # orig_name => [new names] for `alias new orig` lines in a module's file
    def self.file_aliases(file)
      return @alias_cache[file] if @alias_cache.has_key?(file)
      h = Hash.new { |hh, k| hh[k] = [] }
      path = file
      path = basename_map[file] || file unless file.include?("/") || file.include?("\\")
      begin
        File.foreach(path) do |line|
          next unless line =~ ALIAS_RE
          h[$2.to_sym] << $1.to_sym
        end
      rescue
      end
      @alias_cache[file] = h
      return h
    end

    def self.has_method?(mod, name)
      return mod.method_defined?(name) || mod.private_method_defined?(name)
    end

    # [:send, name] or [:um, UnboundMethod] or nil (new method)
    def self.fallback_for(mod, name, um, file)
      orig = um.original_name
      file_aliases(file)[orig].each do |nm|
        next if nm == name
        next unless has_method?(mod, nm)
        other = own_method(mod, nm) || (mod.instance_method(nm) rescue nil)
        next if other.nil? || other == um
        return [:send, nm]
      end
      snap = @snapshot[[mod, name]]
      if snap && snap.source_location != um.source_location
        return [:um, snap]
      end
      anc = mod.ancestors
      idx = anc.index(mod)
      return nil unless idx
      anc[(idx + 1)..-1].each do |a|
        next unless a.instance_methods(false).include?(name) || a.private_instance_methods(false).include?(name)
        return [:um, own_method(a, name) || a.instance_method(name)]
      end
      return nil
    end

    def self.uses_keywords?(um)
      return um.parameters.any? { |t, _| t == :key || t == :keyreq || t == :keyrest }
    end

    def self.install_switch(mod, name, um, id, fb)
      vis = if mod.private_method_defined?(name) then :private
            elsif mod.protected_method_defined?(name) then :protected
            else :public end
      kw = uses_keywords?(um) || (fb[0] == :um && uses_keywords?(fb[1]))
      if fb[0] == :send
        nm = fb[1]
        if kw
          mod.send(:define_method, name) do |*args, **opts, &blk|
            KIF::Modules.active?(id) ? um.bind_call(self, *args, **opts, &blk) : __send__(nm, *args, **opts, &blk)
          end
        else
          mod.send(:define_method, name) do |*args, &blk|
            KIF::Modules.active?(id) ? um.bind_call(self, *args, &blk) : __send__(nm, *args, &blk)
          end
        end
      else
        fum = fb[1]
        if kw
          mod.send(:define_method, name) do |*args, **opts, &blk|
            KIF::Modules.active?(id) ? um.bind_call(self, *args, **opts, &blk) : fum.bind_call(self, *args, **opts, &blk)
          end
        else
          mod.send(:define_method, name) do |*args, &blk|
            KIF::Modules.active?(id) ? um.bind_call(self, *args, &blk) : fum.bind_call(self, *args, &blk)
          end
        end
      end
      mod.send(vis, name) unless vis == :public
      @gated[id] += 1
    end

    def self.install_super_switch(mod, name, um, id)
      vis = if mod.private_method_defined?(name) then :private
            elsif mod.protected_method_defined?(name) then :protected
            else :public end
      if uses_keywords?(um)
        mod.send(:define_method, name) do |*args, **opts, &blk|
          KIF::Modules.active?(id) ? um.bind_call(self, *args, **opts, &blk) : super(*args, **opts, &blk)
        end
      else
        mod.send(:define_method, name) do |*args, &blk|
          KIF::Modules.active?(id) ? um.bind_call(self, *args, &blk) : super(*args, &blk)
        end
      end
      mod.send(vis, name) unless vis == :public
      @gated[id] += 1
    end

    def self.gate_methods
      # code that existed before the features loaded (same file names exist
      # in PIF and KIF, e.g. 003_AI_Switch.rb) is never switched
      old_code = {}
      @snapshot.each_value { |u| l = u.source_location; old_code[l] = true if l }
      bases = @snapshot_mods.keys
      seen_prepends = {}
      bases.each do |m|
        names = (m.instance_methods(false) + m.private_instance_methods(false) rescue [])
        names.each do |name|
          um = own_method(m, name)
          next unless um
          loc = um.source_location
          next unless loc
          id = for_file(loc[0])
          next unless id
          snap = @snapshot[[m, name]]
          next if snap && snap == um
          next if old_code[loc]
          fb = fallback_for(m, name, um, loc[0])
          next unless fb
          begin
            install_switch(m, name, um, id, fb)
          rescue => e
            KIF.log("Module gate: #{m}##{name} not switched (#{e.class}: #{e.message})")
          end
        end
        # modules prepended to this class by a feature
        anc = (m.ancestors rescue [])
        own = anc.index(m) || 0
        anc[0...own].each do |pre|
          next if @snapshot_mods[pre] || seen_prepends[pre] || no_gate?(pre)
          seen_prepends[pre] = true
          (pre.instance_methods(false) + pre.private_instance_methods(false)).each do |name|
            um = own_method(pre, name)
            next unless um && um.source_location
            id = for_file(um.source_location[0])
            next unless id
            begin
              install_super_switch(pre, name, um, id)
            rescue => e
              KIF.log("Module gate: #{pre}##{name} not switched (#{e.class}: #{e.message})")
            end
          end
        end
      end
    end

    def self.install_gate
      t = Time.now
      gate_methods
      handlers = gate_handler_hashes
      ms = ((Time.now - t) * 1000).round
      parts = MODULES.keys.map { |id| "#{id} #{@gated[id]}" }.join(", ")
      KIF.log("Modules: #{@gated.values.sum} switches (#{parts}), #{handlers} handlers, #{ms} ms")
      @snapshot = {}   # not needed any more
      @snapshot_mods = {}
    end
  end
end

KIF::Modules.install_gate
