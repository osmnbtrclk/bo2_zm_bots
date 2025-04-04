#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_powerups;
#include scripts\zm\zm_bo2_bots_combat;


// Modified bot_spawn to handle Origins map
bot_spawn()
{
    self bot_spawn_init();
    self thread bot_main();
    self thread bot_check_player_blocking();


}

array_combine(array1, array2)
{
    if (!isDefined(array1))
        array1 = [];
    if (!isDefined(array2))
        array2 = [];

    foreach (item in array2)
    {
        array1[array1.size] = item;
    }

    return array1;
}

init()
{
	// level.player_starting_points = 550 * 500;
	bot_set_skill();
	flag_wait("initial_blackscreen_passed");
	if(!isdefined(level.using_bot_weapon_logic))
		level.using_bot_weapon_logic = 1;
	if(!isdefined(level.using_bot_revive_logic))
		level.using_bot_revive_logic = 1;
	bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 3);
	if(bot_amount > (8-get_players().size))
		bot_amount = 8 - get_players().size;
	for(i=0;i<bot_amount;i++)
		spawn_bot();
}

bot_set_skill()
{
	setdvar( "bot_MinDeathTime", "250" );
	setdvar( "bot_MaxDeathTime", "500" );
	setdvar( "bot_MinFireTime", "100" );
	setdvar( "bot_MaxFireTime", "250" );
	setdvar( "bot_PitchUp", "-5" );
	setdvar( "bot_PitchDown", "10" );
	setdvar( "bot_Fov", "160" );
	setdvar( "bot_MinAdsTime", "3000" );
	setdvar( "bot_MaxAdsTime", "5000" );
	setdvar( "bot_MinCrouchTime", "100" );
	setdvar( "bot_MaxCrouchTime", "400" );
	setdvar( "bot_TargetLeadBias", "2" );
	setdvar( "bot_MinReactionTime", "40" );
	setdvar( "bot_MaxReactionTime", "70" );
	setdvar( "bot_StrafeChance", "1" );
	setdvar( "bot_MinStrafeTime", "3000" );
	setdvar( "bot_MaxStrafeTime", "6000" );
	setdvar( "scr_help_dist", "512" );
	setdvar( "bot_AllowGrenades", "1" );
	setdvar( "bot_MinGrenadeTime", "1500" );
	setdvar( "bot_MaxGrenadeTime", "4000" );
	setdvar( "bot_MeleeDist", "70" );
	setdvar( "bot_YawSpeed", "4" );
	setdvar( "bot_SprintDistance", "256" );
}

bot_get_closest_enemy( origin )
{
	enemies = getaispeciesarray( level.zombie_team, "all" );
	enemies = arraysort( enemies, origin );
	if ( enemies.size >= 1 )
	{
		return enemies[ 0 ];
	}
	return undefined;
}

spawn_bot()
{
    bot = addtestclient();
    bot waittill("spawned_player");
    bot thread maps\mp\zombies\_zm::spawnspectator();
    if ( isDefined( bot ) )
    {
        bot.pers[ "isBot" ] = 1;
        bot thread onspawn();
    }
    wait 1;
    bot [[ level.spawnplayer ]]();
}

bot_spawn_init()
{
	if(level.script == "zm_tomb")
	{
		self SwitchToWeapon("c96_zm");
		self SetSpawnWeapon("c96_zm");
	}
	self SwitchToWeapon("m1911_zm");
	self SetSpawnWeapon("m1911_zm");
	time = getTime();
	if ( !isDefined( self.bot ) )
	{
		self.bot = spawnstruct();
		self.bot.threat = spawnstruct();
	}
	self.bot.glass_origin = undefined;
	self.bot.ignore_entity = [];
	self.bot.previous_origin = self.origin;
	self.bot.time_ads = 0;
	self.bot.update_c4 = time + randomintrange( 1000, 3000 );
	self.bot.update_crate = time + randomintrange( 1000, 3000 );
	self.bot.update_crouch = time + randomintrange( 1000, 3000 );
	self.bot.update_failsafe = time + randomintrange( 1000, 3000 );
	self.bot.update_idle_lookat = time + randomintrange( 1000, 3000 );
	self.bot.update_killstreak = time + randomintrange( 1000, 3000 );
	self.bot.update_lookat = time + randomintrange( 1000, 3000 );
	self.bot.update_objective = time + randomintrange( 1000, 3000 );
	self.bot.update_objective_patrol = time + randomintrange( 1000, 3000 );
	self.bot.update_patrol = time + randomintrange( 1000, 3000 );
	self.bot.update_toss = time + randomintrange( 1000, 3000 );
	self.bot.update_launcher = time + randomintrange( 1000, 3000 );
	self.bot.update_weapon = time + randomintrange( 1000, 3000 );
	self.bot.think_interval = 0.1;
	self.bot.fov = -0.9396;
	self.bot.threat.entity = undefined;
	self.bot.threat.position = ( 0, 0, 0 );
	self.bot.threat.time_first_sight = 0;
	self.bot.threat.time_recent_sight = 0;
	self.bot.threat.time_aim_interval = 0;
	self.bot.threat.time_aim_correct = 0;
	self.bot.threat.update_riotshield = 0;
}

