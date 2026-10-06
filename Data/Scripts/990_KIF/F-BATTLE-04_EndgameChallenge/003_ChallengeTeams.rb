#===============================================================================
# F-BATTLE-04 – Endgame Challenge team tuning (DemICE)
# Copy of KIF 0.20.7 101_DemICE's Endgame Challenge/ChallengeMode.rb:575-2404,
# the body of its GameData::Trainer#to_trainer wrapper, unchanged except the
# lines marked "# KIF port". Called by 002_EndgameChallenge.rb for trainers
# loaded on the challenge maps while the challenge is on:
#   * every Pokémon at your highest level (at least 60), 252 EVs (+200 Atk /
#     Sp. Atk), Speed 0 with Trick Room;
#   * "Shedproofing": if your party has a Wonder Guard Pokémon, specific
#     Pokémon swap a move for one that can hit it (Hidden Power IVs set to the
#     needed type).
# KIF quirk kept: B9H378 tries to learn "MYSTICWATER" (an item, not a move),
# which PIF ignores, so it keeps 3 moves in that case.
#===============================================================================
module KIF
  module Endgame
    def self.tune_team(trainer, pokemon_data)
				trainer.party.each_with_index do |pkmn, i|
					pkmn_data = pokemon_data[i]
					next unless pkmn_data   # KIF port: party longer than the data (randomizer)
					pkmn.abilityMutation = true if pkmn_data[:abilityMutation] && pkmn.respond_to?(:abilityMutation=)   # KIF port: guard
						maxlevel=0
						for i in $Trainer.party
							if i.level>maxlevel
								maxlevel=i.level
							end
						end
						maxlevel=60 if maxlevel<60
						pkmn.level=maxlevel
					GameData::Stat.each_main do |s|
						pkmn.ev[s.id] = 252
						pkmn.ev[s.id]+= 200 if (s.id==:ATTACK || s.id==:SPECIAL_ATTACK)
						pkmn.ev[s.id] = 0 if (s.id==:SPEED) && pkmn.hasMove?(:TRICKROOM)
					end
					pkmn.calc_stats
					#Shedproofing
					needfairy=false
					needdark=false
					needfire=false
					needsomething=false
					for i in $Trainer.party
						if i.ability==:WONDERGUARD
							needfairy=true if i.hasType?(:DARK) && i.hasType?(:GHOST)
							needdark=true if i.hasType?(:NORMAL) && i.hasType?(:GHOST)
							needfire=true if i.hasType?(:BUG) && i.hasType?(:STEEL)
							needsomething=true if !needfairy && !needfire && !needdark
						end
					end
					partypoopers=0
					partypoopers+=1 if needfairy
					partypoopers+=1 if needdark
					partypoopers+=1 if needfire
					case pkmn.species
					# Lorelei
					when :B135H272
						if partypoopers>1 || needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:HIDDENPOWER)# 31,30,31,30,31,30
								pkmn.iv[:HP]=31
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:DEFENSE]=31
								pkmn.iv[:SPEED]=30
								pkmn.iv[:SPECIAL_ATTACK]=31
								pkmn.iv[:SPECIAL_DEFENSE]=30
							end
							if needdark
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:HIDDENPOWER)# 31,30,30,31,30,31
								pkmn.iv[:HP]=31
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:DEFENSE]=30
								pkmn.iv[:SPEED]=31
								pkmn.iv[:SPECIAL_ATTACK]=30
								pkmn.iv[:SPECIAL_DEFENSE]=31
							end
							if needfairy
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:HIDDENPOWER)# 30,30,31,31,30,31
								pkmn.iv[:HP]=30
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:DEFENSE]=31
								pkmn.iv[:SPEED]=31
								pkmn.iv[:SPECIAL_ATTACK]=30
								pkmn.iv[:SPECIAL_DEFENSE]=31
							end
						end
					when :B91H130
						if partypoopers>1
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:FIREBLAST)
							end
							if needdark
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:CRUNCH)
							end
							if needfairy
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:HIDDENPOWER)
								pkmn.iv[:HP]=30
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:SPECIAL_ATTACK]=30
							end
						end
					when :B262H361
						if needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:STEALTHROCK)
						end
						if partypoopers>1
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:FIREFANG)
							end
							if needdark
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:HAIL)
							end
						end
					when :B121H124
						if partypoopers>1
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							if needfire # 31,30,31,30,31,30
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:HIDDENPOWER)
								pkmn.iv[:HP]=31
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:DEFENSE]=31
								pkmn.iv[:SPEED]=30
								pkmn.iv[:SPECIAL_ATTACK]=31
								pkmn.iv[:SPECIAL_DEFENSE]=30
							end
							if needdark
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:HIDDENPOWER)# 31,30,30,31,30,31
								pkmn.iv[:HP]=31
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:DEFENSE]=30
								pkmn.iv[:SPEED]=31
								pkmn.iv[:SPECIAL_ATTACK]=30
								pkmn.iv[:SPECIAL_DEFENSE]=31
							end
							if needfairy
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:MOONBLAST)
							end
						end
					when :B144H367
						if partypoopers>1 || needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B144H367
						if partypoopers>1
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:FIREFANG)
							end
							if needdark
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:CRUNCH)
							end
							if needfairy
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:HAIL)
							end
						end
					# Bruno
					when :B142H106
						if needsomething
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:STEALTHROCK)
						end
						if partypoopers>0
							pkmn.item = :REDCARD
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:WHIRLWIND)
							pkmn.forget_move(:FAKEOUT)
							pkmn.learn_move(:STEALTHROCK)
						end
					when :B107H212
						if partypoopers>1
							pkmn.forget_move(:ROCKTOMB)
							pkmn.learn_move(:SANDSTORM)
							pkmn.forget_move(:MACHPUNCH)
							pkmn.learn_move(:FIREPUNCH)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:BRUTALSWING)
							end
							if needfairy
								pkmn.forget_move_at_index(2)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B321H94
						if partypoopers>0 || needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B208H367
						if partypoopers>0
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B68H293
						if partypoopers>1
							pkmn.forget_move(:STONEEDGE)
							pkmn.learn_move(:SANDSTORM)
							pkmn.forget_move(:BULLETPUNCH)
							pkmn.learn_move(:FIREPUNCH)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:TOXIC)
							end
						end
					# Agatha
					when :B255H263
						if needdark || needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B328H197
						if partypoopers>0
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B105H373
						if partypoopers>1
							pkmn.forget_move_at_index(1)
							pkmn.learn_move(:WILLOWISP)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(1)
								pkmn.learn_move(:FIREPUNCH)
							else
								pkmn.forget_move_at_index(1)
								pkmn.learn_move(:WILLOWISP)
							end
						end
					when :B289H331
						if needfire
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B94H275
						if needfire
							pkmn.forget_move(:SHADOWBALL)
							pkmn.learn_move(:WILLOWISP)
						end
						if needfairy
							pkmn.forget_move(:FOCUSBLAST)
							pkmn.learn_move(:DAZZLINGGLEAM)
						end
					when :B281H94
						if partypoopers>2
							pkmn.forget_move(:SHADOWBALL)
							pkmn.learn_move(:DARKPULSE)
							pkmn.forget_move(:FOCUSBLAST)
							pkmn.learn_move(:DAZZLINGGLEAM)
						elsif partypoopers>1
							if needfire
								if needdark
									pkmn.forget_move(:SHADOWBALL)
									pkmn.learn_move(:DARKPULSE)
								end
								if needfairy
									pkmn.forget_move(:SHADOWBALL)
									pkmn.learn_move(:DAZZLINGGLEAM)
								end
							else
								pkmn.forget_move(:FIREBLAST)
								pkmn.learn_move(:DAZZLINGGLEAM)
								pkmn.forget_move(:SHADOWBALL)
								pkmn.learn_move(:DARKPULSE)
							end
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:SHADOWBALL)
								pkmn.learn_move(:DARKPULSE)
							end
							if needfairy
								pkmn.forget_move(:FOCUSBLAST)
								pkmn.learn_move(:DAZZLINGGLEAM)
							end
						end
					#Lance
					when :B299H309
						if needsomething
							pkmn.forget_move_at_index(1)
							pkmn.learn_move(:STEALTHROCK)
						end
						if needfairy || needdark
							pkmn.forget_move_at_index(1)
							pkmn.learn_move(:SANDSTORM)
						end
					when :B208H130
						if partypoopers>0
							pkmn.item = :REDCARD
							pkmn.forget_move(:POWERWHIP)
							pkmn.learn_move(:ROAR)
							pkmn.forget_move(:THUNDERWAVE)
							pkmn.learn_move(:STEALTHROCK)
						end
					when :B142H306
						if partypoopers>0
							pkmn.forget_move_at_index(1)
							pkmn.learn_move(:SANDSTORM)
						end
					when :B377H269
						if needdark
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:DARKPULSE)
						end
					when :B368H281
						if needdark || needfairy
							pkmn.ability = :MOLDBREAKER
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:DRAGONDANCE)
						end
					when :B149H293
						if partypoopers>1
							pkmn.forget_move_at_index(0)
							pkmn.learn_move(:SANDSTORM)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needfairy
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:SANDSTORM)
							end
							if needdark
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:BRUTALSWING)
							end
						end
					#Blue
					when :B142H267
						if needsomething
							pkmn.forget_move(:DRAGONDANCE)
							pkmn.learn_move(:STEALTHROCK)
						end
						if partypoopers>0
							pkmn.item = :REDCARD
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:WHIRLWIND)
							pkmn.forget_move(:DRAGONDANCE)
							pkmn.learn_move(:STEALTHROCK)
						end
					when :B265H103
						if partypoopers>0
							pkmn.forget_move_at_index(1)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B195H268
						if partypoopers>0 || needsomething
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B128H184
						if partypoopers>1
							pkmn.forget_move_at_index(3)
							if needfire
								pkmn.learn_move(:HAIL)
							else
								pkmn.learn_move(:TOXIC)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:TOXIC)
							end
							if needfairy
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:PLAYROUGH)
							end
							if needdark
								pkmn.forget_move_at_index(3)
								pkmn.learn_move(:KNOCKOFF)
							end
						end
					when :B65H275
						if partypoopers>0
							if needfire # 31,30,31,30,31,30
								pkmn.forget_move(:FOCUSBLAST)
								pkmn.learn_move(:HIDDENPOWER)
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:SPEED]=30
								pkmn.iv[:SPECIAL_DEFENSE]=30
							end
							if needdark
								pkmn.forget_move(:NASTYPLOT)
								pkmn.learn_move(:DARKPULSE)
							end
						end
					when :B6H379
						if partypoopers>0
							pkmn.forget_move_at_index(1)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B9H378
						if partypoopers>1
							pkmn.forget_move_at_index(0)
							if needfire
								pkmn.learn_move(:HAIL)
							else
								pkmn.learn_move(:TOXIC)
							end
						elsif partypoopers>0
							pkmn.forget_move_at_index(0)
							if needfire
								pkmn.learn_move(:MYSTICWATER)
							end
							if needfairy
								pkmn.learn_move(:HIDDENPOWER)
								pkmn.iv[:HP]=30
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:SPECIAL_ATTACK]=30
							end
							if needdark
								pkmn.learn_move(:DARKPULSE)
							end
						end
					when :B348H3
						if partypoopers>0
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:LEECHSEED)
						end
					# Brock
					when :B76H318
						if partypoopers>0
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B142H25
						if needsomething
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:STEALTHROCK)
						end
						if partypoopers>0
							pkmn.forget_move(:AQUATAIL)
							pkmn.learn_move(:WHIRLWIND)
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:STEALTHROCK)
						end
					when :B244H302
						if partypoopers>0 || needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B208H374
						if partypoopers>0
							pkmn.forget_move_at_index(2)
							pkmn.learn_move(:WILLOWISP)
						end
					# Misty
					when :B309H130
						if needfire
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREPUNCH)
						end
						if needfairy
							pkmn.forget_move(:DRAGONDANCE)
							pkmn.learn_move(:TOXIC)
						end
						if needdark
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:KNOCKOFF)
						end
					when :B243H186
						if needfairy || needdark || needsomething
							pkmn.forget_move(:REFLECT)
							pkmn.learn_move(:TOXIC)
						end
					when :B266H134
						if partypoopers>0 || needsomething
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B299H184
						if needfire
							pkmn.forget_move(:AQUAJET)
							pkmn.learn_move(:FIREFANG)
						end
						if needfairy
							pkmn.forget_move(:ICEPUNCH)
							pkmn.learn_move(:PLAYROUGH)
						end
					when :B336H171
						if needfire
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREFANG)
						end
						if needfairy || needdark
							pkmn.forget_move(:AQUATAIL)
							pkmn.learn_move(:TOXIC)
						end
					when :B135H121
						if partypoopers>1
							pkmn.forget_move_at_index(3)
							pkmn.learn_move(:CONFUSERAY)
						elsif partypoopers>0
							pkmn.forget_move_at_index(3)
							if needfire
								pkmn.learn_move(:HIDDENPOWER)
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:SPEED]=30
								pkmn.iv[:SPECIAL_DEFENSE]=30
							end
							if needdark
								pkmn.learn_move(:BITE)
							end
							if needfairy
								pkmn.learn_move(:MOONBLAST)
							end
						end
					# Surge
					when :B135H124
						if partypoopers>0
							pkmn.forget_move(:FOCUSBLAST)
							pkmn.learn_move(:NIGHTMARE)
						end
					when :B262H267
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>1
							if needfire
								if needdark
									pkmn.forget_move(:EARTHQUAKE)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:EARTHQUAKE)
									pkmn.learn_move(:HAIL)
								end
							else
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:HAIL)
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:KNOCKOFF)
							end
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:HAIL)
							end
						end
					when :B110H181
						if partypoopers>0 || needsomething
							pkmn.forget_move(:THUNDERWAVE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B336H332
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREFANG)
							pkmn.forget_move(:ZINGZAP)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:ZINGZAP)
								pkmn.learn_move(:FIREFANG)
								if needdark
									pkmn.forget_move(:EARTHQUAKE)
									pkmn.learn_move(:CRUNCH)
								end
								if needfairy
									pkmn.forget_move(:EARTHQUAKE)
									pkmn.learn_move(:TOXIC)
								end
							else
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:CRUNCH)
								pkmn.forget_move(:ZINGZAP)
								pkmn.learn_move(:TOXIC)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:ZINGZAP)
								pkmn.learn_move(:FIREFANG)
							end
							if needfairy
								pkmn.forget_move(:ZINGZAP)
								pkmn.learn_move(:TOXIC)
							end
							if needdark
								pkmn.forget_move(:ZINGZAP)
								pkmn.learn_move(:CRUNCH)
							end
						end
					when :B348H358
						if needfairy || needdark
							pkmn.item= :FOCUSSASH
							pkmn.forget_move(:TECHNOBLAST)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B142H26
						if needfire
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREFANG)
						end
						if needfairy
							if needdark
								pkmn.forget_move(:VOLTTACKLE)
								pkmn.learn_move(:TOXIC)
							else
								pkmn.forget_move(:AQUATAIL)
								pkmn.learn_move(:TOXIC)
							end
						end
						if needdark
							pkmn.forget_move(:AQUATAIL)
							pkmn.learn_move(:CRUNCH)
						end
					#Erika
					when :B135H278
						if partypoopers>0 || needsomething
							pkmn.forget_move(:DRAGONPULSE)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B333H318
						if partypoopers>0 || needsomething
							pkmn.forget_move(:FIREPUNCH)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B368H355
						if partypoopers>0 || needsomething
							pkmn.ability = :MOLDBREAKER
						end
					when :B364H184
						if partypoopers>0 || needsomething
							pkmn.forget_move(:THUNDERWAVE)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B271H244
						if partypoopers>0 || needsomething
							pkmn.forget_move(:SWORDSDANCE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B266H143
						if partypoopers>0 || needsomething
							pkmn.forget_move(:ROCKSLIDE)
							pkmn.learn_move(:LEECHSEED)
						end
					#Koga
					when :B149H89
						if needfairy || needdark
							pkmn.forget_move(:FIREPUNCH)
							pkmn.learn_move(:GASTROACID)
						end
					when :B49H377
						if partypoopers>1
							pkmn.forget_move(:BATONPASS)
							pkmn.learn_move(:HIDDENPOWER)
							pkmn.iv[:HP]=30
							pkmn.iv[:ATTACK]=30
							pkmn.iv[:SPECIAL_ATTACK]=30
							pkmn.forget_move(:SLEEPPOWDER)
							pkmn.learn_move(:FIREBLAST)
						elsif partypoopers>0
							pkmn.forget_move(:BATONPASS)
							if needfire
								pkmn.learn_move(:FIREBLAST)
							end
							if needfairy
								pkmn.learn_move(:HIDDENPOWER)
								pkmn.iv[:HP]=30
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:SPECIAL_ATTACK]=30
							end
						end
					when :B89H184
						if partypoopers>0
							pkmn.forget_move(:THUNDERPUNCH)
							pkmn.learn_move(:GASTROACID)
						end
					when :B110H263
						if needfairy || needdark || needsomething
							pkmn.forget_move(:THUNDERWAVE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B309H34
						if partypoopers>1
							pkmn.forget_move(:WATERFALL)
							pkmn.learn_move(:TOXIC)
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:KNOCKOFF)
						elsif partypoopers>0
							pkmn.forget_move(:WATERFALL)
							if needdark
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.learn_move(:TOXIC)
							end
						end
					# Sabrina
					when :B321H196
						if needfairy || needdark
							pkmn.forget_move(:SHADOWBALL)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B245H103
						if partypoopers>0 || needsomething
							pkmn.forget_move(:BLIZZARD)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B293H143
						if needfire || needfairy
							pkmn.forget_move(:SLACKOFF)
							pkmn.learn_move(:GASTROACID)
						end
					when :B331H288
						if partypoopers>0 || needsomething
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B36H151
						if needfairy || needdark || needsomething
							pkmn.forget_move(:PHOTONGEYSER)
							pkmn.learn_move(:MOONGEISTBEAM)
						end
					when :B65H157
						if needfairy || needdark
							pkmn.forget_move(:ERUPTION)
							pkmn.learn_move(:WILLOWISP)
						end
					# Blaine
					when :B377H268
						if needfairy || needdark
							pkmn.forget_move(:SURF)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B38H352
						if needfairy || needdark
							pkmn.forget_move(:SLEEPPOWDER)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B278H6
						if needfairy || needdark || needsomething
							pkmn.forget_move(:DRAGONPULSE)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					when :B135H157
						if needfairy || needdark
							pkmn.forget_move(:ERUPTION)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B244H334
						if needfairy || needdark
							pkmn.forget_move(:STONEEDGE)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					when :B142H59
						if needfairy || needdark || needsomething
							pkmn.species=:B142H78
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					# Giovanni
					when :B38H334
						if needfairy || needdark || needsomething
							pkmn.forget_move(:DRAGONPULSE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B34H374
						if partypoopers>0
							pkmn.forget_move(:THUNDERBOLT)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B232H184
						if partypoopers>1
							pkmn.forget_move(:ICESHARD)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							pkmn.forget_move(:ICESHARD)
							if needfire
								pkmn.learn_move(:HAIL)
							end
							if needfairy
								pkmn.learn_move(:SANDSTORM)
							end
							if needdark
								pkmn.learn_move(:KNOCKOFF)
							end
						end
					when :B262H51
						if partypoopers>1
							pkmn.forget_move(:ICESHARD)
							pkmn.learn_move(:HAIL)
						elsif partypoopers>0
							pkmn.forget_move(:ICESHARD)
							if needfire
								pkmn.learn_move(:HAIL)
							end
							if needfairy
								pkmn.learn_move(:SANDSTORM)
							end
							if needdark
								pkmn.learn_move(:KNOCKOFF)
							end
						end
					when :B265H110
						if needsomething
							pkmn.forget_move(:THUNDERPUNCH)
							pkmn.learn_move(:WILLOWISP)
						end
						if partypoopers>1
							pkmn.forget_move(:THUNDERPUNCH)
							pkmn.learn_move(:WILLOWISP)
						elsif partypoopers>0
							pkmn.forget_move(:THUNDERPUNCH)
							if needfire
								pkmn.learn_move(:FIREPUNCH)
							end
							if needfairy || needdark
								pkmn.learn_move(:WILLOWISP)
							end
						end
					# Whitney
					when :B254H214
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREPUNCH)
							pkmn.forget_move(:ROCKBLAST)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
								if needdark
									pkmn.forget_move(:ROCKBLAST)
									pkmn.learn_move(:THIEF)
								end
								if needfairy
									pkmn.forget_move(:ROCKBLAST)
									pkmn.learn_move(:TOXIC)
								end
							else
								pkmn.forget_move(:ROCKBLAST)
								pkmn.learn_move(:TOXIC)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:ROCKBLAST)
								pkmn.learn_move(:THIEF)
							end
							if needfairy
								pkmn.forget_move(:ROCKBLAST)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B151H383
						if needsomething
							pkmn.forget_move(:DRAINPUNCH)
							pkmn.learn_move(:MOONGEISTBEAM)
						end
						if partypoopers>1
							if needfire && needdark
								pkmn.forget_move(:DRAINPUNCH)
								pkmn.learn_move(:MOONGEISTBEAM)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:DRAINPUNCH)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:DRAINPUNCH)
								pkmn.learn_move(:MOONGEISTBEAM)
							end
						end
					when :B273H143
						if partypoopers>0
							pkmn.forget_move(:BATONPASS)
							pkmn.learn_move(:GASTROACID)
						end
					when :B289H217
						if partypoopers>0 || needsomething
							pkmn.forget_move(:TOXIC)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B309H184
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREPUNCH)
							pkmn.forget_move(:FRUSTRATION)
							pkmn.learn_move(:PLAYROUGH)
							pkmn.forget_move(:AQUAJET)
							pkmn.learn_move(:KNOCKOFF)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
								if needdark
									pkmn.forget_move(:FRUSTRATION)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:FRUSTRATION)
									pkmn.learn_move(:PLAYROUGH)
								end
							else
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
								pkmn.forget_move(:AQUAJET)
								pkmn.learn_move(:PLAYROUGH)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:AQUAJET)
								pkmn.learn_move(:PLAYROUGH)
							end
						end
					when :B275H374
						if partypoopers>2
							pkmn.forget_move(:FIREBLAST)
							pkmn.learn_move(:WILLOWISP)
						elsif partypoopers>1
							if needdark || needfairy
								pkmn.forget_move(:TECHNOBLAST)
								pkmn.learn_move(:WILLOWISP)
							end
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:FIREBLAST)
								pkmn.learn_move(:DARKPULSE)
							end
							if needfairy
								pkmn.forget_move(:TECHNOBLAST)
								pkmn.learn_move(:WILLOWISP)
							end
						end
					# Kurt
					when :B309H214
						if partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:FRUSTRATION)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:STONEEDGE)
								pkmn.learn_move(:PLAYROUGH)
							end
						end
					when :B123H142
						if needsomething
							pkmn.ability = :STEALTHROCK
						end
						if partypoopers>0
							pkmn.item = :REDCARD
							pkmn.forget_move(:SWORDSDANCE)
							pkmn.learn_move(:WHIRLWIND)
							pkmn.forget_move(:AQUATAIL)
							pkmn.learn_move(:STEALTHROCK)
						end
					when :B127H229
						if partypoopers>0
							pkmn.ability = :MOLDBREAKER
						end
					when :B304H184
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREPUNCH)
							pkmn.forget_move(:XSCISSOR)
							pkmn.learn_move(:PLAYROUGH)
							pkmn.forget_move(:ACCELEROCK)
							pkmn.learn_move(:KNOCKOFF)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
								if needdark
									pkmn.forget_move(:XSCISSOR)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:XSCISSOR)
									pkmn.learn_move(:PLAYROUGH)
								end
							else
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
								pkmn.forget_move(:XSCISSOR)
								pkmn.learn_move(:PLAYROUGH)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:XSCISSOR)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:XSCISSOR)
								pkmn.learn_move(:PLAYROUGH)
							end
						end
					when :B296H289
						if partypoopers>0 || needsomething
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B348H374
						if partypoopers>0
							pkmn.forget_move(:FLASHCANNON)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					# Falkner
					when :B169H25
						if needdark && needfairy
							pkmn.forget_move(:IRONTAIL)
							pkmn.learn_move(:TOXIC)
						else
							if needdark
								pkmn.forget_move(:IRONTAIL)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:IRONTAIL)
								pkmn.learn_move(:PLAYROUGH)
							end
						end
					when :B142H281
						if needdark || needfairy
							pkmn.forget_move(:SWORDSDANCE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B269H324
						if needdark && needfairy
							pkmn.forget_move(:FLASHCANNON)
							if needfire
								pkmn.forget_move(:AIRSLASH)
							else
								pkmn.forget_move(:FIREBLAST)
							end
							pkmn.learn_move(:HIDDENPOWER) # 31,30,30,31,30,31
							pkmn.iv[:ATTACK]=30
							pkmn.iv[:DEFENSE]=30
							pkmn.iv[:SPECIAL_ATTACK]=30
							pkmn.learn_move(:MOONBLAST)
						else
							if needdark
								pkmn.forget_move(:FLASHCANNON)
								pkmn.learn_move(:HIDDENPOWER) # 31,30,30,31,30,31
								pkmn.iv[:ATTACK]=30
								pkmn.iv[:DEFENSE]=30
								pkmn.iv[:SPECIAL_ATTACK]=30
							end
							if needfairy
								pkmn.forget_move(:FLASHCANNON)
								pkmn.learn_move(:MOONBLAST)
							end
						end
					when :B270H381
						if needdark || needfairy || needsomething
							pkmn.forget_move(:IRONDEFENSE)
							pkmn.learn_move(:TOXIC)
						elsif needfire
							pkmn.forget_move(:IRONDEFENSE)
							pkmn.learn_move(:FIREPUNCH)
						end
					when :B336H334
						if partypoopers>2
							pkmn.forget_move(:BRICKBREAK)
							pkmn.learn_move(:FIREPUNCH)
							pkmn.forget_move(:STONEEDGE)
							pkmn.learn_move(:SANDSTORM)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:BRICKBREAK)
								pkmn.learn_move(:FIREPUNCH)
								if needdark
									pkmn.forget_move(:STONEEDGE)
									pkmn.learn_move(:CRUNCH)
								end
								if needfairy
									pkmn.forget_move(:STONEEDGE)
									pkmn.learn_move(:SANDSTORM)
								end
							else
								pkmn.forget_move(:BRICKBREAK)
								pkmn.learn_move(:CRUNCH)
								pkmn.forget_move(:STONEEDGE)
								pkmn.learn_move(:SANDSTORM)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:BRICKBREAK)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:BRICKBREAK)
								pkmn.learn_move(:CRUNCH)
							end
							if needfairy
								pkmn.forget_move(:BRICKBREAK)
								pkmn.learn_move(:SANDSTORM)
							end
						end
					when :B273H171
						if partypoopers>1
							pkmn.forget_move(:SWORDSDANCE)
							pkmn.learn_move(:TAILGLOW)
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:SOAK)
							pkmn.forget_move(:CRABHAMMER)
							pkmn.learn_move(:THUNDER)
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREFANG)
							end
							if needdark
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:TOXIC)
							end
						end
					# Clair
					when :B299H130
						if partypoopers>2
							pkmn.forget_move(:THUNDERWAVE)
							pkmn.learn_move(:FIREFANG)
							pkmn.forget_move(:STONEEDGE)
							pkmn.learn_move(:SANDSTORM)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:THUNDERWAVE)
								pkmn.learn_move(:FIREFANG)
								if needdark
									pkmn.forget_move(:STONEEDGE)
									pkmn.learn_move(:CRUNCH)
								end
								if needfairy
									pkmn.forget_move(:STONEEDGE)
									pkmn.learn_move(:SANDSTORM)
								end
							else
								pkmn.forget_move(:THUNDERWAVE)
								pkmn.learn_move(:SANDSTORM)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:THUNDERWAVE)
								pkmn.learn_move(:FIREFANG)
							end
							if needdark
								pkmn.forget_move(:THUNDERWAVE)
								pkmn.learn_move(:CRUNCH)
							end
							if needfairy
								pkmn.forget_move(:THUNDERWAVE)
								pkmn.learn_move(:SANDSTORM)
							end
						end
					when :B368H212
						if partypoopers>0 || needsomething
							pkmn.ability = :MOLDBREAKER
							pkmn.forget_move(:BULLETPUNCH)
							pkmn.learn_move(:IRONHEAD)
							pkmn.forget_move(:BULLDOZE)
							pkmn.learn_move(:EARTHQUAKE)
						end
					when :B377H146
						if needdark || needfairy || needsomething
							pkmn.forget_move(:FLASHCANNON)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B309H336
						if partypoopers>2
							pkmn.forget_move(:DRAGONDANCE)
							pkmn.learn_move(:FIREBLAST)
							pkmn.forget_move(:DRAGONRUSH)
							pkmn.learn_move(:PLAYROUGH)
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:KNOCKOFF)
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:DRAGONRUSH)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:FRUSTRATION)
								pkmn.learn_move(:PLAYROUGH)
							end
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
							end
						end
					when :B149H184
						if needfire
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREPUNCH)
						end
						if needfairy
							pkmn.forget_move(:DRAGONRUSH)
							pkmn.learn_move(:PLAYROUGH)
						end
					when :B230H269
						if needdark
							pkmn.forget_move(:AURASPHERE)
							pkmn.learn_move(:HIDDENPOWER) # 31,30,30,31,30,31
							pkmn.iv[:ATTACK]=30
							pkmn.iv[:DEFENSE]=30
							pkmn.iv[:SPECIAL_ATTACK]=30
					    end
					# Morty
					when :B94H377
						if needfire
							pkmn.forget_move(:FOCUSBLAST)
							pkmn.learn_move(:FIREBLAST)
						end
						if needfairy
							pkmn.forget_move(:SHADOWBALL)
							pkmn.learn_move(:DAZZLINGGLEAM)
						end
					when :B321H255
						if needdark
							pkmn.forget_move(:FIREBLAST)
							pkmn.learn_move(:DARKPULSE)
						end
					when :B309H373
						if partypoopers>1
							pkmn.forget_move(:SHADOWSNEAK)
							pkmn.learn_move(:WILLOWISP)
						elsif partypoopers>0
							if needfairy
								pkmn.forget_move(:SHADOWSNEAK)
								pkmn.learn_move(:PLAYROUGH)
							end
							if needfire
								pkmn.forget_move(:SHADOWSNEAK)
								pkmn.learn_move(:FIREPUNCH)
							end
						end
					when :B312H242
						if partypoopers>0
							pkmn.forget_move(:SOFTBOILED)
							pkmn.learn_move(:REST)
							pkmn.forget_move(:NIGHTSHADE)
							pkmn.learn_move(:SPITE)
							pkmn.forget_move(:TOXIC)
							pkmn.learn_move(:SLEEPTALK)
						end
					when :B289H310
						if needfire || needsomething
							pkmn.forget_move(:SHADOWSNEAK)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B348H367
						if needdark || needfairy || needsomething
							pkmn.forget_move(:BUGBUZZ)
							pkmn.learn_move(:WILLOWISP)
						end
					# Pryce
					when :B262H321
						if needdark || needfairy
							pkmn.forget_move(:CLOSECOMBAT)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B262H184
						if partypoopers>0 || needsomething
							pkmn.forget_move(:BRICKBREAK)
							pkmn.learn_move(:HAIL)
						end
					when :B157H124
						if needdark || needfairy
							pkmn.forget_move(:BLIZZARD)
							pkmn.learn_move(:HAIL)
						end
					when :B272H367
						if needdark || needfairy
							pkmn.forget_move(:FREEZEDRY)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B91H245
						if partypoopers>0
							pkmn.forget_move(:ROCKBLAST)
							pkmn.learn_move(:HAIL)
						end
					when :B299H274
						if partypoopers>0
							pkmn.forget_move(:STONEEDGE)
							pkmn.learn_move(:HAIL)
						end
					# Jasmine
					when :B94H263
						if partypoopers>0 || needsomething
							pkmn.forget_move(:GIGADRAIN)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B377H263
						if needdark && needfairy
							pkmn.forget_move(:SURF)
							pkmn.learn_move(:DARKPULSE)
							pkmn.forget_move(:DRAGONPULSE)
							pkmn.learn_move(:SANDSTORM)
						end
					when :B336H324
						if partypoopers>2
							pkmn.forget_move(:AQUATAIL)
							pkmn.learn_move(:FIREFANG)
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:SANDSTORM)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREFANG)
								if needdark
									pkmn.forget_move(:AQUATAIL)
									pkmn.learn_move(:CRUNCH)
								end
								if needfairy
									pkmn.forget_move(:AQUATAIL)
									pkmn.learn_move(:SANDSTORM)
								end
							else
								pkmn.forget_move(:AQUATAIL)
								pkmn.learn_move(:SANDSTORM)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREFANG)
							end
							if needdark
								pkmn.forget_move(:AQUATAIL)
								pkmn.learn_move(:CRUNCH)
							end
							if needfairy
								pkmn.forget_move(:AQUATAIL)
								pkmn.learn_move(:SANDSTORM)
							end
						end
					when :B205H184
						if partypoopers>2
							pkmn.item = :MENTALHERB
							pkmn.forget_move(:ICEPUNCH)
							pkmn.learn_move(:STEALTHROCK)
							pkmn.forget_move(:SHELLSMASH)
							pkmn.learn_move(:SANDSTORM)
						elsif partypoopers>1
							if needfire
								pkmn.item = :MENTALHERB
								pkmn.forget_move(:SHELLSMASH)
								pkmn.learn_move(:STEALTHROCK)
								if needdark
									pkmn.forget_move(:ICEPUNCH)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:ICEPUNCH)
									pkmn.learn_move(:PLAYROUGH)
								end
							else
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:SANDSTORM)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:STEALTHROCK)
							end
							if needdark
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:CRUNCH)
							end
							if needfairy
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:PLAYROUGH)
							end
						end
					when :B326H335
						if needfire
							pkmn.forget_move(:EARTHPOWER)
							pkmn.learn_move(:SANDSTORM)
						end
					when :B208H378
						if partypoopers>0
							if needfire
								pkmn.forget_move(:DRAGONPULSE)
								pkmn.learn_move(:FLASHCANNON)
								pkmn.forget_move(:EARTHPOWER)
								pkmn.learn_move(:MYSTICALFIRE)
							else
								pkmn.forget_move(:DRAGONPULSE)
								pkmn.learn_move(:FLASHCANNON)
								pkmn.forget_move(:EARTHPOWER)
								pkmn.learn_move(:TOXIC)
							end
						end
					# Chuck
					when :B169H106
						if partypoopers>2
							pkmn.forget_move(:FAKEOUT)
							pkmn.learn_move(:BLAZEKICK)
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:FAKEOUT)
								pkmn.learn_move(:BLAZEKICK)
								if needdark
									pkmn.forget_move(:EARTHQUAKE)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:EARTHQUAKE)
									pkmn.learn_move(:TOXIC)
								end
							else
								pkmn.forget_move(:FAKEOUT)
								pkmn.learn_move(:TOXIC)
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:FAKEOUT)
								pkmn.learn_move(:BLAZEKICK)
							end
							if needdark
								pkmn.forget_move(:FAKEOUT)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:FAKEOUT)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B135H296
						if partypoopers>2
							pkmn.forget_move(:THUNDER)
							pkmn.learn_move(:BLAZEKICK)
							pkmn.forget_move(:FLASHCANNON)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire && needfairy
								pkmn.forget_move(:THUNDER)
								pkmn.learn_move(:BLAZEKICK)
								pkmn.forget_move(:DARKPULSE)
								pkmn.learn_move(:TOXIC)
							else
								if needfire
									pkmn.forget_move(:THUNDER)
									pkmn.learn_move(:BLAZEKICK)
								end
								if needfairy
									pkmn.forget_move(:THUNDER)
									pkmn.learn_move(:TOXIC)
								end
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:THUNDER)
								pkmn.learn_move(:BLAZEKICK)
							end
							if needfairy
								pkmn.forget_move(:THUNDER)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B321H377
						if partypoopers>1
							pkmn.item = :LIFEORB
							pkmn.forget_move(:SWORDSDANCE)
							pkmn.learn_move(:WILLOWISP)
						elsif partypoopers>0
							if needfire
								pkmn.item = :LIFEORB
								pkmn.forget_move(:SWORDSDANCE)
								pkmn.learn_move(:FLAREBLITZ)
							end
							if needfairy
								pkmn.item = :LIFEORB
								pkmn.forget_move(:SWORDSDANCE)
								pkmn.learn_move(:WILLOWISP)
							end
						end
					when :B337H237
						if needdark && needfairy
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:TOXIC)
						else
							if needdark
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:THIEF)
							end
							if needfairy
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B355H212
						if partypoopers>0 || needsomething
							pkmn.forget_move(:MACHPUNCH)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B267H62
						if partypoopers>2
							pkmn.forget_move(:ICEPUNCH)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								if needdark
									pkmn.forget_move(:ICEPUNCH)
									pkmn.learn_move(:DARKESTLARIAT)
								end
								if needfairy
									pkmn.forget_move(:ICEPUNCH)
									pkmn.learn_move(:TOXIC)
								end
							else
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:TOXIC)
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:DARKESTLARIAT)
							end
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:DARKESTLARIAT)
							end
							if needfairy
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:TOXIC)
							end
						end
					# Gold
					when :B150H275
						if partypoopers>2
							pkmn.forget_move(:PSYSTRIKE)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								if needdark
									pkmn.forget_move(:PSYSTRIKE)
									pkmn.learn_move(:DARKPULSE)
								end
								if needfairy
									pkmn.forget_move(:PSYSTRIKE)
									pkmn.learn_move(:TOXIC)
								end
							else
								pkmn.forget_move(:FIREBLAST)
								pkmn.learn_move(:TOXIC)
								pkmn.forget_move(:PSYSTRIKE)
								pkmn.learn_move(:DARKPULSE)
							end
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:PSYSTRIKE)
								pkmn.learn_move(:DARKPULSE)
							end
							if needfairy
								pkmn.forget_move(:PSYSTRIKE)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B245H154
						if partypoopers>0 || needsomething
							pkmn.forget_move(:BLIZZARD)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B244H160
						if needdark || needfairy || needsomething
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					when :B243H157
						if needdark || needfairy
							pkmn.item == :LIFEORB
							pkmn.forget_move(:ERUPTION)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B142H250
						if needdark || needfairy || needsomething
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					# Dem
					when :B135H94
						if partypoopers>0 || needsomething
							pkmn.forget_move(:ENERGYBALL)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B309H242
						if partypoopers>2
							pkmn.forget_move(:BULKUP)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								if needdark
									pkmn.forget_move(:DRAINPUNCH)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:DRAINPUNCH)
									pkmn.learn_move(:PLAYROUGH)
								end
							else
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:KNOCKOFF)
								pkmn.forget_move(:DRAINPUNCH)
								pkmn.learn_move(:PLAYROUGH)
							end
						elsif partypoopers>0
							if needdark
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:FIREPUNCH)
								pkmn.learn_move(:PLAYROUGH)
							end
						end
					#when :B169H106 see chuck
					when :B254H381
						if needfairy
							pkmn.forget_move(:AGILITY)
							pkmn.learn_move(:PLAYROUGH)
						end
					when :B262H288
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREPUNCH)
							pkmn.forget_move(:ZENHEADBUTT)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
								if needdark
									pkmn.forget_move(:ZENHEADBUTT)
									pkmn.learn_move(:KNOCKOFF)
								end
								if needfairy
									pkmn.forget_move(:ZENHEADBUTT)
									pkmn.learn_move(:DAZZLINGGLEAM)
								end
							else
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
								pkmn.forget_move(:ZENHEADBUTT)
								pkmn.learn_move(:DAZZLINGGLEAM)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREPUNCH)
							end
							if needdark
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:KNOCKOFF)
							end
							if needfairy
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:DAZZLINGGLEAM)
							end
						end
					when :B208H184
						if partypoopers>2
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:FIREFANG)
							pkmn.forget_move(:ICEPUNCH)
							pkmn.learn_move(:KNOCKOFF)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREFANG)
								if needdark
									pkmn.forget_move(:ICEPUNCH)
									pkmn.learn_move(:KNOCKOFF)
								end
							else
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:KNOCKOFF)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:EARTHQUAKE)
								pkmn.learn_move(:FIREFANG)
							end
							if needdark
								pkmn.forget_move(:ICEPUNCH)
								pkmn.learn_move(:KNOCKOFF)
							end
						end
					when :B195H250
						if needdark || needfairy
							pkmn.forget_move(:STONEEDGE)
							pkmn.learn_move(:WILLOWISP)
						end
					# Final Dem
					when :B150H340
						if partypoopers>0 || needsomething
							pkmn.forget_move(:THUNDER)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B350H242
						if partypoopers>0 || needsomething
							pkmn.ability = :TERAVOLT
							pkmn.forget_move(:HEADBUTT)
							pkmn.learn_move(:FRUSTRATION)
						end
					when :B315H184
						if partypoopers>0
							pkmn.forget_move(:EARTHQUAKE)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B249H343
						if partypoopers>0
							pkmn.item = :LEPPABERRY
							pkmn.forget_move(:AURASPHERE)
							pkmn.learn_move(:HAIL)
						end
					when :B341H250
						if needdark || needfairy || needsomething
							pkmn.forget_move(:ROCKPOLISH)
							pkmn.learn_move(:SUNSTEELSTRIKE)
						end
					# Cynthia
					when :B269H347
						if partypoopers>0
							pkmn.ability == :BADDREAMS
						end
					when :B352H343
						if partypoopers>0 || needsomething
							pkmn.forget_move(:SLUDGEBOMB)
							pkmn.learn_move(:FLASHCANNON)
							pkmn.forget_move(:BLIZZARD)
							pkmn.learn_move(:LEECHSEED)
						end
					when :B275H344
						if partypoopers>2
							pkmn.forget_move(:AGILITY)
							pkmn.learn_move(:FLAMETHROWER)
							pkmn.forget_move(:CALMMIND)
							pkmn.learn_move(:TOXIC)
						elsif partypoopers>1
							if needfire
								pkmn.forget_move(:AGILITY)
								pkmn.learn_move(:FLAMETHROWER)
								if needdark
									pkmn.forget_move(:CALMMIND)
									pkmn.learn_move(:DARKPULSE)
								end
								if needfairy
									pkmn.forget_move(:CALMMIND)
									pkmn.learn_move(:TOXIC)
								end
							else
								pkmn.forget_move(:AGILITY)
								pkmn.learn_move(:DARKPULSE)
								pkmn.forget_move(:CALMMIND)
								pkmn.learn_move(:TOXIC)
							end
						elsif partypoopers>0
							if needfire
								pkmn.forget_move(:AGILITY)
								pkmn.learn_move(:FLAMETHROWER)
							end
							if needdark
								pkmn.forget_move(:AGILITY)
								pkmn.learn_move(:DARKPULSE)
							end
							if needfairy
								pkmn.forget_move(:AGILITY)
								pkmn.learn_move(:TOXIC)
							end
						end
					when :B345H335
						if partypoopers>0
							pkmn.forget_move(:CALMMIND)
							pkmn.learn_move(:WILLOWISP)
						end
					when :B299H315
						if partypoopers>0
							pkmn.forget_move(:THUNDER)
							pkmn.learn_move(:WILLOWISP)
						end

					# Pokemon specific Shedproofing End
					end
				end
    end
  end
end
