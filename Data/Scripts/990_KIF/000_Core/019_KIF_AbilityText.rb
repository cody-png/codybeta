#===============================================================================
# KIF::AbilityText / KIF::MoveText – one place that answers an ability's or a
# move's display name and description (abilities 2026-10-18, moves
# 2026-10-19). The Summary, battle splashes and messages, Battle Info, the
# move screens and the randomizer's lists all read GameData::Ability /
# GameData::Move #name and #description, so that is where the answer is given.
#
#   KIF::AbilityText.register("My Mod", :SOLIDROCK, name: "Solid Rock",
#                             description: "Halves 4x hits.", priority: 10)
#   KIF::MoveText.register("My Mod", :DETECT, description: "...", priority: 10)
#   KIF::AbilityText.set_priority("My Mod", -> { my_setting_on? ? 30 : 5 })
#
# The highest priority wins (a tie: the later registration). A priority is a
# number or a proc asked on every lookup, so it can follow a setting. A
# registration without a name (or description) leaves that text to the next
# one down, and in the end to the game. Nothing registered: the game's text,
# exactly as before.
#
# Kept apart from KIF::TextSwap: TextSwap swaps whole _INTL message texts and
# its first answer wins; these names don't go through _INTL, and here the
# answer is picked by id and by priority.
#
# The wrapper is put on after every mod has loaded (KIF::Mods.load_all) and
# again after each data load, so it sits outside mods that alias #name /
# #description themselves: their text is what the game shows when nothing is
# registered.
#===============================================================================
module KIF
  # what AbilityText and MoveText share; each sets data_class and PREFIX
  module TextRegistry
    def register(owner, id, name: nil, description: nil, priority: 0)
      key = id.to_s.upcase.to_sym
      list = (@entries[key] ||= [])
      list.reject! { |e| e[:owner] == owner }
      list << { :owner => owner, :name => name, :description => description,
                :priority => priority, :seq => (@seq += 1) }
      return nil
    end

    # every registration of owner; a number or a proc
    def set_priority(owner, priority)
      @entries.each_value { |l| l.each { |e| e[:priority] = priority if e[:owner] == owner } }
      return nil
    end

    def unregister(owner, id = nil)
      keys = id ? [id.to_s.upcase.to_sym] : @entries.keys
      keys.each { |k| (@entries[k] || []).reject! { |e| e[:owner] == owner } }
      @entries.delete_if { |_, l| l.empty? }
      return nil
    end

    def any?; return !@entries.empty?; end

    def name(id);        return pick(id, :name); end
    def description(id); return pick(id, :description); end

    def priority_of(e)
      p = e[:priority]
      return (p.respond_to?(:call) ? p.call : p).to_f
    rescue StandardError => err
      KIF.log("#{self::PREFIX}: priority of #{e[:owner]} failed (#{err.class}: #{err.message})") if defined?(KIF.log)
      return 0.0
    end

    # the winning registered text, or nil (then the game's own)
    def pick(id, field)
      list = @entries[id.to_s.upcase.to_sym]
      return nil unless list
      best = nil; best_key = nil
      list.each do |e|
        next if e[field].nil?
        key = [priority_of(e), e[:seq]]
        (best = e; best_key = key) if best_key.nil? || (key <=> best_key) > 0
      end
      return best ? best[field].to_s : nil
    end

    # Puts this answer outside #name / #description. Safe to call again: it
    # wraps again only when something (a mod) has wrapped them since.
    def install
      reg = self
      klass = data_class
      [:name, :description].each do |m|
        cur = klass.instance_method(m)
        next if @wrapped[m] && cur == @wrapped[m]
        inner = :"#{self::PREFIX}_#{m}_#{@n += 1}"
        klass.send(:alias_method, inner, m)
        klass.send(:define_method, m) do
          t = reg.any? ? reg.pick(@id, m) : nil
          t || send(inner)
        end
        @wrapped[m] = klass.instance_method(m)
      end
      return nil
    end
  end

  module AbilityText
    extend TextRegistry
    PREFIX = "kif_at"
    @entries = {}      # ability id => [{ :owner, :name, :description, :priority, :seq }]
    @seq = 0
    @wrapped ||= {}
    @n ||= 0
    def self.data_class; return GameData::Ability; end
  end

  module MoveText
    extend TextRegistry
    PREFIX = "kif_mt"
    @entries = {}      # move id => [...]
    @seq = 0
    @wrapped ||= {}
    @n ||= 0
    def self.data_class; return GameData::Move; end
  end
end

KIF::DataLoad.after_load_all("Ability and move text (KIF::AbilityText, KIF::MoveText)") {
  KIF::AbilityText.install
  KIF::MoveText.install
} if defined?(KIF::DataLoad)