bot_main()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );

	self thread bot_wakeup_think();
	self thread bot_damage_think();
	self thread bot_give_ammo();
	self thread bot_reset_flee_goal();
	for ( ;; )
	{
		self waittill( "wakeup", damage, attacker, direction );
		if( self isremotecontrolling())
		{
			continue;
		}
		else
		{
			self bot_combat_think( damage, attacker, direction );
			self bot_update_follow_host();
			self bot_update_lookat();
			self bot_teleport_think();
			if(is_true(level.using_bot_weapon_logic))
			{
				self bot_buy_perks();
				self bot_buy_wallbuy();
				self bot_pack_gun();
				
			}
			if(is_true(level.using_bot_revive_logic))
			{
				self bot_revive_teammates();
			}
			self bot_pickup_powerup();
			self bot_buy_door();  // Added door buying functionality
			self bot_clear_debris();  // Added debris clearing functionality
			// self bot_buy_box();  // Added box buying functionality
			//HIGH PRIORITY: PICKUP POWERUP
			//WHEN GIVING BOTS WEAPONS, YOU MUST USE setspawnweapon() FUNCTION!!!
			//ADD OTHER NON-COMBAT RELATED TASKS HERE (BUYING GUNS, CERTAIN GRIEF MECHANICS)
			//ANYTHING THAT CAN BE DONE WHILE THE BOT IS NOT THREATENED BY A ZOMBIE
		}	
	}
}

bot_buy_perks()
{
    if (!isDefined(self.bot.perk_purchase_time) || GetTime() > self.bot.perk_purchase_time)
    {
        // Only attempt to buy perks every 4 seconds
        self.bot.perk_purchase_time = GetTime() + 4000;
        
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;
            
        perks = array("specialty_armorvest", "specialty_quickrevive", "specialty_fastreload", "specialty_rof");
        costs = array(2500, 1500, 3000, 2000);
        
        // Only get nearby machines within 350 units
        machines = GetEntArray("zombie_vending", "targetname");
        nearby_machines = [];
        foreach(machine in machines)
        {
            if(Distance(machine.origin, self.origin) <= 350)
            {
                nearby_machines[nearby_machines.size] = machine;
            }
        }
        
        // Check each nearby machine
        foreach(machine in nearby_machines)
        {
            if(!isDefined(machine.script_noteworthy))
                continue;
                
            // Find matching perk
            for(i = 0; i < perks.size; i++)
            {
                if(machine.script_noteworthy == perks[i])
                {
                    // Only try to buy if we don't have it and can afford it
                    if(!self HasPerk(perks[i]) && self.score >= costs[i])
                    {
                        self maps\mp\zombies\_zm_score::minus_to_player_score(costs[i]);
                        self thread maps\mp\zombies\_zm_perks::give_perk(perks[i]);
                        return;
                    }
                }
            }
        }
    }
}

bot_best_gun(buyingweapon, currentweapon)
{
    // Priority weapons based on round number
    if(level.round_number >= 15)
    {
        priority_weapons = array("galil_zm", "an94_zm", "pdw57_zm", "mp5k_zm");
        foreach(weapon in priority_weapons)
        {
            if(buyingweapon == weapon)
                return true;
        }
    }
    else if(level.round_number >= 8)
    {
        if(buyingweapon == "pdw57_zm" || buyingweapon == "mp5k_zm")
            return true;
    }
    else
    {
        if(buyingweapon == "mp5k_zm")
            return true;
    }

    // Consider weapon cost as fallback
    if(maps\mp\zombies\_zm_weapons::get_weapon_cost(buyingweapon) > maps\mp\zombies\_zm_weapons::get_weapon_cost(currentweapon))
        return true;
        
    return false;
}

