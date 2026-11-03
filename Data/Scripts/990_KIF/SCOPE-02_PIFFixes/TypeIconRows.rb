#===============================================================================
# PIF 6.9 fix – the battle type icon rows (2026-11-02)
# 6.9's Visuals screen reads the two settings once, when the row is made
# (SpriteOptions.rb: `selected = $PokemonSystem.type_icons_opponent ? 1 : 0`
# and `proc { selected }`), so a row asked again after it was set (or after a
# preset or a Type Display change) still gave the old value. The rows read the
# setting each time instead. The same rows are in PIF's own screen and in
# KIF's Settings (Graphics > Battle).
#===============================================================================
module KIF
  module TypeIconRows
    LIVE = { "Type Icons (Enemy)" => :type_icons_opponent, "Type Icons (Player)" => :type_icons_player }

    def pbGetOptions(*args)
      opts = super
      opts.each do |o|
        next unless o.is_a?(EnumOption)
        attr = LIVE[o.name.to_s]
        o.instance_variable_set(:@getProc, proc { $PokemonSystem.send(attr) ? 1 : 0 }) if attr
      end
      return opts
    end
  end
end

SpriteOptionsScene.prepend(KIF::TypeIconRows) if defined?(SpriteOptionsScene) && !SpriteOptionsScene.ancestors.include?(KIF::TypeIconRows)
