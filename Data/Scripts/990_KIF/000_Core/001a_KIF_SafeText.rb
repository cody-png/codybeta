#===============================================================================
# KIF.safe_text: text from another game or from a mod, safe to put in a PIF
# message or draw. KIF::Net.safe_text (multiplayer) calls it too.
#===============================================================================
module KIF
  # No backslash (message codes such as \wtnp[99999] or \v[1]), no "<" (a tag such
  # as <img=file> loads a file; one that is not a picture crashes the game) and
  # no ">" except in "->", no control characters (a new line stays) and no
  # text-direction characters.
  UNSAFE_TEXT = /[\\<\x00-\x09\x0b-\x1f\x7f\u0080-\u009f\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069]|(?<!-)>/

  def self.safe_text(s, max = 200)
    # "{2}" in a name would be filled in by _INTL with its next argument: the brace goes
    return s.to_s.dup.force_encoding("UTF-8").scrub("").gsub("\r\n", "\n").gsub(UNSAFE_TEXT, "").gsub(/\{(?=\d)/, "(")[0, max]
  end
end
