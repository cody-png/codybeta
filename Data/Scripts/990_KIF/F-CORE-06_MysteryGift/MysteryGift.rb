#===============================================================================
# F-CORE-06 – KIF Mystery Gift (Reïzod)
# Source: KIF 0.20.7 001_Settings.rb:76-77 (MYSTERY_GIFT_KURAY_URL, KIF's
#   GitHub feed Data/MysteryGift.txt) and 016_UI/023_UI_MysteryGift.rb:141,258.
#
# KIF's feed holds one gift: "Fire Misbok!", a shiny Lv20 B24H200 with KIF
# shiny colours (gift id 18). It is bundled with the port
# (Data/KIF/MysteryGift_KIF.txt, KIF's file unchanged) and shows up in PIF's
# "Search for public gifts" next to PIF's own gifts, once per save (Cody,
# 2026-10-05). It works offline too.
#
# 6.8.2 adaptations: 6.8.2's gift ids are strings from its JSON feed; KIF's
# gifts get ids "KIF-<n>" so they can't clash. KIF's file uses the old
# Essentials format, which 6.8.2's pbMysteryGiftDecrypt still reads.
#===============================================================================
module KIF
  module MysteryGift
    FILE = "Data/KIF/MysteryGift_KIF.txt"
    @public_search = false
    class << self
      attr_accessor :public_search
    end

    def self.gifts
      return [] unless File.exist?(FILE)
      list = pbMysteryGiftDecrypt(File.read(FILE)) rescue []
      list = [] unless list.is_a?(Array)
      list.each { |g| g[0] = "KIF-#{g[0]}" }
      return list
    rescue => e
      KIF.log("KIF Mystery Gift: #{e.message}")
      return []
    end
  end
end

alias kif_mg_downloadMysteryGifts downloadMysteryGifts unless defined?(kif_mg_downloadMysteryGifts)
alias kif_mg_pbDownloadToString pbDownloadToString unless defined?(kif_mg_pbDownloadToString)
alias kif_mg_pbMysteryGiftReadFromJson pbMysteryGiftReadFromJson unless defined?(kif_mg_pbMysteryGiftReadFromJson)

def downloadMysteryGifts(url, sprites, viewport, trainer)
  old = KIF::MysteryGift.public_search
  KIF::MysteryGift.public_search = (url == MysteryGift::URL)
  begin
    return kif_mg_downloadMysteryGifts(url, sprites, viewport, trainer)
  ensure
    KIF::MysteryGift.public_search = old
  end
end

# Offline: an empty feed still lets the KIF gift through
def pbDownloadToString(url, *args)
  ret = kif_mg_pbDownloadToString(url, *args)
  if KIF::MysteryGift.public_search && url == MysteryGift::URL && (ret.nil? || ret.to_s.strip.empty?)
    ret = "{}"
  end
  return ret
end

def pbMysteryGiftReadFromJson(json_string, trainer)
  ret = (kif_mg_pbMysteryGiftReadFromJson(json_string, trainer) rescue [])
  ret = [] unless ret.is_a?(Array)
  ret += KIF::MysteryGift.gifts if KIF::MysteryGift.public_search
  return ret
end
