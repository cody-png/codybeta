#===============================================================================
# Mods and KIF hooking the same method (F-CORE-09, 2026-10-10)
#   KIF hooks some base methods with Module#prepend; mods (and Mod Manager)
#   hook with `alias old_name name` + a new `def name`. In Ruby, an alias
#   taken on a class with a prepended module copies the PREPENDED method, so
#   the mod's "old" method calls KIF's hook, whose super calls the mod's new
#   method again: stack level too deep. Mod Manager's title hook
#   (PokemonLoadScreen#pbStartLoadScreen, also hooked by KIF's sprite import,
#   save folder and session log) crashed the game at the title screen.
#   Every class or module that gets a prepended module from now on gets this
#   check: when an alias copies a prepended module's method, the alias is
#   pointed at the class's own method below the hooks instead, so the chain
#   becomes KIF's hooks -> the mod's method -> the original.
#   Loaded first in 990_KIF, before any KIF prepend.
#===============================================================================
module KIF
  module AliasGuard
    def method_added(name)
      super
      KIF::AliasGuard.repoint(self, name)
    end

    def self.repoint(klass, name)
      um = (klass.instance_method(name) rescue nil)
      return unless um && um.original_name != name
      orig = um.original_name
      anc = klass.ancestors
      idx = anc.index(klass)
      return unless idx && idx > 0
      pre = anc[0, idx]
      hit = pre.find do |m|
        (m.instance_methods(false) + m.private_instance_methods(false)).include?(orig) &&
          m.instance_method(orig).source_location == um.source_location
      end
      return unless hit
      # past every prepended hook (several can wrap one method) to the
      # class's own method
      below = um.super_method
      below = below.super_method while below && pre.include?(below.owner)
      return unless below
      vis = if klass.private_method_defined?(name) then :private
            elsif klass.protected_method_defined?(name) then :protected
            else :public
            end
      klass.send(:define_method, name, below)
      klass.send(vis, name)
    rescue StandardError => e
      KIF.log("Alias guard: #{klass}##{name}: #{e.class}: #{e.message}") if KIF.respond_to?(:log)
    end

    def self.protect(mod)
      return if (mod.singleton_class? rescue true)
      sc = mod.singleton_class
      sc.prepend(KIF::AliasGuard) unless sc.ancestors.include?(KIF::AliasGuard)
    end

    module PrependWatch
      def prepend(*mods)
        ret = super
        KIF::AliasGuard.protect(self) unless mods.include?(KIF::AliasGuard)
        return ret
      end
    end
  end
end

Module.prepend(KIF::AliasGuard::PrependWatch)
