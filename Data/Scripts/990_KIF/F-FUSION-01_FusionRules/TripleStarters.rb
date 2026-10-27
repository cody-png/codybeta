#===============================================================================
# F-FUSION-01 – Triple fusion starters (new in KIF, player request, 2026-10-26)
# Not in KIF 0.20.7 or PIF 6.8.2.
#
# PIF's Custom starter menu (common event 46 "starter set selection", from a
# 2nd save on) offers "Not fused" or "Fused". A third choice, "Triple fusion",
# lists PIF's triple fusion species (no boss parts or placeholders). The rest
# is PIF's own flow: the confirm line, switch 883 and Oak's lab (map 659),
# which gives the starter by number (SCOPE-02 TripleIds makes that work).
# The rival gets a random two-part fusion, as with "Fused".
# Debug menu > Pokémon > "Add triple fusion" gives one at a chosen level
# (PIF's Add Pokémon asks a dex number, which can't reach them).
#===============================================================================
module KIF
  module TripleStarters
    CHOICES = ["Not fused", "Fused"]
    LABEL = "Triple fusion"

    def self.list
      ret = []
      GameData::Species.each do |s|
        ret << s if s.is_triple_fusion && s.type1 != :QMARKS && s.id.to_s !~ /BOSS/
      end
      return ret
    end

    # the species symbol, or nil (B; PIF's lists do the same)
    def self.choose
      return pbChooseList(list.map { |s| [s.id_number, s.name, s.id] }, 0, nil, 1)
    end

    def self.patch(ces)
      ce = ces.is_a?(Array) && ces.compact.find { |c| c.respond_to?(:list) && c.name.to_s == "starter set selection" }
      list = ce && ce.list
      return unless list
      return if list.any? { |c| c.code == 102 && c.parameters[0] == CHOICES + [LABEL] }
      i = list.index { |c| c.code == 102 && c.parameters[0] == CHOICES }
      ind = i && list[i].indent
      j = i && (i + 1...list.length).find { |k| list[k].code == 404 && list[k].indent == ind }
      unless j
        KIF.log("Triple fusion starters: common event 46 is not the expected event; left as it is")
        return
      end
      list[i].parameters[0] = CHOICES + [LABEL]
      add = [[402, ind, [2, LABEL]],
             [355, ind + 1, ["pbSet(7,KIF::TripleStarters.choose)"]],
             [655, ind + 1, ["pbSet(212,rand(NB_POKEMON))"]],
             [655, ind + 1, ["pbSet(213,rand(NB_POKEMON))"]],
             [0, ind + 1, []]]
      list.insert(j, *add.map { |code, indent, params| RPG::EventCommand.new(code, indent, params) })
    end

    # puts PIF's two choices back (the module was turned Off)
    def self.unpatch(ces)
      ce = ces.is_a?(Array) && ces.compact.find { |c| c.respond_to?(:list) && c.name.to_s == "starter set selection" }
      list = ce && ce.list
      i = list && list.index { |c| c.code == 102 && c.parameters[0] == CHOICES + [LABEL] }
      return unless i
      ind = list[i].indent
      j = (i + 1...list.length).find { |k| list[k].code == 402 && list[k].indent == ind && list[k].parameters == [2, LABEL] }
      k = j && (j + 1...list.length).find { |n| list[n].indent <= ind }
      return unless k
      list.slice!(j...k)
      list[i].parameters[0] = CHOICES.dup
    end
  end
end

# load_data only patches while the module is on, and the common events are
# loaded at start-up: follow the module being turned on or off later
# (Options > Modules, an old save's first start)
KIF::Modules.watch(:pokemon) { |on|
  on ? KIF::TripleStarters.patch($data_common_events) : KIF::TripleStarters.unpatch($data_common_events)
} if defined?(KIF::Modules)

alias kif_ts_load_data load_data unless defined?(kif_ts_load_data)

def load_data(filename, *args)
  ret = kif_ts_load_data(filename, *args)
  if filename.is_a?(String) && filename.end_with?("CommonEvents.rxdata")
    begin
      KIF::TripleStarters.patch(ret)
    rescue => e
      KIF.log("Triple fusion starters not added: #{e.class}: #{e.message}")
    end
  end
  return ret
end

if defined?(DebugMenuCommands)
  DebugMenuCommands.register("kif_addtriple", {
    "parent"      => "pokemonmenu",
    "name"        => _INTL("Add triple fusion"),
    "description" => _INTL("Give yourself a triple fusion Pokémon at a chosen level."),
    "effect"      => proc {
      species = KIF::TripleStarters.choose
      if species
        params = ChooseNumberParams.new
        params.setRange(1, GameData::GrowthRate.max_level)
        params.setInitialValue(5)
        params.setCancelValue(0)
        level = pbMessageChooseNumber(_INTL("Set the Pokémon's level."), params)
        pbAddPokemon(species, level) if level > 0
      end
    }
  })
end
