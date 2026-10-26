#===============================================================================
# SCOPE-02 – PIF fix: the title screen's dispose stays the title screen's
# (2026-10-22)
# PIF's IntroScreen.rb closes class GenOneStyle and then defines dispose, so
# every object gets the title screen's clean-up (fade out @sprites, dispose
# @viewport). Kanto Reloaded logged a crash loop on JoiPlay from it (the
# engine calls dispose on unrelated helpers). GenOneStyle gets that dispose
# as its own; on anything else the stray one does nothing (before, it could
# only crash on another object's missing @sprites/@viewport).
# F12 on phones, Linux and macOS runs IntroScreen.rb again in the same game,
# which puts its dispose back on Object: so the test is whether Object's
# dispose is still the do-nothing one made here, not who owns GenOneStyle's.
#===============================================================================
if defined?(GenOneStyle) && (kif_td = Object.instance_method(:dispose)).owner == Object && kif_td != $kif_td_noop
  kif_td_private = Object.private_method_defined?(:dispose)
  GenOneStyle.send(:define_method, :dispose, kif_td)
  GenOneStyle.send(:public, :dispose)

  class Object
    def dispose; end
  end
  Object.send(:private, :dispose) if kif_td_private
  $kif_td_noop = Object.instance_method(:dispose)
end
