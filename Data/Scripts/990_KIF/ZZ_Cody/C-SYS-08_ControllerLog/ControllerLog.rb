#===============================================================================
# C-SYS-08 – Controller log (2026-10-22)
#   KIF_log.txt says which controller the engine is using, once at start and
#   whenever it changes (plugged in, unplugged, another one taken), so a
#   "my controller doesn't work" report shows whether the game saw it at all.
#   The engine uses one controller at a time. Looked at every CHECK_EVERY
#   Input.update calls; does nothing on an engine without Input::Controller.
#   (2026-10-26) It also notes whether a controller button or a key was
#   pressed last, so KIF::Keys names "B" rather than "Esc" to a controller
#   player.
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
        note_device if @last
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

      # Was a controller button pressed more recently than a key? Hints name
      # that button then (KIF::Keys). Looked at only while a controller is in
      # use; the key states only while the controller was the last one.
      def note_device
        c = Input::Controller
        return unless c.respond_to?(:raw_button_states) && Input.respond_to?(:raw_key_states)
        # a press is true or non-zero: an engine giving 0/1 would make every 0 a press in Ruby
        if c.raw_button_states.any? { |v| v && v != 0 }
          @pad = true
        elsif @pad && Input.raw_key_states.any? { |v| v && v != 0 }
          @pad = false
        end
      end

      def pad?
        return !!(@pad && @last && !@off)
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
