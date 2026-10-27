#===============================================================================
# C-SYS-09 – Play to load screen, timed (2026-10-27)
#   A player's screen stayed black for 2.5-3 minutes between the title's Play
#   and the load screen, and nothing in the log said where (verbose logging
#   wasn't on, and it didn't time this stretch either). Always on now:
#     * each step on the way that takes over STEP_SECONDS gets a line,
#       "Load screen: <step> took N s" (verbose logging: every step);
#     * Play to the load screen's first frame, when over TOTAL_SECONDS:
#       "Load screen: Play to load screen took N s (N s outside the timed steps)".
#   Time a message box waits for the player isn't counted. The start-up
#   downloads and version check keep their own "Start-up:" lines (C-SYS-06);
#   they're timed here too, without a second line, so they aren't counted as
#   "outside the timed steps".
#===============================================================================
module KIF
  module LoadTiming
    STEP_SECONDS  = 1.0
    TOTAL_SECONDS = 3.0

    @start = nil

    def self.now
      return Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.active?
      return !@start.nil?
    end

    # Play pressed (restart: a new Play); the load screen opened another way
    # (no title, debug start) starts it only if nothing did
    def self.start!(restart = false)
      return if @start && !restart
      @start = now
      @depth = 0
      @timed = 0.0
      @waited = 0.0
    end

    def self.stop!
      @start = nil
    end

    def self.step(label, quiet = false)
      return yield unless @start
      t = now
      w = @waited
      @depth += 1
      begin
        return yield
      ensure
        if @start
          @depth -= 1
          secs = now - t - (@waited - w)
          @timed += secs if @depth == 0
          unless quiet
            line = format("Load screen: %s took %.1f s", label, secs)
            secs > STEP_SECONDS ? KIF.log(line) : KIF.verbose(line)
          end
        end
      end
    end

    # a message box waiting for the player: not the game's time
    def self.waiting
      return yield unless @start
      t = now
      begin
        return yield
      ensure
        @waited += now - t if @start
      end
    end

    # the load screen's first frame
    def self.finish!
      return unless @start
      total = now - @start - @waited
      line = format("Load screen: Play to load screen took %.1f s (%.1f s outside the timed steps)", total, [total - @timed, 0].max)
      total > TOTAL_SECONDS ? KIF.log(line) : KIF.verbose(line)
      stop!
    end

    module Screen
      def pbStartLoadScreen(*args)
        KIF::LoadTiming.start!
        return super
      ensure
        KIF::LoadTiming.stop!   # left without a first frame (Quit, an error)
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::LoadTiming::Screen)

# Play: PIF's closeTitle (kept PIF's own) disposes the title first. Quit
# disposes it too; the game closes then, nothing more is timed.
class Scene_Intro
  alias kif_ldt_disposeTitle disposeTitle unless method_defined?(:kif_ldt_disposeTitle) || private_method_defined?(:kif_ldt_disposeTitle)

  def disposeTitle
    KIF::LoadTiming.start!(true)
    KIF::LoadTiming.step("closing the title") { kif_ldt_disposeTitle }
  end
end

class PokemonLoadScreen
  alias kif_ldt_initialize initialize unless method_defined?(:kif_ldt_initialize) || private_method_defined?(:kif_ldt_initialize)
  alias kif_ldt_copyKeybindings copyKeybindings unless method_defined?(:kif_ldt_copyKeybindings) || private_method_defined?(:kif_ldt_copyKeybindings)

  def initialize(*args)
    KIF::LoadTiming.step("picking the newest save") { kif_ldt_initialize(*args) }
  end

  def copyKeybindings
    KIF::LoadTiming.step("controller bindings file") { kif_ldt_copyKeybindings }
  end
end

