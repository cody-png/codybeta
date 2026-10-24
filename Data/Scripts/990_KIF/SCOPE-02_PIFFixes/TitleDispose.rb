#===============================================================================
# SCOPE-02 – PIF fix: the title screen's dispose stays the title screen's
# (2026-10-22)
# PIF's IntroScreen.rb closes class GenOneStyle and then defines dispose, so
# every object gets the title screen's clean-up (fade out @sprites, dispose
# @viewport). Kanto Reloaded logged a crash loop on JoiPlay from it (the
# engine calls dispose on unrelated helpers). GenOneStyle gets that dispose
# as its own; on anything else the stray one does nothing (before, it could
# only crash on another object's missing @sprites/@viewport).
#===============================================================================
if defined?(GenOneStyle) && GenOneStyle.instance_method(:dispose).owner == Object
  kif_td_private = Object.private_method_defined?(:dispose)
  GenOneStyle.send(:define_method, :dispose, Object.instance_method(:dispose))
  GenOneStyle.send(:public, :dispose)

  class Object
    def dispose; end
  end
  Object.send(:private, :dispose) if kif_td_private
end
