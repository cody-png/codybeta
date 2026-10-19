#===============================================================================
# KIF::AbilityText – one place that answers an ability's display name and
# description (2026-10-18). The Summary, battle splashes and messages, Battle
# Info and the randomizer's lists all read GameData::Ability#name /
# #description, so that is where the answer is given.
#
#   KIF::AbilityText.register("My Mod", :SOLIDROCK, name: "Solid Rock",
#                             description: "Halves 4x hits.", priority: 10)
#   KIF::AbilityText.set_priority("My Mod", -> { my_setting_on? ? 30 : 5 })
#
# The highest priority wins (a tie: the later registration). A priority is a
# number or a proc asked on every lookup, so it can follow a setting. A
# registration without a name (or description) leaves that text to the next
# one down, and in the end to the game. Nothing registered: the game's text,
# exactly as before.
#
# Kept apart from KIF::TextSwap: TextSwap swaps whole _INTL message texts and
# its first answer wins; ability names don't go through _INTL, and here the
# answer is picked by ability and by priority.
#
# The wrapper is put on after every mod has loaded (KIF::Mods.load_all) and
# again after each data load, so it sits outside mods that alias #name /
# #description themselves: their text is what the game shows when nothing is
# registered.
#===============================================================================
module KIF
  module AbilityText
    @entries = {}      # ability id => [{ :owner, :name, :description, :priority, :seq }]
    @seq = 0

    def self.register(owner, ability, name: nil, description: nil, priority: 0)
      id = ability.to_s.upcase.to_sym
      list = (@entries[id] ||= [])
      list.reject! { |e| e[:owner] == owner }
      list << { :owner => owner, :name => name, :description => description,
                :priority => priority, :seq => (@seq += 1) }
      return nil
    end

    # every registration of owner; a number or a proc
    def self.set_priority(owner, priority)
      @entries.each_value { |l| l.each { |e| e[:priority] = priority if e[:owner] == owner } }
      return nil
    end

    def self.unregister(owner, ability = nil)
      ids = ability ? [ability.to_s.upcase.to_sym] : @entries.keys
      ids.each { |id| (@entries[id] || []).reject! { |e| e[:owner] == owner } }
      @entries.delete_if { |_, l| l.empty? }
      return nil
    end

    def self.any?; return !@entries.empty?; end

    def self.name(ability);        return pick(ability, :name); end
    def self.description(ability); return pick(ability, :description); end

    def self.priority_of(e)
      p = e[:priority]
      return (p.respond_to?(:call) ? p.call : p).to_f
    rescue StandardError => err
      KIF.log("AbilityText: priority of #{e[:owner]} failed (#{err.class}: #{err.message})") if defined?(KIF.log)
      return 0.0
    end

    # the winning registered text, or nil (then the game's own)
    def self.pick(ability, field)
      list = @entries[ability.to_s.upcase.to_sym]
      return nil unless list
      best = nil; best_key = nil
      list.each do |e|
        next if e[field].nil?
        key = [priority_of(e), e[:seq]]
        (best = e; best_key = key) if best_key.nil? || (key <=> best_key) > 0
      end
      return best ? best[field].to_s : nil
    end

    # Puts KIF's answer outside #name / #description. Safe to call again: it
    # wraps again only when something (a mod) has wrapped them since.
    @wrapped ||= {}
    @n ||= 0
    def self.install
      [:name, :description].each do |m|
        cur = GameData::Ability.instance_method(m)
        next if @wrapped[m] && cur == @wrapped[m]
        inner = :"kif_at_#{m}_#{@n += 1}"
        GameData::Ability.send(:alias_method, inner, m)
        GameData::Ability.send(:define_method, m) do
          t = KIF::AbilityText.any? ? KIF::AbilityText.pick(@id, m) : nil
          t || send(inner)
        end
        @wrapped[m] = GameData::Ability.instance_method(m)
      end
      return nil
    end
  end
end

KIF::DataLoad.after_load_all("Ability text (KIF::AbilityText)") { KIF::AbilityText.install } if defined?(KIF::DataLoad)
