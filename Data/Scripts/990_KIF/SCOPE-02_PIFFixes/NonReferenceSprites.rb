#===============================================================================
# SCOPE-02 – PIF fix (2.0.9): "Include non-reference" holds only non-reference
# sprites. getNonReferenceSprites dropped the result of its reject, and the
# reject compared sprite numbers with sprite names, so the set held every
# sprite and picking it let every reference sprite in. The full list has one
# number per sprite file (alts repeat it), so each reference sprite removes one
# copy of its number: a species stays while it has a sprite that isn't one.
# Randomized tables are kept in each save, so only new randomizations change.
#===============================================================================
KIF.guard_base("025-Randomizer/randomizer gym leader edit.rb", 2963255651, "getNonReferenceSprites")

def getNonReferenceSprites(full_list, references_map = nil)
  full_list = getCustomSpeciesList(false, false) unless full_list
  references_map = map_sprites_by_reference() unless references_map
  left = Hash.new(0)
  references_map.each_value do |sprites|
    sprites.each { |name| n = getDexNumFromFilename(name.to_s); left[n] += 1 if n }
  end
  return full_list.reject { |n| left[n] > 0 && (left[n] -= 1) >= 0 }
end
