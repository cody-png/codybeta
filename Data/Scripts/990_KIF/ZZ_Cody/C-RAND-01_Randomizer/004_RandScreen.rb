#===============================================================================
# C-RAND-01 – the Randomizer screen (replaces PIF's RandomizerOptionsScene,
# which PIF's events open when a randomized save is made). Also reachable from
# Cody Settings on saves started as randomized saves. Built from the game's
# own option windows, so it follows the player's frame and dark mode.
#===============================================================================
module KIF
  module Rand
    # Button whose name is worked out when drawn ("Pokémon (On)")
    class DynButton < ButtonOption
      def initialize(name_proc, press, description = "")
        super("", press, description)
        @name_proc = name_proc
      end

      def name
        return @name_proc.call
      end
    end

    def self.on_off(on)
      return on ? _INTL("On") : _INTL("Off")
    end

    def self.page_state(page)
      case page
      when :pokemon then return on_off(pokemon_parts_on?)
      when :trainers then return on_off(get(:trainers) == 1)
      when :gyms then return on_off(get(:gyms) == 1)
      when :items then return on_off(sw(SWITCH_RANDOM_ITEMS_GENERAL))
      end
      return ""
    end

    def self.enum(key, name, values, descs)
      return EnumOption.new(name, values,
                            proc { KIF::Rand.get(key) },
                            proc { |v| KIF::Rand.set(key, v) }, descs)
    end

    def self.onoff(key, name, desc_off, desc_on)
      return enum(key, name, [_INTL("Off"), _INTL("On")], [desc_off, desc_on])
    end

    # 3-digit number (each digit 0-9) instead of a slider (Cody)
    def self.slider(key, name, desc)
      return DynButton.new(proc { sprintf("%s: %03d", name, KIF::Rand.get(key)) },
                           proc {
                             params = ChooseNumberParams.new
                             params.setRange(0, 999)
                             params.setMaxDigits(3)
                             params.setInitialValue(KIF::Rand.get(key))
                             params.setCancelValue(KIF::Rand.get(key))
                             KIF::Rand.digit_wrap = true
                             begin
                               v = pbMessageChooseNumber(_INTL("{1} (0-999)? Up/Down: digit, Left/Right: move.", name), params)
                             ensure
                               KIF::Rand.digit_wrap = false
                             end
                             KIF::Rand.set(key, v)
                           }, desc)
    end

    def self.open_page(title, desc, color, &builder)
      pbFadeOutIn {
        scene = KifRandPageScene.new(title, desc, color, builder)
        PokemonOptionScreen.new(scene).pbStartScreen
      }
    end

    GREEN = [Color.new(70, 170, 40), Color.new(40, 100, 20)]

    def self.page_pokemon
      open_page(_INTL("Randomizer: Pokémon"), _INTL("Which Pokémon are randomized, and how."), GREEN) {
        [
          enum(:wild_mode, _INTL("Wild encounters"),
               [_INTL("Off"), _INTL("Swap"), _INTL("Route"), _INTL("Dynamic")],
               [_INTL("Wild Pokémon are not randomized."),
                _INTL("Each species becomes one other species everywhere."),
                _INTL("Every route rolls its own Pokémon."),
                _INTL("Every encounter is any Pokémon, rolled on the spot.")]),
          enum(:starters, _INTL("Starters"), [_INTL("Off"), _INTL("1st"), _INTL("Any")],
               [_INTL("The starters are not randomized."),
                _INTL("The starters are random first-stage Pokémon."),
                _INTL("The starters can be any Pokémon.")]),
          onoff(:statics, _INTL("Static encounters"),
                _INTL("Overworld Pokémon (legendaries included) are not randomized."),
                _INTL("Overworld Pokémon (legendaries included) are randomized.")),
          onoff(:gifts, _INTL("Gift Pokémon"),
                _INTL("Pokémon given to you are not randomized."),
                _INTL("Pokémon given to you are randomized.")),
          onoff(:trades, _INTL("Trades"),
                _INTL("Pokémon from in-game trades are not randomized."),
                _INTL("Pokémon from in-game trades are randomized.")),
          slider(:wild_bst, _INTL("Strength range"),
                 _INTL("How close in base stat total a replacement must be. 999 = anything.")),
          onoff(:wild_legend, _INTL("Legendaries"),
                _INTL("Only legendaries become legendaries."),
                _INTL("Any Pokémon can become a legendary.")),
          onoff(:wild_custom, _INTL("Custom sprites only"),
                _INTL("Fusions can use auto-generated sprites."),
                _INTL("Fusions only use ones with a custom sprite.")),
          onoff(:fuse_all, _INTL("Fuse everything"),
                _INTL("Wild Pokémon can be unfused."),
                _INTL("All wild Pokémon are already fused."))
        ]
      }
    end

    def self.page_trainers
      open_page(_INTL("Randomizer: Trainers"), _INTL("Trainer teams."), nil) {
        [
          onoff(:trainers, _INTL("Trainers"),
                _INTL("Trainer teams are not randomized."),
                _INTL("Trainer teams are randomized.")),
          slider(:trainer_bst, _INTL("Strength range"),
                 _INTL("How close in base stat total a replacement must be. 999 = anything.")),
          onoff(:trainer_custom, _INTL("Custom sprites only"),
                _INTL("Trainer teams can use auto-generated sprites."),
                _INTL("Trainer teams only use Pokémon with a custom sprite."))
        ]
      }
    end

    def self.page_gyms
      open_page(_INTL("Randomizer: Gyms"), _INTL("Gym trainers and leaders (needs Trainers on)."), nil) {
        [
          onoff(:gyms, _INTL("Gym trainers"),
                _INTL("Gym teams are randomized like other trainers."),
                _INTL("Gym teams stick to the gym's type.")),
          onoff(:gym_custom, _INTL("Custom sprites only"),
                _INTL("Gym teams can use auto-generated sprites."),
                _INTL("Gym teams only use Pokémon with a custom sprite.")),
          onoff(:gym_types, _INTL("Gym types"),
                _INTL("Gyms keep their usual types."),
                _INTL("Gym types are shuffled.")),
          onoff(:gym_each, _INTL("Rerandomize each battle"),
                _INTL("Gym teams stay the same each try."),
                _INTL("Gym teams change on every try."))
        ]
      }
    end

    def self.page_items
      open_page(_INTL("Randomizer: Items"), _INTL("Items and TMs."), nil) {
        [
          onoff(:found_items, _INTL("Found items"), _INTL("Items on the ground are normal."), _INTL("Items on the ground are randomized.")),
          onoff(:found_tms, _INTL("Found TMs"), _INTL("TMs on the ground are normal."), _INTL("TMs on the ground are randomized.")),
          onoff(:given_items, _INTL("Given items"), _INTL("Items from NPCs are normal."), _INTL("Items from NPCs are randomized (may break some quests).")),
          onoff(:given_tms, _INTL("Given TMs"), _INTL("TMs from NPCs are normal."), _INTL("TMs from NPCs are randomized.")),
          onoff(:shop_items, _INTL("Shop items"), _INTL("Shops sell their usual items."), _INTL("Shop stock is randomized.")),
          onoff(:held_items, _INTL("Trainer held items"), _INTL("Trainers hold their usual items."), _INTL("Trainers hold random items."))
        ]
      }
    end

    #---------------------------------------------------------------------------
    def self.seed_menu
      cmds = [_INTL("New random seed"), _INTL("Type a seed"), _INTL("Copy seed"), _INTL("Cancel")]
      case pbMessage(_INTL("Seed: {1}", format_seed), cmds, cmds.length)
      when 0
        self.seed = new_seed
        pbMessage(_INTL("New seed: {1}", format_seed))
      when 1
        text = pbMessageFreeText(_INTL("Seed (8 letters/numbers):"), format_seed, false, 9)
        s = parse_seed(text)
        if s
          self.seed = s
        elsif text && !text.strip.empty?
          pbMessage(_INTL("A seed is 8 letters and numbers (no I, O, 0 or 1)."))
        end
      when 2
        Input.clipboard = format_seed rescue nil
        pbMessage(_INTL("Seed copied."))
      end
    end

    def self.page_presets
      open_page(_INTL("Presets & sharing"), _INTL("Share or keep your randomizer settings."), nil) {
        [
          ButtonOption.new(_INTL("Copy settings code"), proc {
            begin
              Input.clipboard = KIF::Rand.settings_code
              pbMessage(_INTL("Copied: {1}", KIF::Rand.settings_code))
            rescue
              pbMessage(_INTL("Couldn't copy. The code is: {1}", KIF::Rand.settings_code))
            end
          }, _INTL("Copies the seed and every setting as one line.")),
          ButtonOption.new(_INTL("Paste settings code"), proc {
            text = (Input.clipboard rescue nil).to_s.strip
            res = KIF::Rand.parse_code(text)
            if !res
              pbMessage(_INTL("The clipboard doesn't hold a settings code (it starts with {1}).", KIF::Rand::CODE_PREFIX))
            elsif pbConfirmMessage(_INTL("Load these settings? Seed {1}.", KIF::Rand.format_seed(res[0])))
              KIF::Rand.apply_code(text)
              pbMessage(_INTL("Loaded. Use Randomize now for them to take effect."))
            end
          }, _INTL("Loads a settings code copied from someone else.")),
          ButtonOption.new(_INTL("Save as preset"), proc {
            name = pbMessageFreeText(_INTL("Preset name:"), "", false, 30)
            if name && !name.strip.empty?
              ok = KIF::Rand.save_preset(name)
              pbMessage(ok ? _INTL("Saved to the {1} folder.", KIF::Rand::PRESET_DIR) : _INTL("Couldn't save that preset."))
            end
          }, _INTL("Saves these settings as a file you can share.")),
          ButtonOption.new(_INTL("Load preset"), proc {
            names = KIF::Rand.preset_names
            if names.empty?
              pbMessage(_INTL("No presets yet. They're kept in the {1} folder.", KIF::Rand::PRESET_DIR))
            else
              i = pbMessage(_INTL("Which preset?"), names + [_INTL("Cancel")], names.length + 1)
              if i >= 0 && i < names.length
                ok = KIF::Rand.load_preset(names[i])
                pbMessage(ok ? _INTL("Loaded. Use Randomize now for it to take effect.") : _INTL("That preset couldn't be read."))
              end
            end
          }, _INTL("Loads a preset from the {1} folder.", KIF::Rand::PRESET_DIR))
        ]
      }
    end

    #---------------------------------------------------------------------------
    # Randomize now: the same steps as Common Event 28, on the seed
    #---------------------------------------------------------------------------
    def self.randomize_now
      sync_masters
      setsw(SWITCH_RANDOMIZED_AT_LEAST_ONCE, true)
      Kernel.initRandomTypeArray
      if pokemon_parts_on?
        data[:dex_ok] = false
        Kernel.pbShuffleDex($game_variables[VAR_RANDOMIZER_WILD_POKE_BST])
        setsw(669, true)
        Kernel.randomizeWildPokemonByRoute if sw(SWITCH_RANDOM_WILD_AREA)
      end
      if sw(SWITCH_RANDOM_TRAINERS)
        sw(600) ? Kernel.pbShuffleTrainersCustom : Kernel.pbShuffleTrainers
        $PokemonGlobal.randomGymTrainersHash = {}
      end
      $PokemonGlobal.randomItemsHash = nil
      $PokemonGlobal.randomTMsHash = nil
      pbShuffleItems if sw(SWITCH_RANDOM_ITEMS) || sw(SWITCH_RANDOM_SHOP_ITEMS)
      pbShuffleTMs if sw(SWITCH_RANDOM_TMS)
      KIF::Rand.progress_done
      write_log
    end
  end
