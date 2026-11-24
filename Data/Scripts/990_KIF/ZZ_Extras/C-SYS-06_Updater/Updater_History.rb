#===============================================================================
# C-SYS-06 – Update history (2026-10-26)
# Data/KIF/changelog.txt holds every KIF version's notes, newest first, each
# under its "KIF 1.2.5" line: an OVERVIEW part (the short notes, the same
# lines update_notes.txt gives What's new) and a FULL NOTES part (every
# change a player can notice; a line without "- " is a heading).
# Options > System > Update history, and "All updates" after an update, list
# the versions; each opens its Overview or Full notes in a reader. The kit's
# tools/gen_changelog.rb makes the repo's CHANGELOG.md (GitHub) from the
# same file.
#===============================================================================
module KIF
  module Updater
    CHANGELOG = "Data/KIF/changelog.txt"
    CHANGELOG_PARTS = { "OVERVIEW" => :overview, "FULL NOTES" => :full }

    # [{ :version, :overview => [lines], :full => [lines] }, ...] in the file's order
    def self.changelog(text = nil)
      text ||= (File.binread(File.join(root, CHANGELOG)) rescue "")
      sections = []
      part = :overview
      text.to_s.dup.force_encoding("UTF-8").split(/\r?\n/).each do |l|
        l = l.strip
        if (v = l[NOTES_HEAD, 1])
          sections << { :version => v, :overview => [], :full => [] }
          part = :overview
        elsif CHANGELOG_PARTS[l]
          part = CHANGELOG_PARTS[l]
        elsif !l.empty? && !sections.empty?
          sections.last[part] << l
        end
      end
      return sections
    end

    def self.history
      secs = changelog
      if secs.empty?
        pbMessage(_INTL("No notes for this version."))
        return
      end
      names = secs.map { |s| "KIF #{s[:version]}" }
      pick = 0
      loop do
        pick = pbMessage(_INTL("You have KIF {1}. Which version's notes?", current_version),
                         names + [_INTL("Close")], names.length + 1, nil, pick)
        break if pick < 0 || pick >= secs.length
        s = secs[pick]
        loop do
          cmd = pbMessage(_INTL("KIF {1}", s[:version]), [_INTL("Overview"), _INTL("Full notes"), _INTL("Back")], 3)
          break unless cmd == 0 || cmd == 1
          if cmd == 0
            show_text(_INTL("KIF {1}: Overview", s[:version]), s[:overview])
          else
            show_text(_INTL("KIF {1}: Full notes", s[:version]), s[:full])
          end
        end
      end
    end

    # Word-wrapped rows; a list line's ("- ", "1. ") later rows are indented.
    # gaps: a heading (any other line) gets an empty row above it; without
    # gaps the lines bring their own empty ones (mod descriptions). A word
    # wider than the window (a long URL) goes on across rows.
    def self.text_rows(bmp, lines, width, gaps = true)
      rows = []
      lines.each do |line|
        item = line[/\A *(?:- |\d+[.)] )/]
        pad = item ? " " * item.length : ""
        rows << "" if gaps && !item && !rows.empty?
        cur = line[/\A */]   # a nested list keeps its indent
        line.split(" ").each do |word|
          test = cur.strip.empty? ? cur + word : "#{cur} #{word}"
          if bmp.text_size(test).width <= width
            cur = test
          elsif !cur.strip.empty? && bmp.text_size(pad + word).width <= width
            rows << cur
            cur = pad + word
          else   # too wide on its own: as much as fits on each row
            cur = test
            loop do
              start = cur.length - word.length   # where the word starts on this row
              n = start
              n += 1 while n < cur.length && bmp.text_size(cur[0, n + 1]).width <= width
              break if n >= cur.length
              n = start + 1 if n == start && cur[0, start].strip.empty?   # not one letter fits: one anyway
              rows << cur[0, n].rstrip
              word = cur[n..-1]
              cur = pad + word
            end
          end
        end
        rows << cur
      end
      return rows
    end

    # Reader: Up/Down a line, Left/Right (or the page keys) a page, Use or
    # Back closes. Mouse and touch: the wheel scrolls, a click or tap on the
    # text's upper or lower half turns a page, one on the title closes.
    def self.show_text(title, lines, gaps = true)
      lines = [_INTL("No notes for this version.")] if lines.empty?
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 999999
      # black behind the windows: the frame's own back is see-through, and the
      # load screen or a message would show through the text
      bg = Sprite.new(vp)
      bg.z = -1
      bg.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      bg.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0))
      head = Window_UnformattedTextPokemon.newWithSize(title, 0, 0, Graphics.width, 64, vp)
      win = SpriteWindow_Base.new(0, 64, Graphics.width, Graphics.height - 64)
      win.viewport = vp
      win.setSkin(MessageConfig.pbGetSystemFrame) rescue nil
      head.back_opacity = 255
      win.back_opacity = 255
      cw = win.width - win.borderX
      ch = win.height - win.borderY
      win.contents = Bitmap.new(cw, ch)
      pbSetSmallFont(win.contents) rescue nil
      base, shadow = (getDefaultTextColors(win.windowskin) rescue [Color.new(80, 80, 88), Color.new(160, 160, 168)])
      lh = 26
      rows = text_rows(win.contents, lines, cw - 12, gaps)
      per = [ch / lh, 1].max
      maxtop = [rows.length - per, 0].max
      top = 0
      draw = proc {
        win.contents.clear
        rows[top, per].each_with_index { |r, k| pbDrawShadowText(win.contents, 4, k * lh, cw - 8, lh, r, base, shadow) }
        head.text = rows.length > per ? "#{title}  (#{top + 1}-#{[top + per, rows.length].min}/#{rows.length})" : title
      }
      draw.call
      m = defined?(KIF::Mouse) ? KIF::Mouse : nil
      loop do
        Graphics.update
        Input.update
        old = top
        if m && m.clicked?
          m.swallow!   # the click isn't Use too
          break if m.over_rect?(0, 0, Graphics.width, 64)
          top += m.over_rect?(0, 64, Graphics.width, (Graphics.height - 64) / 2) ? 1 - per : per - 1
        elsif Input.repeat?(Input::DOWN) then top += 1
        elsif Input.repeat?(Input::UP) then top -= 1
        elsif Input.repeat?(Input::RIGHT) || Input.repeat?(Input::JUMPDOWN) then top += per - 1
        elsif Input.repeat?(Input::LEFT) || Input.repeat?(Input::JUMPUP) then top -= per - 1
        elsif Input.trigger?(Input::BACK) || Input.trigger?(Input::USE) then break
        end
        top = top.clamp(0, maxtop)
        draw.call if top != old
      end
      pbPlayCancelSE
      win.contents.dispose
      win.dispose
      head.dispose
      bg.bitmap.dispose
      bg.dispose
      vp.dispose
      Graphics.update   # the closing key isn't read again by the list below
      Input.update
    end
  end
end

KIF::Options.add(:others, :global) {
  ButtonOption.new(_INTL("Update history"), proc { KIF::Updater.history },
                   _INTL("Shows what changed in each KIF version"))
}
