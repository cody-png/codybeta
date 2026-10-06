#===============================================================================
# F-UI-09 – Intro skip and load-screen links
# Source: KIF 0.20.7 052_AddOns/IntroScreen.rb:30-50 (NoIntro.krs),
#   016_UI/013_UI_Load.rb:302-355 (Discord / Documentation entries)
#
# * Intro skip: if a file named NoIntro.krs is in the save folder
#   (%APPDATA%/<game>/, next to the saves), the game goes straight to the
#   load screen – no intro movie, no title screen.
# * Load screen: "Join Discord Server" and "Open Documentation" before
#   "Quit Game", opening KIF's links (KIF::Links below) in the browser.
#
# 6.8.2 adaptations:
#   * KIF opened links with `open URL` (a macOS command, so it did nothing on
#     Windows); 6.8.2's openUrlInBrowser works on all systems.
#   * The two entries are added to 6.8.2's load menu without copying it:
#     they are inserted before "Quit Game" and the menu's own choices are
#     handed back unchanged.
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
      return [[_INTL("Join Discord Server"), DISCORD],
              [_INTL("Open Documentation"), DOCUMENTATION]]
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

class PokemonLoad_Scene
  alias kif_ti_pbStartScene pbStartScene unless method_defined?(:kif_ti_pbStartScene)
  alias kif_ti_pbChoose pbChoose unless method_defined?(:kif_ti_pbChoose)

  def pbStartScene(commands, *args)
    @kif_links = nil
    if commands.is_a?(Array) && commands.length > 0
      at = commands.length - 1                      # before "Quit Game"
      links = KIF::Links.load_menu
      commands.insert(at, *links.map { |l| l[0] })
      @kif_links = [at, links]
    end
    return kif_ti_pbStartScene(commands, *args)
  end

  # The base menu keeps its own numbering: our entries are handled here
  def pbChoose(commands)
    loop do
      ret = kif_ti_pbChoose(commands)
      return ret unless @kif_links && ret.is_a?(Integer)
      at, links = @kif_links
      return ret if ret < at
      return ret - links.length if ret >= at + links.length
      pbPlayDecisionSE
      openUrlInBrowser(links[ret - at][1])
    end
  end
end