bot_teleport_think()
{
	self endon("death");
	self endon("disconnect");
	level endon("end_game");
	players = get_players();
	if(Distance(self.origin, players[0].origin) > 1500 && players[0] IsOnGround())
	{
		self SetOrigin(players[0].origin + (0,50,0));
	}
}

bot_reset_flee_goal()
{
	self endon("death");
	self endon("disconnect");
	level endon("end_game");
	while(1)
	{
		self CancelGoal("flee");
		wait 2;
	}
}

bot_revive_teammates()
{
	if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand() || self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		self cancelgoal("revive");
		return;
	}
	if(!self hasgoal("revive"))
	{
		teammate = self get_closest_downed_teammate();
		if(!isdefined(teammate))
			return;
		self AddGoal(teammate.origin, 50, 3, "revive");
	}
	else
	{
		if(self AtGoal("revive") || Distance(self.origin, self GetGoal("revive")) < 75)
		{
			teammate = self get_closest_downed_teammate();
			teammate.revivetrigger disable_trigger();
			wait 0.75;
			teammate.revivetrigger enable_trigger();
			if(!self maps\mp\zombies\_zm_laststand::player_is_in_laststand() && teammate maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			{
				teammate maps\mp\zombies\_zm_laststand::auto_revive( self );
			}
		}
	}
}

bot_pickup_powerup()
{
	if(maps\mp\zombies\_zm_powerups::get_powerups(self.origin, 1000).size == 0)
	{
		self CancelGoal("powerup");
		return;
	}
	powerups = maps\mp\zombies\_zm_powerups::get_powerups(self.origin, 1000);
	foreach(powerup in powerups)
	{
		if(FindPath(self.origin, powerup.origin, undefined, 0, 1))
		{
			self AddGoal(powerup.origin, 25, 2, "powerup");
			if(self AtGoal("powerup") || Distance(self.origin, powerup.origin) < 50)
			{
				self CancelGoal("powerup");
			}
			return;
		}
	}
}

bot_check_player_blocking()
{
    self endon("death");
    self endon("disconnect");
    level endon("game_ended");
    
    while(1)
    {
        foreach(player in get_players())
        {
            if(player == self || !isPlayer(player))
                continue;
                
            // Check if bot is too close to player and potentially blocking
            if(Distance(self.origin, player.origin) < 40)
            {
                // Get direction vector from bot to player
                dir = VectorNormalize(self.origin - player.origin);
                
                // Move bot away from player
                new_pos = self.origin + (dir * 50);
                
                // Verify new position is valid before moving
                if(FindPath(self.origin, new_pos, undefined, 0, 1))
                {
                    self SetOrigin(new_pos);
                    // Cancel current goal to prevent bot from moving back
                    if(self hasgoal("doorBuy") || self hasgoal("weaponBuy"))
                    {
                        self cancelgoal(self getgoal("doorBuy") ? "doorBuy" : "weaponBuy");
                    }
                }
            }
        }
        wait 0.1; // Check every 100ms
    }
}

get_closest_downed_teammate()
{
	if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
		return;
	downed_players = [];
	foreach(player in get_players())
	{
		if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		downed_players[downed_players.size] = player;
	}
	downed_players = arraysort(downed_players, self.origin);
	return downed_players[0];

}

bot_pack_gun()
{
	if(level.round_number <= 1)
		return;
	if(!self bot_should_pack())
		return;
	machines = GetEntArray("zombie_vending", "targetname");
	foreach(pack in machines)
	{
		if(pack.script_noteworthy != "specialty_weapupgrade")
			continue;
		if(Distance(pack.origin, self.origin) < 400 && self.score >= 5000 && FindPath(self.origin, pack.origin, undefined, 0, 1))
		{
			self maps\mp\zombies\_zm_score::minus_to_player_score(5000);
			weapon = self GetCurrentWeapon();
			upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon( weapon );
			self TakeAllWeapons();
			self GiveWeapon(upgrade_name);
			self SetSpawnWeapon(upgrade_name);
			return;
		}
	}
}


