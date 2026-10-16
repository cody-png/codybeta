#===============================================================================
# Settings by module: which registered settings belong to which module.
# The settings screen (016_KIF_SettingsScreen.rb) shows them; the Modules
# section there sets each module Off / On / Hidden (011_KIF_Modules.rb).
#===============================================================================
module KIF
  module Options
    # Every menu settings can be registered in (KIF's and Cody Settings)
    def self.all_menu_ids
      return MENUS.keys + @extra_menus.keys
    end

    # [scope, builder] of every setting whose code belongs to module id
    # (:general = settings of always-on features)
    def self.module_entries(id)
      want = (id == :general) ? nil : id
      list = []
      all_menu_ids.each do |menu|
        entries(menu).each do |scope, builder|
          list << [scope, builder] if KIF::Modules.for_proc(builder) == want
        end
      end
      return list
    end
  end
end
