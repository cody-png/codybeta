#===============================================================================
# SCOPE-02 – the engine's frame time in either unit (2026-10-21)
#   Graphics.delta is the time the last frame took. PIF 6.8.2's mkxp-z gives
#   it in microseconds (an Integer); newer mkxp-z builds (the one old KIF
#   0.20.7 shipped) give seconds (a Float). PIF's Graphics.delta_s only
#   divides by 1,000,000, so on a newer engine water, autotiles, weather and
#   the credits barely move (KIF 0.19.8 hit this in 2024; old KIF's scripts
#   checked System::VERSION instead). Both units work now.
#===============================================================================
module KIF
  module EngineTime
    module_function

    # shortcut: a Float above 100 is taken as microseconds (no frame lasts 100 s)
    def seconds(d)
      return 0.0 if d.nil?
      return d / 1_000_000.0 if d.is_a?(Integer) || d > 100
      return d.to_f
    end

    def microseconds(d)
      return (seconds(d) * 1_000_000).round
    end
  end
end

module Graphics
  def self.delta_s
    return KIF::EngineTime.seconds(self.delta)
  end
end
