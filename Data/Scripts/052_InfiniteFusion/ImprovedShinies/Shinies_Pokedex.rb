# # frozen_string_literal: true
#
# class PokeBattle_Scene
#   def pbShowPokedex(species, headShiny = false, bodyShiny = false)
#     pbFadeOutIn {
#       scene = PokemonPokedexInfo_Scene.new
#       screen = PokemonPokedexInfoScreen.new(scene)
#       screen.pbDexEntry(species, headShiny, bodyShiny)
#     }
#   end
# end
#
#
# class PokemonPokedexInfo_Scene
#   alias original_pokemonPokedexInfoScene_pbStartScene pbStartScene
#   def pbStartScene(species, headShiny = false, bodyShiny = false, pokemon=nil)
#     original_pokemonPokedexInfoScene_pbStartScene(species, headShiny, bodyShiny)
#     @pokemon = pokemon
#     @sprites["infosprite"].setPokemonBitmap(@pokemon)
#   end
#
#   alias original_pokemonPokedexInfoScene_ppbStartSpritesSelectSceneBrief pbStartSpritesSelectSceneBrief
#   def pbStartScene(species, alts_list,headShiny = false, bodyShiny = false)
#     original_pokemonPokedexInfoScene_ppbStartSpritesSelectSceneBrief(species, alts_list)
#     @isHead_Shiny = headShiny
#     @isBody_Shiny = bodyShiny
#     @isShiny = bodyShiny || headShiny
#     @idSpecies = getDexNumberForSpecies(species)
#
#     @sprites["infosprite"].zoom_x = Settings::FRONTSPRITE_SCALE
#     @sprites["infosprite"].zoom_y = Settings::FRONTSPRITE_SCALE
#   end
#
#   alias original_pokemonPokedexInfoScene_pbStartSceneBrief pbStartSceneBrief
#   def pbStartSceneBrief(species, headShiny = false, bodyShiny = false)
#     original_pokemonPokedexInfoScene_pbStartSceneBrief(species)
#     @isHead_Shiny = headShiny
#     @isBody_Shiny = bodyShiny
#     @isShiny = bodyShiny || headShiny
#     @idSpecies = getDexNumberForSpecies(species)
#
#     @sprites["infosprite"].zoom_x = Settings::FRONTSPRITE_SCALE
#     @sprites["infosprite"].zoom_y = Settings::FRONTSPRITE_SCALE
#   end
#
#
#
#   def pbUpdateDummyPokemon
#     @species = @dexlist[@index][0]
#     @gender, @form = $Trainer.pokedex.last_form_seen(@species)
#     if @sprites["selectedSprite"]
#       @sprites["selectedSprite"].visible = false
#     end
#     if @sprites["nextSprite"]
#       @sprites["nextSprite"].visible = false
#     end
#     if @sprites["previousSprite"]
#       @sprites["previousSprite"].visible = false
#     end
#     if @pokemon != nil
#       @sprites["infosprite"].setPokemonBitmap(@pokemon)
#     elsif @idSpecies != nil
#       @sprites["infosprite"].setPokemonBitmapFromId(@idSpecies, false, @isShiny, @isBody_Shiny, @isHead_Shiny)
#     else
#       @sprites["infosprite"].setSpeciesBitmap(@species)
#     end
#   end
# end
#
#
#
#
# class PokemonSummary_Scene
#   def drawPageFive
#     return if !$Trainer.has_pokedex
#     $Trainer.pokedex.register_last_seen(@pokemon)
#     pbFadeOutIn {
#       scene = PokemonPokedexInfo_Scene.new
#       screen = PokemonPokedexInfoScreen.new(scene)
#       screen.pbStartSceneSingle(@pokemon)
#     }
#     pbChangePokemon
#     @page -= 1
#     drawPageFour #stay on the same page
#   end
#
#
#   def drawPage(page)
#     if @pokemon.egg?
#       drawPageOneEgg
#       return
#     end
#     @sprites["itemicon"].item = @pokemon.item_id
#     overlay = @sprites["overlay"].bitmap
#     overlay.clear
#     base = Color.new(248, 248, 248)
#     shadow = Color.new(104, 104, 104)
#     # Set background image
#     @sprites["background"].setBitmap("Graphics/Pictures/Summary/bg_#{page}") if page < NB_PAGES
#     imagepos = []
#     # Show the Poké Ball containing the Pokémon
#     ballimage = sprintf("Graphics/Pictures/Summary/icon_ball_%s", @pokemon.poke_ball)
#     if !pbResolveBitmap(ballimage)
#       ballimage = sprintf("Graphics/Pictures/Summary/icon_ball_%02d", pbGetBallType(@pokemon.poke_ball))
#     end
#     imagepos.push([ballimage, 14, 60])
#     # Show status/fainted/Pokérus infected icon
#     status = 0
#     if @pokemon.fainted?
#       status = GameData::Status::DATA.keys.length / 2
#     elsif @pokemon.status != :NONE
#       status = GameData::Status.get(@pokemon.status).id_number
#     elsif @pokemon.pokerusStage == 1
#       status = GameData::Status::DATA.keys.length / 2 + 1
#     end
#     status -= 1
#     if status >= 0
#       imagepos.push(["Graphics/Pictures/statuses", 124, 100, 0, 16 * status, 44, 16])
#     end
#     # Show Pokérus cured icon
#     if @pokemon.pokerusStage == 2
#       imagepos.push([sprintf("Graphics/Pictures/Summary/icon_pokerus"), 176, 100])
#     end
#     # Show shininess star
#     if @pokemon.shiny?
#       addShinyStarsToGraphicsArray(imagepos, 2, 126, @pokemon.bodyShiny?, @pokemon.headShiny?, @pokemon.debugShiny?, nil, nil, nil, nil, true)
#       #imagepos.push([sprintf("Graphics/Pictures/shiny"), 2, 134])
#     end
#     # Draw all images
#     pbDrawImagePositions(overlay, imagepos)
#     # Write various bits of text
#     pagename = ["INFO",
#                 "TRAINER MEMO",
#                 "SKILLS",
#                 "MOVES",
#                 "MOVES"][page - 1]
#     textpos = [
#       [pagename, 26, 10, 0, base, shadow],
#       [@pokemon.name, 46, 56, 0, base, shadow],
#       [@pokemon.level.to_s, 46, 86, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)],
#       ["Item", 66, 312, 0, base, shadow]
#     ]
#     # Write the held item's name
#     if @pokemon.hasItem?
#       textpos.push([@pokemon.item.name, 16, 346, 0, Color.new(64, 64, 64), Color.new(176, 176, 176)])
#     else
#       textpos.push(["None", 16, 346, 0, Color.new(192, 200, 208), Color.new(208, 216, 224)])
#     end
#     # Write the gender symbol
#     if @pokemon.male?
#       textpos.push(["♂", 178, 56, 0, Color.new(24, 112, 216), Color.new(136, 168, 208)])
#     elsif @pokemon.female?
#       textpos.push(["♀", 178, 56, 0, Color.new(248, 56, 32), Color.new(224, 152, 144)])
#     end
#     # Draw all text
#     pbDrawTextPositions(overlay, textpos)
#     # Draw the Pokémon's markings
#     drawMarkings(overlay, 84, 292)
#     # Draw page-specific information
#     case page
#     when 1 then
#       drawPageOne
#     when 2 then
#       drawPageTwo
#     when 3 then
#       drawPageThree
#     when 4 then
#       drawPageFour
#     when 5 then
#       drawPageFive
#     end
#   end
#
# end
