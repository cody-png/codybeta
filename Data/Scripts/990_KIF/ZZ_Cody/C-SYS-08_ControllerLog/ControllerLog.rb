#===============================================================================
# C-SYS-08 – Controller log (2026-10-22)
#   KIF_log.txt says which controller the engine is using, once at start and
#   whenever it changes (plugged in, unplugged, another one taken), so a
#   "my controller doesn't work" report shows whether the game saw it at all.
#   The engine uses one controller at a time. Looked at every CHECK_EVERY
#   Input.update calls; does nothing on an engine without Input::Controller.
#===============================================================================
module KIF
  module ControllerLog
    CHECK_EVERY = 120

    class << self
      # the controller's name, or nil when none is in use
      def current
        c = Input::Controller
        return nil unless c.connected?
        n = (c.name rescue nil).to_s
        return n.empty? ? "?" : n
      end

      def step
        return if @off
        @tick = (@tick || 0) + 1
        return unless @tick == 1 || @tick % CHECK_EVERY == 0
        return (@off = true) unless defined?(Input::Controller)
        now = current
        return if @noted && now == @last
        @noted = true
        @last = now
        KIF.log(now ? "Controller: the game is using \"#{now}\"" : "Controller: none in use")
      rescue StandardError => e
        @off = true
        KIF.log("Controller: can't be read on this engine (#{e.class}: #{e.message})")
      end
    end
  end
end

module Input
  class << Input
    alias kif_cl_update update unless method_defined?(:kif_cl_update)
  end

  def self.update(*args)
    ret = kif_cl_update(*args)
    KIF::ControllerLog.step
    return ret
  end
end