bot_buy_wallbuy()
{
	self endon("death");
	self endon("disconnect");
	level endon("end_game");
	if(self maps\mp\zombies\_zm_weapons::has_weapon_or_upgrade("mp5k_zm") || self maps\mp\zombies\_zm_weapons::has_weapon_or_upgrade("pdw57_zm") || self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		self CancelGoal("weaponBuy");
		return;
	}
	weapon = self GetCurrentWeapon();
	weaponToBuy = undefined;
	wallbuys = array_randomize(level._spawned_wallbuys);
	foreach(wallbuy in wallbuys)
	{
		if(Distance(wallbuy.origin, self.origin) < 400 && wallbuy.trigger_stub.cost <= self.score && bot_best_gun(wallbuy.trigger_stub.zombie_weapon_upgrade, weapon) && FindPath(self.origin, wallbuy.origin, undefined, 0, 1) && weapon != wallbuy.trigger_stub.zombie_weapon_upgrade && !is_offhand_weapon( wallbuy.trigger_stub.zombie_weapon_upgrade ))
		{
			if(!isdefined(wallbuy.trigger_stub))
				return;
			if(!isdefined(wallbuy.trigger_stub.zombie_weapon_upgrade))
				return;
			weaponToBuy = wallbuy;
			break;
		}
	}
	if(!isdefined(weaponToBuy))
		return;
	self AddGoal(weaponToBuy.origin, 75, 2, "weaponBuy");
	//IPrintLn(weaponToBuy.zombie_weapon_upgrade);
	while(!self AtGoal("weaponBuy") && !Distance(self.origin, weaponToBuy.origin) < 100)
	{
		wait 1;
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			self cancelgoal("weaponBuy");
			return;
		}
	}
	self cancelgoal("weaponBuy");
	self maps\mp\zombies\_zm_score::minus_to_player_score( weaponToBuy.trigger_stub.cost );
	self TakeAllWeapons();
	self GiveWeapon(weaponToBuy.trigger_stub.zombie_weapon_upgrade);
	self SetSpawnWeapon(weaponToBuy.trigger_stub.zombie_weapon_upgrade);
	//IPrintLn("Bot Bought Weapon");
	
}

bot_buy_door()
{
    if (!isDefined(self.bot.door_purchase_time) || GetTime() > self.bot.door_purchase_time)
    {
        // Only attempt to purchase doors every 5 seconds
        self.bot.door_purchase_time = GetTime() + 5000;

        // Get all potential doors
        doors = getEntArray("zombie_door", "targetname");
        
        // Find the closest valid door
        closestDoor = undefined;
        closestDist = 500; // Maximum distance to consider

        foreach(door in doors)
        {
            // Skip if door is already opened
            if(isDefined(door._door_open) && door._door_open)
                continue;
                
            if(isDefined(door.has_been_opened) && door.has_been_opened)
                continue;

            // Set default cost if not defined
            if(!isDefined(door.zombie_cost))
                door.zombie_cost = 1000;

            // Skip doors we can't afford
            if(self.score < door.zombie_cost)
                continue;

            // Handle electric doors
            if(isDefined(door.script_noteworthy))
            {
                if(door.script_noteworthy == "electric_door" || door.script_noteworthy == "local_electric_door")
                {
                    if(!flag("power_on"))
                        continue;
                }
            }

            // Check distance
            dist = Distance(self.origin, door.origin);
            if(dist < closestDist)
            {
                closestDoor = door;
                closestDist = dist;
            }
        }

        // If we found a valid door and we're close enough, try to buy it
        if(isDefined(closestDoor))
        {
            // Deduct points first
            self maps\mp\zombies\_zm_score::minus_to_player_score(closestDoor.zombie_cost);
            
            // Try to call door_buy first, if that function exists on the door
            if(isDefined(closestDoor.door_buy))
            {
                closestDoor thread door_buy();
            }
            // Otherwise fallback to direct door_opened call
            else
            {
                closestDoor thread maps\mp\zombies\_zm_blockers::door_opened(closestDoor.zombie_cost);
            }
            
            // Mark door as opened
            closestDoor._door_open = 1;
            closestDoor.has_been_opened = 1;
            
            // Play purchase sound
            self PlaySound("zmb_cha_ching");
            return true;
        }
    }
    return false;
}

