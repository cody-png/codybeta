#===============================================================================
# C-RAND-01 – settings only take effect after Randomize now.
# While the Randomizer screen is open, the menus edit a draft. Leaving with
# changes asks to Randomize now, keep them for later, or undo them. Kept
# changes wait in the save (marked * next time) and the game keeps using the
# settings it was last randomized with. The new-game intro is unchanged.
#===============================================================================
module KIF
  module Rand
    BAN_KINDS = [:pokemon, :moves, :abilities, :items]

    class << self
      attr_accessor :applied_state
    end

    def self.drafting?
      return !@applied_state.nil?
    end

    def self.setting_keys
      return (SETTINGS + DATA_SETTINGS).map(&:first).uniq
    end

    # Everything the menus can change, as plain values
    def self.capture
      s = {}
      setting_keys.each { |k| s[k] = get(k) }
      s[:__seed] = seed
      BAN_KINDS.each { |k| s[:"__ban_#{k}"] = ban_list(k) }
      return s
    end

    # Order doesn't matter (banning, unbanning and banning again is no change)
    def self.ban_list(kind)
      return bans(kind).uniq.sort_by(&:to_s)
    end

    def self.restore(state)
      return unless state.is_a?(Hash)
      setting_keys.each do |k|
        next unless state.key?(k)
        v = as_int(state[k], 0)
        set(k, v) if get(k) != v
      end
      data[:seed] = state[:__seed] if state[:__seed].is_a?(String)
      BAN_KINDS.each do |k|
        list = state[:"__ban_#{k}"]
        bans(k).replace(list) if list.is_a?(Array)
      end
      sync_masters
    rescue => e
      KIF.log("Randomizer settings couldn't be restored (#{e.class}: #{e.message})")
    end

    def self.changed_keys
      return [] unless @applied_state
      now = capture
      return now.keys.select { |k| now[k] != @applied_state[k] }
    end

    def self.changed?(key)
      return false unless @applied_state
      return capture_one(key) != @applied_state[key]
    end

    def self.capture_one(key)
      return seed if key == :__seed
      return ban_list(key.to_s.sub("__ban_", "").to_sym) if key.to_s.start_with?("__ban_")
      return get(key)
    end

    def self.mark(key, text)
      return changed?(key) ? "#{text} *" : text
    end

    # Runs the block with the settings the game is really using
    def self.with_applied
      return yield unless @applied_state
      draft = capture
      restore(@applied_state)
      begin
        return yield
      ensure
        restore(draft)
      end
    end

    def self.open_draft
      return if $game_switches && $game_switches[SWITCH_DURING_INTRO]
      @applied_state = capture
      pending = data[:pending]
      restore(pending) if pending.is_a?(Hash)
    end

    def self.close_draft
      return unless @applied_state
      begin
        n = changed_keys.length
        if n == 0
          data.delete(:pending)
          return
        end
        cmds = [_INTL("Randomize now"), _INTL("Keep for later"), _INTL("Undo changes")]
        msg = n == 1 ? _INTL("You changed 1 setting. Settings take effect when you Randomize now.") :
                       _INTL("You changed {1} settings. Settings take effect when you Randomize now.", n)
        case pbMessage(msg, cmds, 2)
        when 0
          randomize_now
          pbMessage(_INTL("Done!"))
        when 2
          restore(@applied_state)
          data.delete(:pending)
        else
          data[:pending] = capture
          restore(@applied_state)
        end
      ensure
        @applied_state = nil
      end
    end

    class << self
      alias kif_apply_randomize_now randomize_now unless method_defined?(:kif_apply_randomize_now)
      alias kif_apply_view_log view_log unless method_defined?(:kif_apply_view_log)

      def randomize_now
        kif_apply_randomize_now
      ensure
        if @applied_state
          @applied_state = capture
          data.delete(:pending)
        end
      end

      def view_log
        with_applied { kif_apply_view_log }
      end
    end
  end
end

class RandomizerOptionsScene
  alias kif_apply_pbStartScene pbStartScene unless method_defined?(:kif_apply_pbStartScene)
  alias kif_apply_pbEndScene pbEndScene unless method_defined?(:kif_apply_pbEndScene)

  def pbStartScene(inloadscreen = false)
    KIF::Rand.open_draft
    kif_apply_pbStartScene(inloadscreen)
  end

  def pbEndScene
    KIF::Rand.close_draft
    kif_apply_pbEndScene
  end
end