end

module KIF
  module Rand
    @digit_wrap = false
    class << self
      attr_accessor :digit_wrap
    end
  end
end

# Strength range picker: each digit wraps on its own (0 down -> 9, 9 up -> 0)
# without touching the other digits (PIF's number box carries/borrows).
# Only while the randomizer's picker is open.
class Window_InputNumberPokemon
  alias kif_rand_update update unless method_defined?(:kif_rand_update)

  def update
    return kif_rand_update unless KIF::Rand.digit_wrap && self.active
    return kif_rand_update unless Input.repeat?(Input::UP) || Input.repeat?(Input::DOWN)
    digits = @digits_max + (@sign ? 1 : 0)
    return kif_rand_update if @index == 0 && @sign
    SpriteWindow_Base.instance_method(:update).bind(self).call
    place = 10 ** (digits - 1 - @index)
    d = (@number / place) % 10
    nd = Input.repeat?(Input::UP) ? (d + 1) % 10 : (d + 9) % 10
    @number += (nd - d) * place
    pbPlayCursorSE
    refresh
    @frame = (@frame + 1) % 30
  end
end

class KifRandPageScene < PokemonOption_Scene
  def initialize(title, desc, colors, builder)
    super()
    @kif_title = title
    @kif_desc = desc
    @kif_colors = colors
    @kif_builder = builder
  end

  def initUIElements
    super
    @sprites["title"].text = @kif_title
  end

  def getDefaultDescription
    return @kif_desc
  end

  def pbStartScene(inloadscreen = false)
    super
    if @kif_colors
      @sprites["option"].nameBaseColor = @kif_colors[0]
      @sprites["option"].nameShadowColor = @kif_colors[1]
    else
      @sprites["option"].nameBaseColor = MessageConfig::BLUE_TEXT_MAIN_COLOR
      @sprites["option"].nameShadowColor = MessageConfig::BLUE_TEXT_SHADOW_COLOR
    end
    @sprites["option"].refresh
  end

  def pbGetOptions(inloadscreen = false)
    return @kif_builder.call
  end

  def pbEndScene
    super
    KIF::Rand.sync_masters
  end
