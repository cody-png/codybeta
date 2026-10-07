#===============================================================================
# C-GYM-01 – Gym Leader lines follow the team sizes (Cody, 2026-10-07)
# When "Gym Leader teams" (or the Randomizer's Leader team size) or "Your
# Pokémon in gyms" changes a Kanto Gym Leader battle, the leader's lines say
# the real numbers, in words. When both sides differ, lines name both counts;
# at six the number is dropped ("my full team", "your whole team").
# Only the shown text changes; the maps and PIF's scripts are untouched.
# With both settings on Normal nothing is changed.
#===============================================================================
module KIF
  module LeaderTeams
    NUMBER_WORDS = %w[zero one two three four five]

    @dialog_ctx = nil
    class << self
      attr_accessor :dialog_ctx
    end

    def self.utf8(s)
      return s if s.encoding == Encoding::UTF_8
      u = s.dup.force_encoding(Encoding::UTF_8)
      return u.valid_encoding? ? u : s
    end

    def self.word(n)
      return NUMBER_WORDS[n] || n.to_s
    end

    # "three Pokémon" / "my full team"
    def self.lead_phrase(l)
      return l >= 6 ? _INTL("my full team") : _INTL("{1} Pokémon", word(l))
    end

    # "two" / "your whole team"
    def self.you_phrase(p)
      return p >= 6 ? _INTL("your whole team") : word(p)
    end

    # ", and you may use two" when the counts differ
    def self.and_you(l, p)
      return "" if l == p
      return _INTL(", and you may use {1}", you_phrase(p))
    end

    #---------------------------------------------------------------------------
    # What the event battles: leader, its data and the picker's limit
    #---------------------------------------------------------------------------
    CHOOSE_RE = /PokemonSelection\.choose\(\s*\d+\s*,\s*(\d+)/
    BATTLE_RE = /pbTrainerBattle\(\s*PBTrainers::(LEADER_\w+)\s*,\s*"([^"]+)"/

    def self.script_text(list)
      parts = []
      list.each do |c|
        case c.code
        when 355, 655 then parts << c.parameters[0].to_s
        when 111 then parts << c.parameters[1].to_s if c.parameters[0] == 12
        end
      end
      return parts.join("\n")
    end

    # [leader type, name, version, picker max] or nil, per command list
    def self.event_info(list)
      @event_info ||= {}
      key = list.object_id
      return @event_info[key] if @event_info.key?(key)
      @event_info.clear if @event_info.length > 32
      text = script_text(list)
      info = nil
      ch = text[CHOOSE_RE, 1]
      bt = text.match(BATTLE_RE)
      if ch && bt
        call = text[bt.begin(0)..-1][/\A[^\n]*/].to_s.gsub(/\s+/, "")
        version = call[/,(\d+),(?:true|false)\)/, 1].to_i
        info = [bt[1].to_sym, bt[2], version, ch.to_i]
      end
      @event_info[key] = info
      return info
    end

    # [leader count, base count, your count, base picker count] or nil
    def self.counts(info)
      return nil unless info
      type, name, version, pmax = info
      data = (getTrainersDataMode.try_get(type, name, version) rescue nil) ||
             (GameData::Trainer.try_get(type, name, version) rescue nil)
      return nil unless data
      base = data.pokemon.length
      lead = base
      if randomizer_decides?
        if KIF::Rand.team_extra_setting(type) > 0
          team = ($PokemonGlobal.randomTrainersHash || {})[data.id]
          lead = [[team ? team.length : base, base].max, 6].min
        end
      else
        lead = [base + extra_count(base, cody_setting), 6].min
      end
      return [lead, base, player_max(pmax), pmax]
    rescue => e
      KIF.log("Gym Leader line counts failed: #{e.class}: #{e.message}")
      return nil
    end

    #---------------------------------------------------------------------------
    # The lines (Kanto gyms). Each: pattern => proc(l, p, match, changed_l,
    # changed_p) returning the new line or nil (unchanged)
    #---------------------------------------------------------------------------
    LINES = [
      # Brock
      [/\AIn Gym battles, you are only allowed to use as many Pokémon as the Gym Leader\.\z/,
       proc { |l, p| l != p ? _INTL("In Gym battles, the Gym Leader decides how many Pokémon each side may use.") : nil }],
      [/\ASince this is your first Gym badge, I will be using \w+ Pokémon\.\z/,
       proc { |l, p| _INTL("Since this is your first Gym badge, I will be using {1}{2}.", lead_phrase(l), and_you(l, p)) }],
      # Misty (your count only)
      [/\AI'll let you use \w+ Pokémon for the fight\. (.*)\z/,
       proc { |l, p, m, _cl, cp|
         next nil unless cp
         what = p >= 6 ? _INTL("your whole team") : _INTL("{1} Pokémon", word(p))
         _INTL("I'll let you use {1} for the fight. {2}", what, m[1])
       }],
      # Lt. Surge (Vermilion Gym, both versions)
      [/\A(I'm using|I'll be using) \w+ Pokémon for this battle, so choose the ones you're going to use!\z/,
       proc { |l, p, m|
         if l == p
           _INTL("{1} {2} for this battle, so choose the ones you're going to use!", m[1], lead_phrase(l))
         else
           _INTL("{1} {2} for this battle! You may use {3}, so choose the ones you're going to use!", m[1], lead_phrase(l), you_phrase(p))
         end
       }],
      # Erika
      [/\AI shall use \w+ Pokémon for this battle\. Choose yours!\z/,
       proc { |l, p| _INTL("I shall use {1} for this battle{2}. Choose yours!", lead_phrase(l), and_you(l, p)) }],
      # Koga
      [/\AWe'll be using \w+ Pokémon for this battle\. Choose carefully!\z/,
       proc { |l, p|
         if l == p
           both = l >= 6 ? _INTL("our full teams") : _INTL("{1} Pokémon", word(l))
           _INTL("We'll be using {1} for this battle. Choose carefully!", both)
         else
           _INTL("I'll be using {1}, and you may use {2}. Choose carefully!", lead_phrase(l), you_phrase(p))
         end
       }],
      # Sabrina
      [/\AWe'll use \w+ Pokémon for our battle\. Choose carefully\.\z/,
       proc { |l, p|
         if l == p
           both = l >= 6 ? _INTL("our full teams") : _INTL("{1} Pokémon", word(l))
           _INTL("We'll use {1} for our battle. Choose carefully.", both)
         else
           _INTL("I'll use {1}, and you may use {2}. Choose carefully.", lead_phrase(l), you_phrase(p))
         end
       }],
      # Blaine (your count only)
      [/\AI'll allow \w+ Pokémon for this fight, so choose wisely!\z/,
       proc { |l, p, _m, _cl, cp|
         next nil unless cp
         what = p >= 6 ? _INTL("your whole team") : _INTL("{1} Pokémon", word(p))
         _INTL("I'll allow {1} for this fight, so choose wisely!", what)
       }],
      # Giovanni (your count only)
      [/\AChoose your \w+ strongest Pokémon!\z/,
       proc { |l, p, _m, _cl, cp|
         next nil unless cp
         p >= 6 ? _INTL("Choose your strongest Pokémon!") : _INTL("Choose your {1} strongest Pokémon!", word(p))
       }]
    ]

    # The line as it should be shown (nil = unchanged)
    def self.rewrite_line(text, info)
      return nil unless info && text.is_a?(String)
      # Map texts load as raw bytes (RPG Maker data); read them as UTF-8
      text = KIF::LeaderTeams.utf8(text)
      # Show Text adds "\1" (wait) when another message follows; kept as is
      tail = text[/\x01*\z/]
      flat = text.sub(/\x01+\z/, "").gsub(/\s+/, " ").strip
      LINES.each do |re, fn|
        m = flat.match(re)
        next unless m
        c = counts(info)
        return nil unless c
        l, base, p, pbase = c
        return nil if l == base && p == pbase   # both settings Normal
        out = fn.call(l, p, m, l != base, p != pbase)
        return out ? out + tail : nil
      end
      return nil
    rescue => e
      KIF.log("Gym Leader line failed: #{e.class}: #{e.message}")
      return nil
    end
  end
end

class Interpreter
  alias kif_leader_dlg_execute_command execute_command unless method_defined?(:kif_leader_dlg_execute_command)

  def execute_command
    return kif_leader_dlg_execute_command unless @list
    info = KIF::LeaderTeams.event_info(@list)
    return kif_leader_dlg_execute_command unless info
    old = KIF::LeaderTeams.dialog_ctx
    KIF::LeaderTeams.dialog_ctx = info
    begin
      return kif_leader_dlg_execute_command
    ensure
      KIF::LeaderTeams.dialog_ctx = old
    end
  end
end

class Object
  alias kif_leader_dlg_pbMessage pbMessage unless method_defined?(:kif_leader_dlg_pbMessage) || private_method_defined?(:kif_leader_dlg_pbMessage)

  def pbMessage(message, *args, &block)
    info = KIF::LeaderTeams.dialog_ctx
    if info && message.is_a?(String)
      new = KIF::LeaderTeams.rewrite_line(message, info)
      message = new if new
    end
    return kif_leader_dlg_pbMessage(message, *args, &block)
  end
end