bot_clear_debris()
{
    if (!isDefined(self.bot.debris_purchase_time) || GetTime() > self.bot.debris_purchase_time)
    {
        // Only attempt to clear debris every 4 seconds
        self.bot.debris_purchase_time = GetTime() + 4000;
        
        // Get all potential debris piles
        debris = getEntArray("zombie_debris", "targetname");
        
        if(debris.size == 0)
            return false;
        
        // Find the closest valid debris pile
        closestDebris = undefined;
        closestDist = 500; // Maximum distance to consider
        
        foreach(pile in debris)
        {
            // Skip if pile is not defined
            if(!isDefined(pile))
                continue;
                
            // Skip if origin is not defined
            if(!isDefined(pile.origin))
                continue;
            
            // Skip if debris is already cleared
            if(isDefined(pile._door_open) && pile._door_open)
                continue;
            
            if(isDefined(pile.has_been_opened) && pile.has_been_opened)
                continue;
            
            // Set default cost if not defined
            if(!isDefined(pile.zombie_cost))
                pile.zombie_cost = 1000;
            
            // Skip if we can't afford it
            if(self.score < pile.zombie_cost)
                continue;
            
            // Check distance first
            dist = Distance(self.origin, pile.origin);
            
            // Get nearby nodes for path finding
            nearbyNodes = GetNodesInRadius(pile.origin, 150, 0);
            if(!isDefined(nearbyNodes) || nearbyNodes.size == 0)
            {
                // Try direct path if no nodes found
                if(FindPath(self.origin, pile.origin, undefined, 0, 1))
                    pathFound = true;
                else 
                    continue;
            }
            else
            {
                // Try path to closest node first
                pathFound = false;
                nearbyNodes = ArraySort(nearbyNodes, pile.origin);
                
                foreach(node in nearbyNodes)
                {
                    if(FindPath(self.origin, node.origin, undefined, 0, 1))
                    {
                        pathFound = true;
                        break;
                    }
                }
                
                if(!pathFound)
                {
                    // Try multiple height offsets as fallback
                    offsets = array(0, 30, -30, 50, -50);
                    foreach(offset in offsets)
                    {
                        offsetOrigin = pile.origin + (0, 0, offset);
                        if(FindPath(self.origin, offsetOrigin, undefined, 0, 1))
                        {
                            pathFound = true;
                            break;
                        }
                    }
                }
            }
            
            if(!pathFound)
                continue;
            
            if(dist < closestDist)
            {
                closestDebris = pile;
                closestDist = dist;
            }
        }
        
        // If we found valid debris, try to clear it
        if(isDefined(closestDebris))
        {
            // Move toward the debris if not close enough
            if(closestDist > 300) // Increased interaction range
            {
                self AddGoal(closestDebris.origin, 75, 2, "debrisClear");
                return false;
            }
            
            // Deduct points and clear debris
            self maps\mp\zombies\_zm_score::minus_to_player_score(closestDebris.zombie_cost);
            junk = getentarray(closestDebris.target, "targetname");
            // Mark the debris as cleared
            closestDebris._door_open = 1;
            closestDebris.has_been_opened = 1;
            
            // Try multiple methods to trigger debris removal
            closestDebris notify("trigger", self);
            if(isDefined(closestDebris.trigger))
                closestDebris.trigger notify("trigger", self);
                
            // Activate any associated triggers
            if(isDefined(closestDebris.target))
            {
                targets = GetEntArray(closestDebris.target, "targetname");
                foreach(target in targets)
                {
                    if(isDefined(target))
                    {
                        target notify("trigger", self);
                    }
                }
            }
            
            // Update flags if specified
            if(isDefined(closestDebris.script_flag))
            {
                tokens = strtok(closestDebris.script_flag, ",");
                for(i = 0; i < tokens.size; i++)
                {
                    flag_set(tokens[i]);
                }
            }

            play_sound_at_pos("purchase", closestDebris.origin);
            level notify("junk purchased");

			// Process each piece of debris
            foreach(chunk in junk)
            {
                chunk connectpaths();
                
                if(isDefined(chunk.script_linkto))
                {
                    struct = getstruct(chunk.script_linkto, "script_linkname");
                    if(isDefined(struct))
                    {
                        chunk thread maps\mp\zombies\_zm_blockers::debris_move(struct);
                    }
                    else
                        chunk delete();
                    continue;
                }
                
                chunk delete();
            }

            // Delete the triggers
            all_trigs = getentarray(closestDebris.target, "target");
            foreach(trig in all_trigs)
                trig delete();
            
            // Clean up goals
            if(self hasgoal("debrisClear"))
                self cancelgoal("debrisClear");
            
            // Update stats
            self maps\mp\zombies\_zm_stats::increment_client_stat("doors_purchased");
            self maps\mp\zombies\_zm_stats::increment_player_stat("doors_purchased");
            
            return true;
        }
        
        if(self hasgoal("debrisClear"))
            self cancelgoal("debrisClear");
    }
    return false;
}