end

class RandomizerOptionsScene < PokemonOption_Scene
  def initialize
    super
    $game_switches[SWITCH_RANDOMIZED_AT_LEAST_ONCE] = true
    KIF::Rand.seed
  end

  def initUIElements
    super
    @sprites["title"].text = _INTL("Randomizer")
  end

  def getDefaultDescription
    return _INTL("Same seed + same settings = the same game.")
  end

  def pbStartScene(inloadscreen = false)
    super
    @sprites["option"].nameBaseColor = MessageConfig::BLUE_TEXT_MAIN_COLOR
    @sprites["option"].nameShadowColor = MessageConfig::BLUE_TEXT_SHADOW_COLOR
    @sprites["option"].refresh
    @sprites["textbox"].text = getDefaultDescription
  end

  def kif_refresh
    @sprites["option"].refresh if @sprites && @sprites["option"]
  end

  def pbGetOptions(inloadscreen = false)
    r = KIF::Rand
    options = []
    options << r::DynButton.new(proc { _INTL("Seed: {1}", r.format_seed) },
                                proc { r.seed_menu; kif_refresh },
                                _INTL("Same seed + same settings = the same game."))
    options << ButtonOption.new(_INTL("Presets & sharing"), proc { r.page_presets; kif_refresh },
                                _INTL("Copy, paste, save or load settings."))
    options << EnumOption.new(_INTL("Spoiler log"), [_INTL("Off"), _INTL("On")],
                              proc { r.log_on? ? 1 : 0 },
                              proc { |v| r.data[:log] = (v == 1) },
                              [_INTL("No spoiler log is written."),
                               _INTL("Writes \"Randomizer Log - <seed>.txt\" in the Randomizer/Logs folder.")])
    options << ButtonOption.new(_INTL("View spoiler log"), proc { r.view_log },
                                _INTL("Shows everything that was randomized (asks first)."))
    [[:pokemon, _INTL("Pokémon"), _INTL("Wild encounters, starters, statics, gifts and trades.")],
     [:trainers, _INTL("Trainers"), _INTL("Trainer teams.")],
     [:gyms, _INTL("Gyms"), _INTL("Gym trainers, leaders and gym types.")],
     [:items, _INTL("Items"), _INTL("Found, given and shop items, TMs.")]].each do |page, label, desc|
      options << r::DynButton.new(proc { "#{label} (#{r.page_state(page)})" },
                                  proc { r.send("page_#{page}"); kif_refresh }, desc)
    end
    unless $game_switches[SWITCH_DURING_INTRO]
      options << ButtonOption.new(_INTL("Randomize now"), proc {
        if pbConfirmMessage(_INTL("Randomize with seed {1}? Your current randomized Pokémon, trainers and items are replaced. Your party and boxes stay.", r.format_seed))
          r.randomize_now
          pbMessage(_INTL("Done!"))
        end
      }, _INTL("Applies these settings now."))
    end
    return options
  end

  def pbEndScene
    super
    KIF::Rand.sync_masters
    KIF::Rand.screen_closed! if $game_switches[SWITCH_DURING_INTRO]
  end
end

#-------------------------------------------------------------------------------
# Cody Settings button (randomized saves only)
#-------------------------------------------------------------------------------
class CodyOptionsScene < KifOptionsScene
  alias kif_rand_pbGetOptions pbGetOptions unless method_defined?(:kif_rand_pbGetOptions)

  def pbGetOptions(inloadscreen = false)
    options = kif_rand_pbGetOptions(inloadscreen)
    if !inloadscreen && KIF::Rand.available?
      options << ButtonOption.new(_INTL("Randomizer"), proc {
        pbFadeOutIn {
          PokemonOptionScreen.new(RandomizerOptionsScene.new).pbStartScreen
        }
      }, _INTL("Seed, presets, spoiler log and every randomizer setting."))
    end
    return options
  end
end
