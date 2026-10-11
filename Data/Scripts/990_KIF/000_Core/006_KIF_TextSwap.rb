#===============================================================================
# KIF::TextSwap – swap a game text for another one where _INTL looks it up
# (port framework). Used by F-BATTLE-06 (Frostbite/Drowsy/Snow texts) and
# F-BATTLE-04 (Endgame Challenge Hall of Fame text).
#
#   KIF::TextSwap.add("{1} fell asleep!") { drowsy_on ? "{1} starts to feel drowsy!" : nil }
#
# The block returns the replacement text, or nil to keep the original. The
# {1}, {2}... placeholders are filled in afterwards as usual.
#===============================================================================
module KIF
  module TextSwap
    @swaps = {}

    def self.add(text, &block)
      (@swaps[text] ||= []) << block
    end

    def self.has?(text)
      return @swaps.key?(text)
    end

    def self.swap(text)
      list = @swaps[text]
      return nil unless list
      list.each do |block|
        next if defined?(KIF::Modules) && !KIF::Modules.proc_active?(block)
        ret = (block.call rescue nil)
        return ret if ret
      end
      return nil
    end
  end
end

alias kif_ts__INTL _INTL unless defined?(kif_ts__INTL)

def _INTL(*arg)
  if arg[0].is_a?(String) && KIF::TextSwap.has?(arg[0])
    new_text = KIF::TextSwap.swap(arg[0])
    arg = [new_text] + arg[1..-1] if new_text
  end
  return kif_ts__INTL(*arg)
end