bot_buy_box()
{
    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        return;
        
    if(!isDefined(level.chests) || level.chests.size == 0)
        return;
        
    current_box = level.chests[level.chest_index];
    if(!isDefined(current_box))
        return;
    
    dist = Distance(current_box.origin, self.origin);
        
    // Only try to use box if we have enough points and aren't too far
    if(self.score >= 950 && dist < 300)
    {
        // Check if box is available
        if(!is_true(current_box._box_open) && !is_true(current_box._box_opened_by_fire_sale) && !flag("moving_chest_now"))
        {
            if(FindPath(self.origin, current_box.origin, undefined, 0, 1))
            {
                // Move to box if not already there
                if(dist > 75)
                {
                    self AddGoal(current_box.origin, 50, 2, "boxBuy");
                    return;
                }
                
                // Use the box when close enough
                self maps\mp\zombies\_zm_score::minus_to_player_score(950);
                current_box notify("trigger", self);
                
                // Wait for weapon to appear and box to fully open
                wait 4;
                
                // Try to grab weapon multiple times to ensure it's picked up
                for(i = 0; i < 3; i++)
                {
                    if(is_true(current_box._box_open))
                    {
                        current_box notify("trigger", self);
                        self UseButtonPressed();
                        wait 0.5;
                        
                        // Check if weapon was actually taken
                        if(!is_true(current_box._box_open))
                            return;
                    }
                    wait 0.5;
                }
            }
        }
    }
    
    // Clean up any remaining box goal
    if(self hasgoal("boxBuy"))
        self cancelgoal("boxBuy");
}

UseButtonPressed()
{
    if(isDefined(self))
    {
        self notify("use_button_pressed");
        return true;
    }
    return false;
}

activate(user)
{
    if (isDefined(self) && isDefined(user))
    {
        // Example logic for activation
        self notify("trigger_activated", user);
    }
}

bot_should_pack()
{
	if(maps\mp\zombies\_zm_weapons::can_upgrade_weapon(self GetCurrentWeapon()))
		return 1;
	return 0;
}

bot_wakeup_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	for ( ;; )
	{
		wait self.bot.think_interval;
		self notify( "wakeup" );
	}
}

bot_damage_think()
{
	self notify( "bot_damage_think" );
	self endon( "bot_damage_think" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	for ( ;; )
	{
		self waittill( "damage", damage, attacker, direction, point, mod, unused1, unused2, unused3, weapon, flags, inflictor );
		self.bot.attacker = attacker;
		self notify( "wakeup", damage, attacker, direction );
	}
}

bot_give_ammo()
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	for(;;)
	{
		primary_weapons = self GetWeaponsListPrimaries();
		j=0;
		while(j<primary_weapons.size)
		{
			self GiveMaxAmmo(primary_weapons[ j ]);
			j++;
		}
		wait 1;
	}
}

onspawn()
{
	self endon("disconnect");
	level endon("end_game");
	while(1)
	{
		self waittill("spawned_player");
		self thread bot_perks();
		self thread bot_spawn();
	}
}

bot_perks()
{
	self endon("disconnect");
	self endon("death");
	wait 1;
	while(1)
	{
		self SetNormalHealth(250);
		self SetmaxHealth(250);
		self SetPerk("specialty_flakjacket");
		self SetPerk("specialty_rof");
		self SetPerk("specialty_fastreload");
		self waittill("player_revived");
	}
}

bot_update_follow_host()
{
	//goal = self GetGoal("wander");
	//if(distance(goal, self.origin) > 100)
	//	return;
	//if(distance(self.origin, get_players[0].origin) > 3000)
	self AddGoal(get_players()[0].origin, 200, 1, "wander");
	//self lookat(get_players()[0].origin);
	//else
	//	self AddGoal()	
}

bot_update_lookat()
{
	path = 0;
	if ( isDefined( self getlookaheaddir() ) )
	{
		path = 1;
	}
	if ( !path && getTime() > self.bot.update_idle_lookat )
	{
		origin = bot_get_look_at();
		if ( !isDefined( origin ) )
		{
			return;
		}
		self lookat( origin + vectorScale( ( 0, 0, 1 ), 16 ) );
		self.bot.update_idle_lookat = getTime() + randomintrange( 1500, 3000 );
	}
	else if ( path && self.bot.update_idle_lookat > 0 )
	{
		self clearlookat();
		self.bot.update_idle_lookat = 0;
	}
}

