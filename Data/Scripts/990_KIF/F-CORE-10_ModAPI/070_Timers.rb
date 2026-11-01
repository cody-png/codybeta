#===============================================================================
# F-CORE-10 Mod API - timers that count game steps
#
#   KIF::API.after(steps: 120) { ... }              once, in 120 steps
#   KIF::API.after(seconds: 3, id: "my_id") { ... } once, in 3 seconds (the same name as the game-method hook: the keywords tell them apart)
#   KIF::API.every(seconds: 10, scope: :always) { ... }
#   KIF::API.when_idle { ... }                      once, at the next moment the map is idle
#   KIF::API.map_idle?                              true while the map is quiet
#   timer = KIF::API.after(steps: 10) { }; timer.cancel
#
# Units are logic steps, 40 a second (the :tick event), NOT drawn frames:
# seconds = steps / 40. scope: :map (default) counts only while map_idle?,
# :always counts everywhere, :battle only in battle. The same id from the same
# mod replaces the older timer. At most 500 timers per mod. Timers are not saved
# and go away when the mod is unloaded. A timer that raises is logged once and
# cancelled after 5 errors in a row.
#===============================================================================
module KIF
  module API
    class Timer
      attr_reader :id, :mod, :scope, :repeat, :interval
      attr_accessor :left, :blk, :errors

      def initialize(id, mod, scope, left, repeat, blk)
        @id = id
        @mod = mod
        @scope = scope
        @left = left
        @interval = left
        @repeat = repeat
        @blk = blk
        @cancelled = false
        @errors = 0
      end

      def cancel; @cancelled = true; API::Timers.drop(self); return nil; end
      def cancelled?; return @cancelled; end
    end

    module Timers
      MAX_PER_MOD = 500 unless const_defined?(:MAX_PER_MOD)
      STEPS_PER_SECOND = 40 unless const_defined?(:STEPS_PER_SECOND)
      @list  ||= []
      @hooked ||= false

      class << self
        attr_reader :list
      end

      def self.count(mod = nil)
        return mod ? @list.count { |t| t.mod == mod } : @list.length
      end

      def self.add(kind, steps, seconds, id, scope, mod, locs, blk)
        raise ArgumentError, "KIF::API.#{kind} needs a block" unless blk
        key = mod || Attribution.key_from_caller(locs)
        scope = scope.to_sym
        unless [:map, :always, :battle].include?(scope)
          API.say("timerscope:#{key}", "Mod \"#{Attribution.display(key)}\": timer scope must be :map, :always or :battle")
          return nil
        end
        left = if steps then steps.to_i
               elsif seconds then (seconds.to_f * STEPS_PER_SECOND).round
               else 0
               end
        left = 1 if left < 1 && kind != :when_idle
        id = (id || "#{File.basename(locs[0].path.to_s)}:#{locs[0].lineno}").to_s
        old = @list.find { |t| t.mod == key && t.id == id }
        if old.nil? && count(key) >= MAX_PER_MOD
          API.say("timercap:#{key}", "Mod \"#{Attribution.display(key)}\" already has #{MAX_PER_MOD} timers; no more")
          return nil
        end
        t = Timer.new(id, key, scope, left, kind == :every, blk)
        i = old ? @list.index(old) : nil
        i ? @list[i] = t : @list << t
        ensure_hook
        return t
      end

      def self.drop(t)
        @list.delete(t)
        release_hook if @list.empty?
      end

      def self.ensure_hook
        return if @hooked
        @hooked = true
        API.on(:tick, "modapi_timers", mod: :kif) { |c| Timers.step(c[:scope]) }
      end

      def self.release_hook
        return unless @hooked
        @hooked = false
        API.subscribers(:tick).each { |s| s.off if s.id == "modapi_timers" }
      end

      # one logic step in `scope` (:map :battle :menu :title :other)
      def self.step(scope)
        idle = nil
        @list.dup.each do |t|
          next if t.cancelled?
          next if API.mod_off?(t.mod)
          ok = case t.scope
               when :always then true
               when :battle then scope == :battle
               else (idle = API.map_idle? if idle.nil?; idle)
               end
          next unless ok
          t.left -= 1
          next if t.left > 0
          if t.repeat then t.left = t.interval else drop(t) end
          run(t)
        end
      end

      def self.run(t)
        t.blk.call
        t.errors = 0
      rescue Exception => e
        raise if API.fatal?(e)
        t.errors += 1
        API.say("timer:#{t.mod}:#{t.id}:#{e.class}:#{e.message[0, 60]}",
                "Mod \"#{Attribution.display(t.mod)}\" timer #{t.id} raised #{e.class}: #{e.message[0, 160]} at #{(e.backtrace || [])[0].to_s.sub(/\A.*[\/\\]/, '')}")
        if t.errors >= API::BREAKER_ROW
          t.cancel
          KIF.log("Mod \"#{Attribution.display(t.mod)}\" timer #{t.id} cancelled after repeated errors")
        end
      end

      def self.remove_mod(key)
        n = @list.length
        @list.reject! { |t| t.mod == key }
        release_hook if @list.empty?
        return n - @list.length
      end
    end

    # KIF::API.after has two uses, told apart by the keywords:
    #   after("Class#method", "id", priority: 0, defer: false) { |call| }  - a hook on a game method (030_Hook.rb):
    #                                                    may set call.result
    #   after(steps: n | seconds: s, id: nil, scope: :map) { }             - a timer that runs once
    def self.after(first = nil, second = nil, steps: nil, seconds: nil, id: nil, scope: :map, priority: 0, mod: nil, defer: false, &blk)
      if steps || seconds
        return Timers.add(:after, steps, seconds, id || first, scope, mod, caller_locations(1, 40), blk)
      end
      return Hook.add(:after, first, second, priority, mod, defer, blk, caller_locations(1, 40))
    end

    # KIF::API.every(steps: n | seconds: s, id: nil, scope: :map) { } -> Timer
    def self.every(steps: nil, seconds: nil, id: nil, scope: :map, mod: nil, &blk)
      return Timers.add(:every, steps, seconds, id, scope, mod, caller_locations(1, 40), blk)
    end

    # KIF::API.when_idle(id = nil) { } - once, at the next moment the map is idle
    def self.when_idle(id = nil, mod: nil, &blk)
      return Timers.add(:when_idle, nil, nil, id, :map, mod, caller_locations(1, 40), blk)
    end

    # The map is quiet: the map scene, no battle, no message, no event running,
    # no move or transfer. (The one shared version of what the multiplayer menu
    # and Archipelago ask separately.)
    def self.map_idle?
      return false unless defined?(::Scene_Map) && $scene.is_a?(::Scene_Map)
      t = $game_temp
      return false if t.nil? || $game_player.nil?
      return false if t.message_window_showing || t.in_menu || t.in_battle
      return false if t.respond_to?(:player_transferring) && t.player_transferring
      return false if pbMapInterpreterRunning?
      return false if $game_player.moving? || $game_player.move_route_forcing
      return true
    rescue StandardError
      return false
    end

    on_unload(:timers) { |key| Timers.remove_mod(key) }
  end
end
