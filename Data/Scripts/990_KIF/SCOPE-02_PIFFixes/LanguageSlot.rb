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

  end
end

# (an alias, not a prepend: code that wraps File.open by aliasing it, as the kit's tests and mods do, would loop through a prepended one)
class << File
  alias kif_lang_open open unless method_defined?(:kif_lang_open)

  def open(*args, **kw, &blk)
    if blk && !args.empty? && KIF::LanguageSlot.take?(args[0], args[1])
      path = args[0]
      tmp = "#{path}.kif_tmp"
      begin
        ret = kif_lang_open(tmp, *args[1..-1], **kw, &blk)
        File.rename(tmp, path)
        return ret
      rescue StandardError
        File.delete(tmp) if File.exist?(tmp) rescue nil
        raise
      end
    end
    return kif_lang_open(*args, **kw, &blk)
  end
end

alias kif_lang_pbChooseLanguage pbChooseLanguage unless defined?(kif_lang_pbChooseLanguage)

def pbChooseLanguage(*args)
  ret = kif_lang_pbChooseLanguage(*args)
  KIF::LanguageSlot.arm
  return ret
end