bot_get_look_at()
{
	enemy = bot_get_closest_enemy( self.origin );
	if ( isDefined( enemy ) )
	{
		node = getvisiblenode( self.origin, enemy.origin );
		if ( isDefined( node ) && distancesquared( self.origin, node.origin ) > 1024 )
		{
			return node.origin;
		}
	}
	spawn = self getgoal( "wander" );
	if ( isDefined( spawn ) )
	{
		node = getvisiblenode( self.origin, spawn );
	}
	if ( isDefined( node ) && distancesquared( self.origin, node.origin ) > 1024 )
	{
		return node.origin;
	}
	return undefined;
}

bot_update_weapon()
{
	weapon = self GetCurrentWeapon();
	primaries = self getweaponslistprimaries();
	foreach ( primary in primaries )
	{
		if ( primary != weapon )
		{
			self switchtoweapon( primary );
			return;
		}
		i++;
	}
}

bot_update_failsafe()
{
	time = getTime();
	if ( ( time - self.spawntime) < 7500 )
	{
		return;
	}
	if ( time < self.bot.update_failsafe )
	{
		return;
	}
	if ( !self atgoal() && distance2dsquared( self.bot.previous_origin, self.origin ) < 256 )
	{
		nodes = getnodesinradius( self.origin, 512, 0 );
		nodes = array_randomize( nodes );
		nearest = bot_nearest_node( self.origin );
		failsafe = 0;
		if ( isDefined( nearest ) )
		{
			i = 0;
			while ( i < nodes.size )
			{
				if ( !bot_failsafe_node_valid( nearest, nodes[ i ] ) )
				{
					i++;
					continue;
				}
				else
				{
					self botsetfailsafenode( nodes[ i ] );
					wait 0.5;
					self.bot.update_idle_lookat = 0;
					self bot_update_lookat();
					self cancelgoal( "enemy_patrol" );
					self wait_endon( 4, "goal" );
					self botsetfailsafenode();
					self bot_update_lookat();
					failsafe = 1;
					break;
				}
				i++;
			}
		}
		else if ( !failsafe && nodes.size )
		{
			node = random( nodes );
			self botsetfailsafenode( node );
			wait 0.5;
			self.bot.update_idle_lookat = 0;
			self bot_update_lookat();
			self cancelgoal( "enemy_patrol" );
			self wait_endon( 4, "goal" );
			self botsetfailsafenode();
			self bot_update_lookat();
		}
	}
	self.bot.update_failsafe = getTime() + 3500;
	self.bot.previous_origin = self.origin;
}

bot_failsafe_node_valid( nearest, node )
{
	if ( isDefined( node.script_noteworthy ) )
	{
		return 0;
	}
	if ( ( node.origin[ 2 ] - self.origin[ 2 ] ) > 18 )
	{
		return 0;
	}
	if ( nearest == node )
	{
		return 0;
	}
	if ( !nodesvisible( nearest, node ) )
	{
		return 0;
	}
	if ( isDefined( level.spawn_all ) && level.spawn_all.size > 0 )
	{
		spawns = arraysort( level.spawn_all, node.origin );
	}
	else if ( isDefined( level.spawnpoints ) && level.spawnpoints.size > 0 )
	{
		spawns = arraysort( level.spawnpoints, node.origin );
	}
	else if ( isDefined( level.spawn_start ) && level.spawn_start.size > 0 )
	{
		spawns = arraycombine( level.spawn_start[ "allies" ], level.spawn_start[ "axis" ], 1, 0 );
		spawns = arraysort( spawns, node.origin );
	}
	else
	{
		return 0;
	}
	goal = bot_nearest_node( spawns[ 0 ].origin );
	if ( isDefined( goal ) && findpath( node.origin, goal.origin, undefined, 0, 1 ) )
	{
		return 1;
	}
	return 0;
}

bot_nearest_node( origin )
{
	node = getnearestnode( origin );
	if ( isDefined( node ) )
	{
		return node;
	}
	nodes = getnodesinradiussorted( origin, 256, 0, 256 );
	if ( nodes.size )
	{
		return nodes[ 0 ];
	}
	return undefined;
}

