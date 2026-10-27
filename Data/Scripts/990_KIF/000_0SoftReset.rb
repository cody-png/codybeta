#===============================================================================
# Soft reset (F12) as a real restart (2026-10-18)
#   F12 makes the engine run every script again inside the same game, with
#   everything from before still in memory. KIF's hooks are set up once, so
#   a second run left some of them half done: after F12 during a battle the
#   Battle AI mixed PIF's and DemICE's code (an error on every turn, the foe
#   couldn't attack) and saves afterwards could miss changes to your team.
#   So when the scripts run a second time, the game starts itself again
#   (like closing and reopening it) and this copy closes. Unsaved progress is
#   lost either way, as with any soft reset. Without Windows' process API
#   (other systems): the old soft reset, and the session log says so.
#   Loaded first in 990_KIF.
#===============================================================================
module KIF
  def self.restart_after_soft_reset
    win = defined?(KIF::Updater::Win) && KIF::Updater.windows? ? KIF::Updater::Win : nil
    exe = win && win.exe_path
    if exe
      h, _pid = win.spawn("\"#{exe.tr('/', '\\')}\"", 0, File.dirname(exe))
      if h
        win.close(h)
        KIF.log("F12: the game started again as a new copy") if KIF.respond_to?(:log)
        (KIF::SessionLog.finish rescue nil) if defined?(KIF::SessionLog)
        win.respond_to?(:quit_now) ? win.quit_now : Kernel.exit!(0)
      end
    end
    KIF.log("F12: couldn't start a new copy of the game; soft reset as before (restart the game if anything acts up)") if KIF.respond_to?(:log)
  end
end

# before Steam adds its controller settings to it: new copies start with this (Updater Win.spawn)
$kif_start_env ||= (ENV.to_h rescue nil)
KIF.restart_after_soft_reset if $kif_scripts_loaded
$kif_scripts_loaded = true
