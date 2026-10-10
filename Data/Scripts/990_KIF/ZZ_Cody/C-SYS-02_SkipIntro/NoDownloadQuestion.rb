#===============================================================================
# C-SYS-02 – No "where did you download the game?" question (Cody, 2026-10-09)
#   With no save files, PIF's intro (map 295, event 4) calls common event 108
#   "gameDownload Warning" instead of the game mode menu: a question about
#   where the game was downloaded, then a scam warning (and, for "Other",
#   the game quits and opens the Discord page). KIF skips it entirely.
#===============================================================================
module KIF
  module SkipIntro
    DOWNLOAD_QUESTION = "gameDownload Warning"

    def self.download_question?(id)
      ce = ($data_common_events[id] rescue nil)
      return !!(ce && ce.name == DOWNLOAD_QUESTION)
    end
  end
end

class Interpreter
  alias kif_nodlq_command_117 command_117 unless method_defined?(:kif_nodlq_command_117)

  def command_117
    return true if KIF::SkipIntro.download_question?(@parameters[0])
    return kif_nodlq_command_117
  end
end
