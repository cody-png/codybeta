#===============================================================================
# Newest save slot, without reading every save (2026-11-01, PERF-BOOT)
#
# SaveData.get_newest_save_slot (MultiSaves.rb:180) reads all ten slots in
# full (Marshal.load of 1 MB or more each, ~0.2 s a save on a PC, several
# seconds on a phone) just to compare each one's last_time_saved, and it runs
# on every start (the load screen), again after an import. A save whose size
# and time haven't changed since it was last read has the same time in it:
# that is kept for the session and in Cache/KIFBoot/save_times.kbc. A save
# that is new or changed is read as before. Conversions a read applies to an
# old save still happen, the first time that save is read.
#===============================================================================
module KIF
  module Perf
    module SaveScan
      NAME = "save_times"
      @known = nil   # full path => [size, mtime, last_time_saved]
      @dirty = false

      def self.known
        @known ||= (BootCache.read(NAME, 0) || {})
        @known = {} unless @known.is_a?(Hash)
        return @known
      end

      # a save's size and time, nil when it can't be looked at
      def self.stamp(path)
        st = File.stat(path)
        return [st.size, st.mtime.to_f]
      rescue SystemCallError
        return nil
      end

      # the time kept for a save that hasn't changed since, or nil
      def self.saved_time(path)
        st = stamp(path)
        e = st && known[path]
        return (e && e[0] == st[0] && e[1] == st[1] && e[2].is_a?(Time)) ? e[2] : nil
      end

      # st: the save's stamp taken before it was read (a read may convert and rewrite it)
      def self.remember(path, st, time)
        return unless st && time.is_a?(Time)
        known[path] = [st[0], st[1], time]
        @dirty = true
      end

      # after a scan: slots that went away are dropped, a changed list is saved
      def self.flush(paths)
        k = known
        gone = k.keys - paths
        gone.each { |p| k.delete(p) }
        @dirty ||= !gone.empty?
        return unless @dirty
        @dirty = false
        BootCache.write(NAME, 0, k)
      end
    end
  end
end

module SaveData
  class << self
    alias kif_perf_get_newest_save_slot get_newest_save_slot unless method_defined?(:kif_perf_get_newest_save_slot)

    # MultiSaves.rb:180, with a save's time taken from what is kept when the
    # file is as it was
    def get_newest_save_slot
      return kif_perf_get_newest_save_slot unless defined?(KIF::Perf::BootCache) && KIF::Perf::SaveScan.respond_to?(:saved_time)
      newest_time = Time.at(0) # the Epoch
      newest_slot = nil
      paths = []
      self.each_slot do |file_slot|
        full_path = self.get_full_path(file_slot)
        next if !File.file?(full_path)
        paths << full_path
        # a slot that can't be read, has no player or a save time that isn't
        # a Time is skipped (SCOPE-02 SaveRobustness item 2 lives here)
        begin
          save_time = KIF::Perf::SaveScan.saved_time(full_path)
          unless save_time
            st = KIF::Perf::SaveScan.stamp(full_path)
            save_time = self.read_from_file(full_path)[:player].last_time_saved || Time.at(1)
            KIF::Perf::SaveScan.remember(full_path, st, save_time)
          end
          newer = save_time > newest_time
        rescue StandardError
          next
        end
        if newer
          newest_time = save_time
          newest_slot = file_slot
        end
      end
      KIF::Perf::SaveScan.flush(paths)
      # Port old save
      if newest_slot.nil? && File.file?(self.get_full_path(OLD_SAVE_SLOT))
        file_copy(self.get_full_path(OLD_SAVE_SLOT), self.get_full_path(MANUAL_SLOTS[0]))
        return MANUAL_SLOTS[0]
      end
      return newest_slot
    end
  end
end
