#===============================================================================
# PIF fix – the load screen's Language button (2026-11-02, hm-19)
# After a language is chosen there, PIF writes the whole selected save file
# again, in place (MultiSaves.rb: File.open(slot, 'wb') { Marshal.dump(...) }):
# a crash, a full disk or a closed window part-way left a cut file. The write
# that follows a language choice goes to a temporary file that replaces the
# slot only once it is complete (a failed write leaves the slot as it was).
#===============================================================================
module KIF
  module LanguageSlot
    WINDOW = 60.0   # seconds after the choice in which the next save-file write is made safe

    @armed_until = 0.0

    def self.now; return Process.clock_gettime(Process::CLOCK_MONOTONIC); end

    def self.arm; @armed_until = now + WINDOW; end

    # true once for the first save-file write after a choice
    def self.take?(path, mode)
      return false if @armed_until <= 0.0
      return false unless mode.is_a?(String) && mode.start_with?("w") && path.to_s =~ /\.rxdata\z/i
      armed = now < @armed_until
      @armed_until = 0.0
      return armed
    end

    module FileOpen
      def open(path, mode = "r", *rest, &blk)
        if blk && KIF::LanguageSlot.take?(path, mode)
          tmp = "#{path}.kif_tmp"
          begin
            ret = super(tmp, mode, *rest, &blk)
            File.rename(tmp, path)
            return ret
          rescue StandardError
            File.delete(tmp) if File.exist?(tmp) rescue nil
            raise
          end
        end
        return super
      end
    end
  end
end

File.singleton_class.prepend(KIF::LanguageSlot::FileOpen) unless File.singleton_class.ancestors.include?(KIF::LanguageSlot::FileOpen)

alias kif_lang_pbChooseLanguage pbChooseLanguage unless defined?(kif_lang_pbChooseLanguage)

def pbChooseLanguage(*args)
  ret = kif_lang_pbChooseLanguage(*args)
  KIF::LanguageSlot.arm
  return ret
end
