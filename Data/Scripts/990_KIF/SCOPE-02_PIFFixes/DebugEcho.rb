#===============================================================================
# SCOPE-02 – Debug console text with a % in it no longer crashes the game
# PIF's Kernel#echo (001_Technical/001_Debugging/002_DebugConsole.rb:40)
# prints with printf(string), so in debug mode any text holding a % sign is
# read as a format string ("%F" -> ArgumentError: malformed format string).
# Found 2026-10-09 by a real-engine door crawl: arriving in Dragon's Den
# echoed such a line once in a run. Same output, written as plain text
# ($stdout.write like printf does: mkxp turns Kernel#print into a pop-up).
#===============================================================================
module Kernel
  def echo(string)
    return unless $DEBUG
    $stdout.write(string.is_a?(String) ? string : string.inspect)
  rescue IOError, SystemCallError
    nil
  end
end
