#===============================================================================
# SCOPE-02 – PIF fix: JSON.parse no longer runs the text as code (2026-10-22)
# PIF's JSON.parse (001_Technical/002_Files/003_HTTP_Utilities.rb) is
# eval(str). A JSON string may hold #{...}, which eval runs, and PIF parses
# text other players supply with it: a friend's secret base downloaded by
# trainer ID, mystery gift codes, a shared sprite_preferences.json. A crafted
# one could run any program on the player's PC.
# Now a real JSON parser (KIF's MiniJSON) reads it. Keys come back as symbols
# and null as nil, as eval of PIF's own JSON gave them, so PIF's callers
# (json[:secretUUID], gift[:pokemon]...) read the same values. Text that
# isn't JSON gives nil instead of whatever eval made of it.
#===============================================================================
module JSON
  module_function

  def parse(str)
    return nil if str.nil? || str.to_s.strip.empty?
    return nil unless defined?(KIF::Mods::MiniJSON)
    return kif_symbolize(KIF::Mods::MiniJSON.parse(str.to_s))
  end

  def kif_symbolize(v)
    case v
    when Hash  then v.each_with_object({}) { |(k, x), h| h[k.to_s.to_sym] = kif_symbolize(x) }
    when Array then v.map { |x| kif_symbolize(x) }
    else v
    end
  end
end