class PokemonLoad_Scene
  alias kif_ldt_pbStartScene pbStartScene unless method_defined?(:kif_ldt_pbStartScene) || private_method_defined?(:kif_ldt_pbStartScene)
  alias kif_ldt_pbSetParty pbSetParty unless method_defined?(:kif_ldt_pbSetParty) || private_method_defined?(:kif_ldt_pbSetParty)
  alias kif_ldt_pbStartScene2 pbStartScene2 unless method_defined?(:kif_ldt_pbStartScene2) || private_method_defined?(:kif_ldt_pbStartScene2)

  def pbStartScene(*args)
    KIF::LoadTiming.step("drawing the save panels") { kif_ldt_pbStartScene(*args) }
  end

  def pbSetParty(*args)
    KIF::LoadTiming.step("party sprites") { kif_ldt_pbSetParty(*args) }
  end

  def pbStartScene2(*args)
    KIF::LoadTiming.finish!
    kif_ldt_pbStartScene2(*args)
  end
end

module SaveData
  class << self
    alias kif_ldt_read_from_file read_from_file unless method_defined?(:kif_ldt_read_from_file) || private_method_defined?(:kif_ldt_read_from_file)
    alias kif_ldt_get_newest_save_slot get_newest_save_slot unless method_defined?(:kif_ldt_get_newest_save_slot) || private_method_defined?(:kif_ldt_get_newest_save_slot)

    def read_from_file(file_path)
      KIF::LoadTiming.step("reading save #{File.basename(file_path.to_s, '.*')}") { kif_ldt_read_from_file(file_path) }
    end

    def get_newest_save_slot(*args)
      KIF::LoadTiming.step("reading every save slot") { kif_ldt_get_newest_save_slot(*args) }
    end
  end
end

module KIF
  module SaveFolder
    class << self
      alias kif_ldt_first_launch first_launch unless method_defined?(:kif_ldt_first_launch) || private_method_defined?(:kif_ldt_first_launch)
      alias kif_ldt_update_menu update_menu unless method_defined?(:kif_ldt_update_menu) || private_method_defined?(:kif_ldt_update_menu)

      def first_launch(*args)
        KIF::LoadTiming.step("old save folder check") { kif_ldt_first_launch(*args) }
      end

      def update_menu(*args)
        KIF::LoadTiming.step("old saves to import") { kif_ldt_update_menu(*args) }
      end
    end
  end

  module SessionLog
    class << self
      alias kif_ldt_sprite_report sprite_report unless method_defined?(:kif_ldt_sprite_report) || private_method_defined?(:kif_ldt_sprite_report)

      def sprite_report(*args)
        KIF::LoadTiming.step("sprite count") { kif_ldt_sprite_report(*args) }
      end
    end
  end
end

# timed for the "outside" figure only: C-SYS-06 logs them as "Start-up:"
alias kif_ldt_updateHttpSettingsFile updateHttpSettingsFile unless defined?(kif_ldt_updateHttpSettingsFile)
alias kif_ldt_updateCustomDexFile updateCustomDexFile unless defined?(kif_ldt_updateCustomDexFile)
alias kif_ldt_find_newer_available_version find_newer_available_version unless defined?(kif_ldt_find_newer_available_version)
alias kif_ldt_checkEnableSpritesDownload checkEnableSpritesDownload unless defined?(kif_ldt_checkEnableSpritesDownload)
alias kif_ldt_pbMessageDisplay pbMessageDisplay unless defined?(kif_ldt_pbMessageDisplay)

def updateHttpSettingsFile(*args)
  KIF::LoadTiming.step("PIF settings file", true) { kif_ldt_updateHttpSettingsFile(*args) }
end

def updateCustomDexFile(*args)
  KIF::LoadTiming.step("dex.json", true) { kif_ldt_updateCustomDexFile(*args) }
end

def find_newer_available_version(*args)
  KIF::LoadTiming.step("update check", true) { kif_ldt_find_newer_available_version(*args) }
end

def checkEnableSpritesDownload(*args)
  KIF::LoadTiming.step("sprite download check") { kif_ldt_checkEnableSpritesDownload(*args) }
end

def pbMessageDisplay(*args, &block)
  KIF::LoadTiming.waiting { kif_ldt_pbMessageDisplay(*args, &block) }
end
