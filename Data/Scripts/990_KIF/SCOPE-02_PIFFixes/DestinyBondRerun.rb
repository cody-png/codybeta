#===============================================================================
# SCOPE-02 – PIF fix: Destiny Bond after a second run of the scripts
# PIF 6.8.2's Clauses script (011_Battle/006_Other battle types/
# 009_PokeBattle_Clauses.rb:233) takes `alias __clauses__pbFailsAgainstTarget?`
# in PokeBattle_Move_0E7, which only inherits that method. When every script
# runs again in one process (F12 on JoiPlay, Linux and macOS), the alias takes
# the Clauses wrapper itself and Destiny Bond raises "stack level too deep".
# The alias goes back to the inherited method then; after a first run it
# already is, so nothing changes. Always on (a bug fix). Date: 2026-10-25.
#===============================================================================
class PokeBattle_Move_0E7
  if method_defined?(:__clauses__pbFailsAgainstTarget?) &&
     instance_method(:__clauses__pbFailsAgainstTarget?).source_location ==
     instance_method(:pbFailsAgainstTarget?).source_location
    define_method(:__clauses__pbFailsAgainstTarget?, superclass.instance_method(:pbFailsAgainstTarget?))
  end
end
