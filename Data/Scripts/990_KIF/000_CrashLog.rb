#===============================================================================
# Port debugging aid (not a KIF feature; Cody 2026-10-05: crash text couldn't
# be copied and no errorlog.txt was found).
#
# 1. Crashes while the KIF port's scripts load: PIF's script loader
#    (Data/Scripts.rxdata, load_scripts_from_folder) shows mkxp's plain error
#    box and logs nothing. From this file on, the loader is replaced by the
#    same loader that also writes the error to KIF_errorlog.txt.
# 2. Crashes in game: PIF writes them to errorlog.txt in the save folder
#    (%APPDATA%\<game>\errorlog.txt); the same text is now also appended to
#    KIF_errorlog.txt.
# KIF_errorlog.txt is in the Logs folder (000_Paths.rb; the game folder
# itself if a crash comes before that file loads).
#===============================================================================
module KIF
  module CrashLog
    FILE = "KIF_errorlog.txt"

    def self.write(text)
      path = defined?(KIF::Paths) ? KIF::Paths.log(FILE) : FILE
      File.open(path, "ab") do |f|
        f.write("\r\n=================\r\n\r\n[#{Time.now}]\r\n")
        f.write(text.to_s)
        f.write("\r\n")
      end
    rescue
      nil
    end

    def self.describe(e, file = nil)
      msg = "Exception: #{e.class}\r\nMessage: #{e.message}\r\n"
      msg = "While loading script: #{file}\r\n" + msg if file
      msg += "\r\nBacktrace:\r\n" + (e.backtrace || [])[0, 25].join("\r\n")
      return msg
    end
  end
end

# Same as PIF's loader (Data/Scripts.rxdata "Main"), plus the log
def load_scripts_from_folder(path)
  files   = []
  folders = []
  ignored = ['.', '..', '.git', '.idea', '.gitignore']
  Dir.foreach(path) do |f|
    next if ignored.include?(f)
    (File.directory?(path + "/" + f)) ? folders.push(f) : files.push(f)
  end
  files.sort!
  files.each do |f|
    code = File.open(path + "/" + f, "r") { |file| file.read }
    begin
      eval(code, nil, f)
      # 999_Main.rb is the game itself: when it returns, the player quit
      KIF::SessionLog.finish if f == "999_Main.rb" && defined?(KIF::SessionLog)
    rescue SystemExit
      # Closing the window: mkxp raises SystemExit out of whichever engine
      # call comes next (Graphics.update, Input.update, a transition...), and
      # PIF's own at_exit only runs on Kernel#exit - this is the one place
      # every way out of the game passes through
      (KIF::SessionLog.finish rescue nil) if defined?(KIF::SessionLog)
      raise
    rescue ScriptError, StandardError, SystemStackError, NoMemoryError => e
      KIF::CrashLog.write(KIF::CrashLog.describe(e, path + "/" + f))
      if e.is_a?(ScriptError)
        raise ScriptError.new(e.message + "\n\n(also logged in #{KIF::CrashLog::FILE})")
      end
      $!.message.sub!($!.message, traceback_report) rescue nil
      raise_traceback_error
    end
  end
  folders.sort!
  folders.each do |folder|
    load_scripts_from_folder(path + "/" + folder)
  end
end

alias kif_crash_pbPrintException pbPrintException unless defined?(kif_crash_pbPrintException)

def pbPrintException(e)
  begin
    KIF::CrashLog.write(KIF::CrashLog.describe(e))
  rescue
    nil
  end
  kif_crash_pbPrintException(e)
end
