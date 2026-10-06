#===============================================================================
# F-UI-09 – Intro skip and load-screen links
# Source: KIF 0.20.7 052_AddOns/IntroScreen.rb:30-50 (NoIntro.krs),
#   016_UI/013_UI_Load.rb:302-355 (Discord / Documentation entries)
#
# * Intro skip: if a file named NoIntro.krs is in the save folder
#   (%APPDATA%/<game>/, next to the saves), the game goes straight to the
#   load screen – no intro movie, no title screen.
# * Load screen: KIF's Discord and documentation links ("KIF Discord",
#   "KIF Documentation"; KIF called them "Join Discord Server" / "Open
#   Documentation" – renamed because 6.8.2 already lists PIF's "Discord").
#
# 6.8.2 adaptations:
#   * KIF opened links with `open URL` (a macOS command, so it did nothing on
#     Windows); 6.8.2's openUrlInBrowser works on all systems.
#   * The links go into 6.8.2's own link list (Settings::MAIN_MENU_LINKS),
#     which its load menu shows after Options and opens itself. (First
#     version wrapped the old 013_UI_Load menu, which 6.8.2's MultiSaves
#     load menu replaces – crash fixed 2026-10-05.)
#   * The random custom fusions on the title screen are 6.8.2's own now
#     (getRandomCustomFusionForIntro), nothing to port. KIF's "Optidons" typo
#     is not ported.
#===============================================================================
module KIF
  module Links
    DISCORD = "https://discord.gg/UFxQkUZeyE"
    DOCUMENTATION = "https://docs.google.com/document/d/1O6pKKL62dbLcapO0c2zDG2UI-eN6uatYlt_0GSk1dbE"

    # [label, url]
    def self.load_menu
      return [["KIF Discord", DISCORD], ["KIF Documentation", DOCUMENTATION]]
    end

    def self.no_intro?
      return File.exist?(File.join(RTP.getSaveFolder, "NoIntro.krs"))
    rescue
      return false
    end
  end
end

class Scene_Intro
  alias kif_ti_main main unless method_defined?(:kif_ti_main)

  def main
    return kif_ti_main unless KIF::Links.no_intro?
    Graphics.transition(0)
    updateCreditsFile if defined?(updateCreditsFile) && !File.exist?(Settings::CREDITS_FILE_PATH)
    sscene = PokemonLoad_Scene.new
    sscreen = PokemonLoadScreen.new(sscene)
    sscreen.pbStartLoadScreen
  end
end

# 6.8.2's load menu (MultiSaves.rb:532) already lists Settings::MAIN_MENU_LINKS
# (PIF's Discord / FAQ / Wiki) and opens them; KIF's two links are added there.
KIF::Links.load_menu.each do |label, url|
  Settings::MAIN_MENU_LINKS[label] = url unless Settings::MAIN_MENU_LINKS.value?(url)
end if defined?(Settings::MAIN_MENU_LINKS) && Settings::MAIN_MENU_LINKS.is_a?(Hash) && !Settings::MAIN_MENU_LINKS.frozen?
