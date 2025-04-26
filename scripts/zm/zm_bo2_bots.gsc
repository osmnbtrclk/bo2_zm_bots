#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_powerups;
#include scripts\zm\zm_bo2_bots_combat;
#include scripts\zm\zm_bo2_bots_utility; // Added include for utility functions


// Bot action constants
#define BOT_ACTION_STAND "stand"
#define BOT_ACTION_CROUCH "crouch"
#define BOT_ACTION_PRONE "prone"

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
    // level.player_starting_points = 550 * 400;
    bot_set_skill();
    
    

    // Add debug
    iprintln("^3Waiting for initial blackscreen...");
    flag_wait("initial_blackscreen_passed");
    iprintln("^2Blackscreen passed, continuing bot setup...");

    if(!isdefined(level.using_bot_weapon_logic))
        level.using_bot_weapon_logic = 1;
    if(!isdefined(level.using_bot_revive_logic))
        level.using_bot_revive_logic = 1;

    // Initialize box and PAP usage variables
    level.box_in_use_by_bot = undefined;
    level.last_bot_box_interaction_time = 0;
    level.pap_in_use_by_bot = undefined;
    level.last_bot_pap_time = 0;
    level.generator_in_use_by_bot = undefined;
    level.last_bot_generator_time = 0;

    // Setup bot tracking array
    if (!isdefined(level.bots))
        level.bots = [];

    bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 8);
    // if(bot_amount > (8-get_players().size))
    //     bot_amount = 8 - get_players().size;

    iprintln("^2Spawning " + bot_amount + " bots...");

    for(i=0; i<bot_amount; i++)
    {
        iprintln("^3Spawning bot " + (i+1));
        // Track spawned bot entities
        bot_entity = spawn_bot();
        level.bots[level.bots.size] = bot_entity;
        wait 1; // Add a brief pause between bot spawns
    }

    // Initialize map specific logic
    if(level.script == "zm_tomb")
    {
        level thread scripts\zm\zm_bo2_bots_origins::init();
    }

    iprintln("^2Bot initialization complete");
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

// New function to handle bot stance actions
botaction(stance)
{
    // Handle different stance actions for the bot
    switch(stance)
    {
        case BOT_ACTION_STAND:
            self allowstand(true);
            self allowcrouch(false);
            self allowprone(false);
            break;
        
        case BOT_ACTION_CROUCH:
            self allowstand(false);
            self allowcrouch(true);
            self allowprone(false);
            break;
            
        case BOT_ACTION_PRONE:
            self allowstand(false);
            self allowcrouch(false);
            self allowprone(true);
            break;
            
        default:
            // Reset to allow all stances
            self allowstand(true);
            self allowcrouch(true);
            self allowprone(true);
            break;
    }
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

bot_buy_box()
{
    // Only try to access the box on a timed interval
    if (!isDefined(self.bot.box_purchase_time) || GetTime() > self.bot.box_purchase_time)
    {
        self.bot.box_purchase_time = GetTime() + 3000; // Try every 3 seconds

        // Don't try if we're in last stand
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;

        // Don't try if we can't afford it
        if(self.score < 950)
            return;
        
        // Check global box usage tracker to prevent multiple bots using box simultaneously
        if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot != self)
        {
            // Another bot is using the box, wait your turn
            return;
        }

        // First check if we can pick up a weapon from an already open box
        if(!isDefined(self.bot.grab_weapon_time) || GetTime() > self.bot.grab_weapon_time)
        {
            activeBox = undefined;
            
            // Find an open box with a weapon ready to grab
            foreach(box in level.chests)
            {
                if(!isDefined(box))
                    continue;
                    
                // Check if the box is open with a weapon ready
                if(isDefined(box._box_open) && box._box_open && 
                   isDefined(box.weapon_out) && box.weapon_out &&
                   isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_model))
                {
                    dist = Distance(self.origin, box.origin);
                    if(dist < 150) // Only attempt if we're close enough
                    {
                        activeBox = box;
                        break;
                    }
                    else if(dist < 500) // Otherwise move closer
                    {
                        // Check for valid path
                        if(FindPath(self.origin, box.origin, undefined, 0, 1))
                        {
                            self AddGoal(box.origin, 75, 3, "boxGrab");
                            return;
                        }
                    }
                }
            }
            
            // If we found an open box with a weapon and we're close enough
            if(isDefined(activeBox))
            {
                // Cancel any existing goal
                if(self hasgoal("boxGrab"))
                    self cancelgoal("boxGrab");
                    
                // Mark that we're trying to grab the weapon
                self.bot.grab_weapon_time = GetTime() + 5000;
                
                // Look at the box with human-like slight aim jitter
                aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
                self lookat(activeBox.origin + aim_offset);
                
                // Wait a bit before grabbing (simulating human reaction time)
                wait randomfloatrange(0.3, 0.8);
                
                // Make sure the box and weapon are still valid after waiting
                if(!isDefined(activeBox) || 
                   !isDefined(activeBox._box_open) || 
                   !activeBox._box_open || 
                   !isDefined(activeBox.weapon_out) || 
                   !activeBox.weapon_out)
                {
                    return;
                }
                
                // Get current weapon for weapon quality comparison
                currentWeapon = self GetCurrentWeapon();
                boxWeapon = activeBox.zbarrier.weapon_string;
                shouldTake = false;
                
                // Weapon decision logic - improved weapon selection
                if(isDefined(boxWeapon))
                {
                    shouldTake = bot_should_take_weapon(boxWeapon, currentWeapon);
                }
                else
                {
                    // If weapon can't be determined, 60% chance to take it
                    shouldTake = (randomfloat(1) < 0.6);
                }
                
                // Simulate grabbing the weapon based on decision
                if(shouldTake)
                {
                    // Try multiple box interaction methods to ensure it works
                    if(isDefined(activeBox.unitrigger_stub) && isDefined(activeBox.unitrigger_stub.trigger))
                    {
                        activeBox.unitrigger_stub.trigger notify("trigger", self);
                    }
                    else if(isDefined(activeBox.zbarrier) && isDefined(activeBox.zbarrier.weapon_string))
                    {
                        // Give weapon directly to avoid box interaction bugs
                        self TakeWeapon(currentWeapon);
                        self GiveWeapon(boxWeapon);
                        self SwitchToWeapon(boxWeapon);
                        self SetSpawnWeapon(boxWeapon);
                        
                        // End the box weapon state
                        if(isDefined(activeBox))
                        {
                            activeBox notify("weapon_grabbed");
                            activeBox.weapon_out = 0;
                        }
                    }
                    else
                    {
                        // Last resort, try to interact with the box directly
                        activeBox notify("trigger", self);
                    }
                    
                    // Set spawn weapon to remember this is our weapon
                    if(isDefined(boxWeapon))
                    {
                        self SetSpawnWeapon(boxWeapon);
                        
                        // Satisfaction feedback for good weapons
                        if(IsSubStr(boxWeapon, "raygun") || IsSubStr(boxWeapon, "thunder"))
                        {
                            // Random celebration for getting a good weapon (crouch/stand)
                            if(randomfloat(1) > 0.5)
                            {
                                self botaction(BOT_ACTION_STAND);
                                wait 0.2;
                                self botaction(BOT_ACTION_CROUCH);
                                wait 0.2;
                                self botaction(BOT_ACTION_STAND);
                            }
                        }
                    }
                    
                    // Play take sound effect
                    self PlaySound("zmb_weap_pickup");
                }
                else
                {
                    // Bot decided to ignore this weapon - wait before trying again
                    self.bot.grab_weapon_time = GetTime() + 7000;
                }
                
                // Set last interaction time to prevent excessive box usage
                self.bot.last_box_interaction_time = GetTime();
                
                // Clear the box user state if we were the one using it
                if(activeBox.chest_user == self)
                    activeBox.chest_user = undefined;
                
                return;
            }
        }

        // If we got here, there was no weapon to grab, so try to open the box
        
        // We need to check if we already paid for the box and it's processing
        if(isDefined(self.bot.waiting_for_box_animation) && self.bot.waiting_for_box_animation)
        {
            // If we've been waiting too long for the box to open, reset state
            if((!isDefined(self.bot.box_payment_time) || (GetTime() - self.bot.box_payment_time > 5000)))
            {
                self.bot.waiting_for_box_animation = undefined;
                self.bot.current_box = undefined;
                // Clear global usage flag if we were the one using it
                if(level.box_in_use_by_bot == self)
                    level.box_in_use_by_bot = undefined;
            }
            else
            {
                // Still waiting for animation, don't try to buy again
                return;
            }
        }

        // Check global cooldown to prevent box from moving too quickly
        if(isDefined(level.last_bot_box_interaction_time) && (GetTime() - level.last_bot_box_interaction_time < 30000))
            return;
            
        // Personal cooldown to prevent the same bot from constantly using the box
        if(isDefined(self.bot.last_box_interaction_time) && (GetTime() - self.bot.last_box_interaction_time < 15000))
            return;

        // Make sure boxes exist
        if(!isDefined(level.chests) || level.chests.size == 0)
            return;

        closestBox = undefined;
        closestDist = 99999;

        // Find the nearest accessible box
        foreach(box in level.chests)
        {
            if(!isDefined(box) || !isDefined(box.origin))
                continue;
                
            // Skip locked boxes
            if(isDefined(box.is_locked) && box.is_locked)
                continue;

            // Skip boxes that are already open
            if(isDefined(box._box_open) && box._box_open)
                continue;
                
            // Skip boxes already in use
            if(isDefined(box.chest_user) && box.chest_user != self)
                continue;

            // Only use the active box or fire sale boxes
            if(box == level.chests[level.chest_index] || 
               (isDefined(level.zombie_vars["zombie_powerup_fire_sale_on"]) && 
                level.zombie_vars["zombie_powerup_fire_sale_on"] == 1))
            {
                dist = Distance(self.origin, box.origin);
                if(dist < closestDist)
                {
                    closestBox = box;
                    closestDist = dist;
                }
            }
        }

        // If no valid box was found or it's too far away
        if(!isDefined(closestBox) || closestDist > 500)
            return;

        // Move closer if not already near the box
        if(closestDist > 100)
        {
            // Check for valid path
            if(FindPath(self.origin, closestBox.origin, undefined, 0, 1))
            {
                self AddGoal(closestBox.origin, 75, 2, "boxBuy");
                return;
            }
        }
        
        // Look at the box with slight aim jitter
        aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
        self lookat(closestBox.origin + aim_offset);

        // Wait a bit before purchase to mimic human reaction
        wait randomfloatrange(0.5, 1.0);

        // Check again if the box is still valid after waiting
        if(!isDefined(closestBox) || 
           (isDefined(closestBox._box_open) && closestBox._box_open) || 
           self maps\mp\zombies\_zm_laststand::player_is_in_laststand() || 
           self.score < 950)
            return;

        // Cancel current goal to prevent movement during interaction
        if(self hasgoal("boxBuy"))
            self cancelgoal("boxBuy");

        // Set global box usage flag to prevent other bots from using the box simultaneously
        level.box_in_use_by_bot = self;
        
        // Store the box we're using to check for successful activation
        self.bot.current_box = closestBox;
        self.bot.waiting_for_box_animation = true;
        self.bot.box_payment_time = GetTime();
        
        // Set the player as the box user
        closestBox.chest_user = self;
        
        // Deduct points AFTER we've verified everything is good to go
        self maps\mp\zombies\_zm_score::minus_to_player_score(950);

        // Try all possible ways to trigger the box properly
        if(isDefined(closestBox.unitrigger_stub) && isDefined(closestBox.unitrigger_stub.trigger))
        {
            closestBox.unitrigger_stub.trigger notify("trigger", self);
        }
        else if(isDefined(closestBox.zbarrier))
        {
            // Force the chest to start thinking
            closestBox notify("trigger", self);
            
            // Directly start the box logic in case the trigger didn't work
            closestBox thread maps\mp\zombies\_zm_magicbox::treasure_chest_think();
        }
        else
        {
            // Try all common trigger methods as a last resort
            if(isDefined(closestBox.use_trigger))
                closestBox.use_trigger notify("trigger", self);
                
            closestBox notify("trigger", self);
            closestBox notify("open_chest_trigger", self);
        }

        // Play purchase sound effect
        self PlaySound("zmb_cha_ching");
        
        // Set cooldown times
        self.bot.last_box_interaction_time = GetTime();
        level.last_bot_box_interaction_time = GetTime();
        
        // Start monitoring the box to see if it opened
        self thread bot_monitor_box_animation(closestBox);
    }
}

bot_monitor_box_animation(box)
{
    self endon("disconnect");
    self endon("death");
    
    // Make sure this bot is removed from the usage tracker when done or disconnected
    self endon("box_usage_complete");
    
    // Wait for the box to start opening animation
    started = false;
    
    // Check for up to 3 seconds
    for(i = 0; i < 15; i++) 
    {
        wait 0.2;
        
        // Box is no longer valid
        if(!isDefined(box))
        {
            self.bot.waiting_for_box_animation = undefined;
            self.bot.current_box = undefined;
            // Clear global usage flag when done
            if(level.box_in_use_by_bot == self)
                level.box_in_use_by_bot = undefined;
            self notify("box_usage_complete");
            return;
        }
        
        // Box has started opening
        if(isDefined(box._box_open) && box._box_open)
        {
            started = true;
            // Stay in the monitoring loop to wait for weapon
            break;
        }
    }
    
    // Box animation didn't start after payment
    if(!started)
    {
        self.bot.waiting_for_box_animation = undefined;
        self.bot.current_box = undefined;
        // Clear global usage flag when done
        if(level.box_in_use_by_bot == self)
            level.box_in_use_by_bot = undefined;
        self notify("box_usage_complete");
        return;
    }
    
    // Now wait for the weapon to appear
    weaponAppeared = false;
    
    // Wait up to 6 more seconds for the weapon
    for(i = 0; i < 30; i++)
    {
        wait 0.2;
        
        // Box is no longer valid or has closed
        if(!isDefined(box) || !isDefined(box._box_open) || !box._box_open)
        {
            self.bot.waiting_for_box_animation = undefined;
            self.bot.current_box = undefined;
            // Clear global usage flag when done
            if(level.box_in_use_by_bot == self)
                level.box_in_use_by_bot = undefined;
            self notify("box_usage_complete");
            return;
        }
        
        // Check if the weapon is ready
        if(isDefined(box.weapon_out) && box.weapon_out && 
           isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_model))
        {
            weaponAppeared = true;
            break;
        }
        
        // Check if the box is showing a teddy bear
        if(isDefined(box.zbarrier) && isDefined(box.zbarrier.state) && box.zbarrier.state == "teddy_bear")
        {
            // Remember this position had a teddy to prevent future use
            if(!isDefined(level.mystery_box_teddy_locations))
                level.mystery_box_teddy_locations = [];
                
            if(!array_contains(level.mystery_box_teddy_locations, box.origin))
                level.mystery_box_teddy_locations[level.mystery_box_teddy_locations.size] = box.origin;
                
            // No weapon is coming, so exit
            self.bot.waiting_for_box_animation = undefined;
            self.bot.current_box = undefined;
            if(level.box_in_use_by_bot == self)
                level.box_in_use_by_bot = undefined;
            self notify("box_usage_complete");
            return;
        }
    }
    
    // Clear waiting flags
    self.bot.waiting_for_box_animation = undefined;
    
    // If weapon didn't appear, stop monitoring
    if(!weaponAppeared)
    {
        self.bot.current_box = undefined;
        // Clear global usage flag when done
        if(level.box_in_use_by_bot == self)
            level.box_in_use_by_bot = undefined;
        self notify("box_usage_complete");
        return;
    }
    
    // Wait a random amount of time before grabbing
    wait randomfloatrange(0.5, 1.5);
    
    // Make sure the box and player are still valid
    if(!isDefined(box) || 
       !isDefined(box._box_open) || 
       !box._box_open ||
       !isDefined(box.weapon_out) ||
       !box.weapon_out ||
       self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
        self.bot.current_box = undefined;
        // Clear global usage flag when done
        if(level.box_in_use_by_bot == self)
            level.box_in_use_by_bot = undefined;
        self notify("box_usage_complete");
        return;
    }
    
    // Get weapon info for decision making
    boxWeapon = undefined;
    if(isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_string))
    {
        boxWeapon = box.zbarrier.weapon_string;
    }
    
    currentWeapon = self GetCurrentWeapon();
    shouldTake = bot_should_take_weapon(boxWeapon, currentWeapon);
    
    // Look at the box again with slight jitter
    aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
    self lookat(box.origin + aim_offset);
    
    // Try to grab the weapon based on decision
    if(shouldTake)
    {
        // Try direct weapon give first (most reliable)
        if(isDefined(boxWeapon))
        {
            // First make sure we don't already have this weapon
            if(!self HasWeapon(boxWeapon))
            {
                // Get current weapons
                primaries = self GetWeaponsListPrimaries();
                
                // If we have two primaries, drop one
                if(primaries.size >= 2)
                {
                    // Keep the best weapon (never drop raygun/wonder weapons)
                    dropWeapon = currentWeapon;
                    foreach(weapon in primaries)
                    {
                        if(weapon != currentWeapon && 
                           !IsSubStr(weapon, "raygun") && 
                           !IsSubStr(weapon, "thunder") && 
                           !IsSubStr(weapon, "wave") && 
                           !IsSubStr(weapon, "tesla"))
                        {
                            dropWeapon = weapon;
                            break;
                        }
                    }
                    
                    // Drop the selected weapon
                    self TakeWeapon(dropWeapon);
                }
                
                // Give the new box weapon
                self GiveWeapon(boxWeapon);
                self SwitchToWeapon(boxWeapon);
                self SetSpawnWeapon(boxWeapon);
                
                // Mark the box as grabbed
                box.weapon_out = 0;
                box notify("weapon_grabbed");
                
                // Satisfaction feedback - bot might prone or spin if got a good weapon
                if(IsSubStr(boxWeapon, "raygun") || IsSubStr(boxWeapon, "thunder"))
                {
                    // Random celebration for getting a good weapon
                    if(randomfloat(1) > 0.5)
                    {
                        self botaction(BOT_ACTION_STAND);
                        wait 0.2;
                        self botaction(BOT_ACTION_CROUCH);
                        wait 0.2;
                        self botaction(BOT_ACTION_STAND);
                    }
                }
                
                // Play take sound effect
                self PlaySound("zmb_weap_pickup");
            }
        }
        else
        {
            // Fallback to traditional trigger methods
            if(isDefined(box.unitrigger_stub) && isDefined(box.unitrigger_stub.trigger))
            {
                box.unitrigger_stub.trigger notify("trigger", self);
            }
            else
            {
                box notify("trigger", self);
            }
        }
    }
    
    // Clear the reference to this box
    self.bot.current_box = undefined;
    
    // Clear box user reference
    if(isDefined(box.chest_user) && box.chest_user == self)
        box.chest_user = undefined;
    
    // Clear global usage flag when done
    if(level.box_in_use_by_bot == self)
        level.box_in_use_by_bot = undefined;
    
    self notify("box_usage_complete");
}

spawn_bot()
{
    iprintln("^3Adding test client...");
    bot = addtestclient();
    if(!isDefined(bot))
    {
        iprintln("^1Failed to add test client!");
        return;
    }
    
    iprintln("^3Waiting for bot to spawn...");
    bot waittill("spawned_player");
    iprintln("^2Bot spawned, configuring...");
    
    bot thread maps\mp\zombies\_zm::spawnspectator();
    if(isDefined(bot))
    {
        bot.pers["isBot"] = 1;
        bot thread onspawn();
    }
    
    wait 1;
    iprintln("^3Spawning bot as player...");
    
    if(isDefined(level.spawnplayer))
        bot [[level.spawnplayer]]();
    else
        iprintln("^1ERROR: level.spawnplayer not defined!");
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
	// self thread bot_give_ammo();
	self thread bot_reset_flee_goal();
    self thread bot_manage_ammo();
    // If on Origins map, handle generator purchases
    if (level.script == "zm_tomb")
        self thread bot_origins_think();
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
			self bot_buy_box();  // Added box buying functionality

			// Add Origins specific generator activation
			if(level.script == "zm_tomb")
			{
				self thread scripts\zm\zm_bo2_bots_origins::bot_activate_generator();
			}
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
            
        perks = array("specialty_armorvest", "specialty_quickrevive", "specialty_fastreload", "specialty_rof", "specialty_longersprint", "specialty_deadshot","specialty_additionalprimaryweapon");
        costs = array(2500, 1500, 3000, 2000, 2000, 1500, 4000);
        
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
	if(players.size == 0) // Ensure there's at least one player
		return;

	// Get the host player or first player as reference
	host_player = undefined;
	foreach(player in players)
	{
		if(player != self && !player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			host_player = player;
			break;
		}
	}
	
	if(!isDefined(host_player))
		return;
		
	// Check if bot is too far from host
	if(Distance(self.origin, host_player.origin) > 1500 && host_player IsOnGround())
	{
		// Try to find a valid node near the host player
		safe_node = GetNearestNode(host_player.origin);
		
		if(isDefined(safe_node))
		{
			// Check if node is on navmesh and accessible
			if(NodeVisible(safe_node.origin, host_player.origin))
			{
				// Teleport to the safe node
				self SetOrigin(safe_node.origin);
				// Make bot look at the player
				self SetPlayerAngles(VectorToAngles(host_player.origin - self.origin));
				//iprintln("^3Bot teleported to safe node");
				return;
			}
		}
		
		// If no safe node found, try to find any valid position near the player
		test_positions = array();
		test_positions[0] = host_player.origin + (50, 0, 0);
		test_positions[1] = host_player.origin + (0, 50, 0);
		test_positions[2] = host_player.origin + (-50, 0, 0);
		test_positions[3] = host_player.origin + (0, -50, 0);
		
		foreach(pos in test_positions)
		{
			// Try to find a path to validate the position
			if(SightTracePassed(pos, pos + (0, 0, 50), false, undefined) && 
			   !SightTracePassed(pos, pos - (0, 0, 50), false, undefined))
			{
				// Position is valid - above ground but not inside ceiling
				self SetOrigin(pos);
				self SetPlayerAngles(VectorToAngles(host_player.origin - self.origin));
				//iprintln("^3Bot teleported to offset position");
				return;
			}
		}
		
		// Last resort - teleport directly to player with small height offset
		// This is risky but better than being stuck far away
		self SetOrigin(host_player.origin + (0, 0, 5));
		//iprintln("^1Bot teleported directly to player (fallback)");
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
        wait 0.15; // Slightly reduced check frequency for better performance
        
        // Skip checks if bot is in last stand
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            continue;
            
        foreach(player in get_players())
        {
            if(player == self || !isPlayer(player) || player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
                continue;
                
            // Check if bot is too close to player and potentially blocking
            distance_sq = DistanceSquared(self.origin, player.origin);
            if(distance_sq < 1600) // Square of 40
            {
                // Calculate direction to move away from player
                dir = VectorNormalize(self.origin - player.origin);
                
                // Try different ways to move the bot away safely
                // Method 1: Use AddGoal to navigate properly
                if(!self hasgoal("avoid_player"))
                {
                    // Try to find a valid position in the direction away from player
                    try_pos = self.origin + (dir * 60);
                    
                    // Check for valid path to new position
                    if(FindPath(self.origin, try_pos, undefined, 0, 1))
                    {
                        self AddGoal(try_pos, 20, 2, "avoid_player"); // Higher priority
                        wait 0.5; // Give bot time to start moving
                        continue;
                    }
                    
                    // Method 2: Look for nearby node if direct movement failed
                    nearest_node = GetNearestNode(self.origin);
                    if(isDefined(nearest_node))
                    {
                        // Try to find nodes away from the player
                        nodes = GetNodesInRadius(self.origin, 200, 0);
                        best_node = undefined;
                        best_dist = 0;
                        
                        if(isDefined(nodes) && nodes.size > 0)
                        {
                            foreach(node in nodes)
                            {
                                // Calculate which node is furthest from player but still reachable
                                if(NodeVisible(nearest_node.origin, node.origin))
                                {
                                    node_to_player_dist = Distance(node.origin, player.origin);
                                    if(node_to_player_dist > best_dist)
                                    {
                                        best_node = node;
                                        best_dist = node_to_player_dist;
                                    }
                                }
                            }
                            
                            // If we found a good node, move there
                            if(isDefined(best_node))
                            {
                                self AddGoal(best_node.origin, 20, 2, "avoid_player");
                                wait 0.5; // Give bot time to start moving
                                continue;
                            }
                        }
                    }
                    
                    // Method 3 (fallback): Small teleport as last resort, but only if on ground
                    if(self IsOnGround())
                    {
                        // Verify new position is valid before moving
                        new_pos = self.origin + (dir * 50);
                        
                        // Do trace checks to make sure we're not teleporting into walls
                        if(!SightTracePassed(new_pos, new_pos + (0, 0, 30), true, self) && 
                           SightTracePassed(new_pos, new_pos - (0, 0, 50), false, self))
                        {
                            // Cancel any door/weapon purchase goals to prevent getting stuck again
                            goal_names = array("doorBuy", "weaponBuy", "boxBuy", "papBuy");
                            foreach(goal_name in goal_names)
                            {
                                if(self hasgoal(goal_name))
                                    self cancelgoal(goal_name);
                            }
                            
                            // Teleport as last resort
                            self SetOrigin(new_pos);
                        }
                    }
                }
            }
            else
            {
                // If far enough, cancel avoid goal
                if(self hasgoal("avoid_player"))
                    self cancelgoal("avoid_player");
            }
        }
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
	// Only attempt if we're past round 1
	if(level.round_number <= 1)
		return;
	
	// Check if we have a valid weapon to upgrade
	if(!self bot_should_pack())
		return;
		
	// Prevent multiple bots from using PaP simultaneously
	if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot != self)
		return;
		
	// Only check periodically, not every frame
	if(!isDefined(self.bot.pap_check_time) || GetTime() > self.bot.pap_check_time)
	{
		self.bot.pap_check_time = GetTime() + 5000; // Check every 5 seconds
		
		// Global cooldown across all bots
		if(isDefined(level.last_bot_pap_time) && GetTime() - level.last_bot_pap_time < 40000)
			return;
			
		// Personal cooldown
		if(isDefined(self.bot.last_pap_time) && GetTime() - self.bot.last_pap_time < 30000)
			return;
		
		// Find Pack-a-Punch machine
		machines = GetEntArray("zombie_vending", "targetname");
		closestPap = undefined;
		closestDist = 500; // Maximum detection range
		
		foreach(pack in machines)
		{
			if(pack.script_noteworthy != "specialty_weapupgrade")
				continue;
				
			// Check if PaP machine is currently available
			if(isDefined(pack.is_locked) && pack.is_locked)
				continue;
				
			// Check if another player is using it
			if(isDefined(pack.pap_user) && pack.pap_user != self)
				continue;
				
			dist = Distance(self.origin, pack.origin);
			if(dist < closestDist)
			{
				closestPap = pack;
				closestDist = dist;
			}
		}
		
		// If no valid Pack-a-Punch found or too far away
		if(!isDefined(closestPap))
			return;
			
		// Move closer if not already near the machine
		if(closestDist > 100)
		{
			// Check for valid path
			if(FindPath(self.origin, closestPap.origin, undefined, 0, 1))
			{
				if(!self hasgoal("papBuy") || Distance(self GetGoal("papBuy"), closestPap.origin) > 50)
					self AddGoal(closestPap.origin, 50, 2, "papBuy");
				return;
			}
		}
		
		// Cancel movement goal when we arrive
		if(self hasgoal("papBuy"))
			self cancelgoal("papBuy");
			
		// Check if we still have sufficient points
		if(self.score < 5000)
			return;
			
		// Look at the PaP with slight aim jitter (more realistic)
		aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
		self lookat(closestPap.origin + aim_offset);
		
		// Wait a bit before interacting (human-like hesitation)
		wait randomfloatrange(0.3, 0.8);
		
		// Mark this bot as using the PaP
		level.pap_in_use_by_bot = self;
		closestPap.pap_user = self;
		
		// Update cooldown times
		self.bot.last_pap_time = GetTime();
		level.last_bot_pap_time = GetTime();
		
		// Deduct points
		self maps\mp\zombies\_zm_score::minus_to_player_score(5000);
		
		// Get current weapon before upgrading
		weapon = self GetCurrentWeapon();
		upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(weapon);
		
		// Play animation of putting weapon in
		self PlaySound("zmb_cha_ching");
		
		// Properly trigger the Pack-a-Punch machine
		if(isDefined(closestPap.unitrigger_stub) && isDefined(closestPap.unitrigger_stub.trigger))
		{
			closestPap.unitrigger_stub.trigger notify("trigger", self);
		}
		else if(isDefined(closestPap.use_trigger))
		{
			closestPap.use_trigger notify("trigger", self);
		}
		else
		{
			// Fallback interaction
			closestPap notify("trigger", self);
		}
		
		// Start the upgrade process monitoring thread
		self thread bot_monitor_pap_upgrade(closestPap, weapon, upgrade_name);
	}
}

// New function to monitor the Pack-a-Punch upgrade process
bot_monitor_pap_upgrade(pap_machine, old_weapon, upgrade_name)
{
	self endon("disconnect");
	self endon("death");
	self endon("pap_complete");
	
	// Simulate upgrade time (5-6 seconds like the real game)
	wait randomfloatrange(5, 6);
	
	// Make sure we're still valid and in appropriate state
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		// Clear usage flags
		if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot == self)
			level.pap_in_use_by_bot = undefined;
		
		if(isDefined(pap_machine.pap_user) && pap_machine.pap_user == self)
			pap_machine.pap_user = undefined;
			
		self notify("pap_complete");
		return;
	}
	
	// Take weapon and give upgraded version
	self TakeWeapon(old_weapon);
	self GiveWeapon(upgrade_name);
	self SetSpawnWeapon(upgrade_name);
	self SwitchToWeapon(upgrade_name);
	
	// Look at the machine again to grab the weapon
	aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
	self lookat(pap_machine.origin + aim_offset);
	
	// Play pickup sound for upgraded weapon
	self PlaySound("zmb_weap_pickup");
	
	// Celebrate getting a Pack-a-Punched weapon (chance-based)
	if(randomfloat(1) > 0.6)
	{
		// Celebration actions - crouch/stand or spin around
		if(randomfloat(1) > 0.5)
		{
			self botaction(BOT_ACTION_STAND);
			wait 0.2;
			self botaction(BOT_ACTION_CROUCH);
			wait 0.2;
			self botaction(BOT_ACTION_STAND);
		}
	}
	
	// Clear usage flags
	if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot == self)
		level.pap_in_use_by_bot = undefined;
	
	if(isDefined(pap_machine.pap_user) && pap_machine.pap_user == self)
		pap_machine.pap_user = undefined;
		
	self notify("pap_complete");
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
		if(Distance(wallbuy.origin, self.origin) < 400 && wallbuy.trigger_stub.cost <= self.score && bot_best_gun(wallbuy.trigger_stub.zombie_weapon_upgrade, weapon) && FindPath(self.origin, wallbuy.origin, undefined, 0, 1) && weapon != wallbuy.trigger_stub.zombie_weapon_upgrade && !is_offhand_weapon( wallbuy.trigger_stub.zombie_weapon_upgrade  ))
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
        closestDist = 300; // Reduced max distance for realism

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
            // Add human-like hesitation
            if(randomfloat(1) < 0.15)
            {
                wait randomfloatrange(0.5, 1.0);
                return true;
            }

            aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), 0);
            self lookat(closestDoor.origin + aim_offset);
            wait randomfloatrange(0.5, 1.5);

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
        closestDist = 300; // Reduced max distance for realism
        
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
                nearbyNodes = ArraySort(nearbyNodes, pile.origin );
                
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
            if(closestDist > 150) // Reduced interaction range
            {
                self AddGoal(closestDebris.origin, 50, 2, "debrisClear");
                return false;
            }

            // Add human-like hesitation
            if(randomfloat(1) < 0.15)
            {
                wait randomfloatrange(0.5, 1.0);
                return true;
            }

            aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), 0);
            self lookat(closestDebris.origin + aim_offset);
            wait randomfloatrange(0.5, 1.5);
            
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
		self waittill( "damage", damage, attacker, direction, point, mod, unused1, unused2, unused3, unused4, weapon, flags, inflictor );
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
	
	// Clean up box usage if this bot disconnects
    self thread bot_cleanup_on_disconnect();
	
	while(1)
	{
		self waittill("spawned_player");
		self thread bot_perks();
		self thread bot_spawn();
	}
}

// New function to clean up resources when a bot disconnects
bot_cleanup_on_disconnect()
{
    self waittill("disconnect");
    
    // If this bot was using the box, clear the flag
    if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot == self)
    {
        level.box_in_use_by_bot = undefined;
    }
    
    // If this bot was using the PaP, clear the flag
    if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot == self)
    {
        level.pap_in_use_by_bot = undefined;
    }
    
    // Clear any PaP machine connections
    machines = GetEntArray("zombie_vending", "targetname");
    foreach(machine in machines)
    {
        if(isDefined(machine.pap_user) && machine.pap_user == self)
        {
            machine.pap_user = undefined;
        }
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
	self AddGoal(get_players()[0].origin, 100, 1, "wander");
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

// Improved weapon selection logic
bot_should_take_weapon(boxWeapon, currentWeapon)
{
    if(!isDefined(boxWeapon))
        return false;
    
    // Check if we already have this weapon
    if(self HasWeapon(boxWeapon))
        return false;
        
    // Always take wonder weapons
    if(IsSubStr(boxWeapon, "raygun") || 
       IsSubStr(boxWeapon, "thunder") || 
       IsSubStr(boxWeapon, "wave") || 
       IsSubStr(boxWeapon, "mark2") || 
       IsSubStr(boxWeapon, "tesla"))
    {
        return true;
    }
    
    // Define weapon tiers for better decision making
    tier1_weapons = array("raygun_", "thunder", "wave_gun", "mark2", "tesla");
    tier2_weapons = array("galil", "an94", "hamr", "rpd", "lsat", "dsr50");
    tier3_weapons = array("mp5k", "pdw57", "mtar", "mp40", "ak74u", "qcw05");
    tier4_weapons = array("m14", "870mcs", "r870", "olympia", "fnfal");
    
    // Track if current weapon is in specific tier
    currentIsTier1 = false;
    currentIsTier2 = false;
    currentIsTier3 = false;
    
    // Check current weapon tier
    foreach(weapon in tier1_weapons)
    {
        if(IsSubStr(currentWeapon, weapon))
        {
            currentIsTier1 = true;
            break;
        }
    }
    
    if(!currentIsTier1)
    {
        foreach(weapon in tier2_weapons)
        {
            if(IsSubStr(currentWeapon, weapon))
            {
                currentIsTier2 = true;
                break;
            }
        }
    }
    
    if(!currentIsTier1 && !currentIsTier2)
    {
        foreach(weapon in tier3_weapons)
        {
            if(IsSubStr(currentWeapon, weapon))
            {
                currentIsTier3 = true;
                break;
            }
        }
    }
    
    // Don't take bad weapons like snipers or launchers (with small chance for variety)
    if(IsSubStr(boxWeapon, "sniper") || 
       IsSubStr(boxWeapon, "launcher") || 
       IsSubStr(boxWeapon, "knife") || 
       (IsSubStr(boxWeapon, "ballistic") && !IsSubStr(boxWeapon, "ballistic_knife")))

    {
        return (randomfloat(1) < 0.15); // 15% chance
    }
    
    // Check box weapon tier
    boxIsTier2 = false;
    boxIsTier3 = false;
    boxIsTier4 = false;
    
    foreach(weapon in tier2_weapons)
    {
        if(IsSubStr(boxWeapon, weapon))
        {
            boxIsTier2 = true;
            break;
        }
    }
    
    if(!boxIsTier2)
    {
        foreach(weapon in tier3_weapons)
        {
            if(IsSubStr(boxWeapon, weapon))
            {
                boxIsTier3 = true;
                break;
            }
        }
    }
    
    if(!boxIsTier2 && !boxIsTier3)
    {
        foreach(weapon in tier4_weapons)
        {
            if(IsSubStr(boxWeapon, weapon))
            {
                boxIsTier4 = true;
                break;
            }
        }
    }
    
    // Decision logic based on tiers and round number
    if(currentIsTier1)
    {
        // Already have a wonder weapon, only take another if it's a different one
        // For example, allow taking thunder gun when already having raygun
        foreach(weapon in tier1_weapons)
        {
            if(IsSubStr(boxWeapon, weapon) && !IsSubStr(currentWeapon, weapon))
            {
                // 70% chance to take another wonder weapon
                return (randomfloat(1) < 0.7);
            }
        }
        return false; // Don't replace wonder weapon with non-wonder weapon
    }
    
    // Have tier 2 weapon already
    if(currentIsTier2)
    {
        if(boxIsTier2)
        {
            // 50% chance to swap between tier 2 weapons for variety
            return (randomfloat(1) < 0.5);
        }
        else if(boxIsTier3 || boxIsTier4)
        {
            // Almost never downgrade from tier 2
            return (randomfloat(1) < 0.1);
        }
        // For unclassified weapons, low chance
        return (randomfloat(1) < 0.2);
    }
    
    // Have tier 3 weapon already
    if(currentIsTier3)
    {
        if(boxIsTier2)
        {
            // Always upgrade to tier 2
            return true;
        }
        else if(boxIsTier3)
        {
            // 60% chance to swap between tier 3 for variety
            return (randomfloat(1) < 0.6);
        }
        else if(boxIsTier4)
        {
            // Don't downgrade
            return (randomfloat(1) < 0.15);
        }
    }
    
    // Round-based logic - in early rounds take most weapons
    if(level.round_number <= 5)
    {
        return true;
    }
    // Mid rounds - prefer at least tier 3
    else if(level.round_number <= 15)
    {
        if(boxIsTier2 || boxIsTier3)
            return true;
        else
            return (randomfloat(1) < 0.5); // 50% chance for other weapons
    }
    // Late rounds - generally only take tier 2
    else
    {
        if(boxIsTier2)
            return true;
        else if(boxIsTier3)
            return (randomfloat(1) < 0.7); // 70% chance for tier 3
        else
            return (randomfloat(1) < 0.3); // 30% chance for other weapons
    }
    
    // Default case - 50/50 chance
    return (randomfloat(1) < 0.5);
}


// Helper function to get Dvar value with a default
GetDvarIntDefault(dvarName, defaultValue)
{
    if(GetDvar(dvarName) == "")
        return defaultValue;
    return GetDvarInt(dvarName);
}

// Main function to manage bot ammo based on Dvar setting
bot_manage_ammo()
{
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");

    // Wait for the bot to be fully initialized
    wait 1;

    // Dvar to control infinite ammo (1 = enabled, 0 = disabled)
    // Default to enabled (1) if Dvar is not set
    infinite_ammo_enabled = GetDvarIntDefault("bo2_zm_bots_infinite_ammo", 0);

    if (infinite_ammo_enabled == 1)
    {
        // If infinite ammo is enabled, run the max ammo loop
        self thread bot_give_max_ammo_loop();
    }
    else
    {
        // If infinite ammo is disabled, run the ammo buying loop
        self thread bot_buy_ammo_loop();
    }
}

// Loop to continuously give max ammo if infinite ammo is enabled
bot_give_max_ammo_loop()
{
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");

    while(true)
    {
        primary_weapons = self GetWeaponsListPrimaries();
        foreach(weapon in primary_weapons)
        {
            // Only give ammo to non-wonder weapons to avoid potential issues
            if (!IsSubStr(weapon, "raygun") && !IsSubStr(weapon, "thunder") &&
                !IsSubStr(weapon, "wave") && !IsSubStr(weapon, "mark2") &&
                !IsSubStr(weapon, "tesla") && !IsSubStr(weapon, "staff")) // Add other wonder weapons if needed
            {
                self GiveMaxAmmo(weapon);
            }
        }
        wait 1; // Check every second
    }
}

// Loop for bots to buy ammo from wall weapons if infinite ammo is disabled
bot_buy_ammo_loop()
{
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");

    // Debug: Confirm the loop started for this bot
    // iprintln("^5DEBUG: " + self.name + " started bot_buy_ammo_loop");

    while(true)
    {
        // Check periodically
        wait randomfloatrange(3.0, 5.0);

        // Debug: Check if the loop is still running
        // iprintln("^5DEBUG: " + self.name + " checking ammo status...");

        // Don't try to buy ammo if downed or interacting with something critical
        if (self maps\mp\zombies\_zm_laststand::player_is_in_laststand() ||
            self hasgoal("revive") || self hasgoal("boxBuy") ||
            self hasgoal("papBuy") || self hasgoal("doorBuy") ||
            self hasgoal("debrisClear") || self hasgoal("generator"))
        {
            // Debug: Show why the bot isn't buying ammo
            // iprintln("^5DEBUG: " + self.name + " skipping ammo buy (downed or busy)");
            continue;
        }

        currentWeapon = self GetCurrentWeapon();
        if (!IsDefined(currentWeapon) || currentWeapon == "none")
        {
            // Debug: Show if weapon is invalid
            // iprintln("^5DEBUG: " + self.name + " skipping ammo buy (invalid weapon: " + currentWeapon + ")");
            continue;
        }

        // Skip weapons that typically don't get wall ammo
        if (IsSubStr(currentWeapon, "knife") || IsSubStr(currentWeapon, "grenade") || IsSubStr(currentWeapon, "equip") ||
            IsSubStr(currentWeapon, "raygun") || IsSubStr(currentWeapon, "thunder") || IsSubStr(currentWeapon, "wave") ||
            IsSubStr(currentWeapon, "mark2") || IsSubStr(currentWeapon, "tesla") || IsSubStr(currentWeapon, "staff"))
        {
            // Debug: Show if weapon is skipped type
            // iprintln("^5DEBUG: " + self.name + " skipping ammo buy (weapon type not buyable: " + currentWeapon + ")");
            continue;
        }

        clipAmmo = self GetWeaponAmmoClip(currentWeapon);
        stockAmmo = self GetWeaponAmmoStock(currentWeapon);
        maxStockAmmo = WeaponMaxAmmo(currentWeapon);

        // Debug: Show current ammo status
        // iprintln("^5DEBUG: " + self.name + " Weapon: " + currentWeapon + " Stock: " + stockAmmo + "/" + maxStockAmmo);

        // Check if ammo is low (e.g., below 20% of max stock)
        if (IsDefined(maxStockAmmo) && maxStockAmmo > 0 && (stockAmmo < (maxStockAmmo * 0.20)))
        {
            // Debug: Confirm ammo is low
            // iprintln("^5DEBUG: " + self.name + " Ammo low for " + currentWeapon);

            // Find the wallbuy trigger for this weapon
            wallbuy = find_wallbuy_for_weapon(currentWeapon);

            if (IsDefined(wallbuy))
            {
                // Debug: Confirm wallbuy found
                // iprintln("^5DEBUG: " + self.name + " Found wallbuy for " + currentWeapon + " at " + wallbuy.origin);

                ammo_cost = int(wallbuy.trigger_stub.cost / 2);

                // Check if bot can afford it
                if (self.score >= ammo_cost)
                {
                    // Debug: Confirm bot can afford ammo
                    // iprintln("^5DEBUG: " + self.name + " Can afford ammo (Cost: " + ammo_cost + ", Score: " + self.score + ")");

                    dist_sq = DistanceSquared(self.origin, wallbuy.origin);
                    interaction_dist_sq = 10000; // Within 100 units

                    // If close enough, buy ammo
                    if (dist_sq < interaction_dist_sq)
                    {
                        // Debug: Confirm bot is close enough to buy
                        // iprintln("^5DEBUG: " + self.name + " Attempting to buy ammo for " + currentWeapon);
                        // ... (rest of the buying logic) ...
                        self maps\mp\zombies\_zm_score::minus_to_player_score(ammo_cost);
                        self GiveMaxAmmo(currentWeapon);
                        self PlaySound("zmb_cha_ching");
                        wait 2.0;
                    }
                    // If not close enough, move towards it
                    else if (dist_sq < 400000) // Within 632 units
                    {
                        // Debug: Confirm bot is moving towards wallbuy
                        // iprintln("^5DEBUG: " + self.name + " Moving towards wallbuy for " + currentWeapon);
                        // ... (rest of the pathing logic) ...
                        if (!self hasgoal("ammoBuy") || Distance(self GetGoal("ammoBuy"), wallbuy.origin) > 100)
                        {
                            if (FindPath(self.origin, wallbuy.origin, undefined, 0, 1))
                            {
                                self AddGoal(wallbuy.origin, 75, 1, "ammoBuy");
                            }
                            else
                            {
                                // Debug: Show if path not found
                                // iprintln("^1DEBUG: " + self.name + " Path not found to wallbuy at " + wallbuy.origin);
                            }
                        }
                    }
                    else
                    {
                        // Debug: Show if wallbuy is too far
                        // iprintln("^5DEBUG: " + self.name + " Wallbuy too far for " + currentWeapon + " (DistSq: " + dist_sq + ")");
                    }
                }
                else
                {
                    // Debug: Show if bot cannot afford ammo
                    // iprintln("^5DEBUG: " + self.name + " Cannot afford ammo for " + currentWeapon + " (Cost: " + ammo_cost + ", Score: " + self.score + ")");
                }
            }
            else
            {
                // Debug: Show if wallbuy not found
                // iprintln("^5DEBUG: " + self.name + " No wallbuy found for " + currentWeapon);
            }
        }
        else
        {
             // Debug: Show if ammo is not low
            //  iprintln("^5DEBUG: " + self.name + " Ammo OK for " + currentWeapon);
             if (self hasgoal("ammoBuy"))
             {
                 self cancelgoal("ammoBuy");
             }
        }
    }
}

find_wallbuy_for_weapon(weapon_name)
{
    if (!IsDefined(level._spawned_wallbuys))
        return undefined;

    closest_wallbuy = undefined;
    closest_dist_sq = 99999999; // Initialize with a large value

    foreach(wallbuy in level._spawned_wallbuys)
    {
        // Basic validation checks
        if (!IsDefined(wallbuy) || !IsDefined(wallbuy.trigger_stub) || !IsDefined(wallbuy.trigger_stub.zombie_weapon_upgrade) || !IsDefined(wallbuy.origin))
            continue;

        // Check if the wallbuy matches the base weapon name
        base_match = (wallbuy.trigger_stub.zombie_weapon_upgrade == weapon_name);

        // Check if the wallbuy matches the upgraded version of the weapon
        upgraded_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(wallbuy.trigger_stub.zombie_weapon_upgrade);
        upgrade_match = (IsDefined(upgraded_name) && upgraded_name == weapon_name);

        if (base_match || upgrade_match)
        {
            // Find the closest matching wallbuy to the bot
            dist_sq = DistanceSquared(self.origin, wallbuy.origin);
            if (dist_sq < closest_dist_sq)
            {
                // Basic visibility check (optional but can help)
                // if (SightTracePassed(self.origin + (0,0,50), wallbuy.origin + (0,0,10), false, self))
                // {
                    closest_dist_sq = dist_sq;
                    closest_wallbuy = wallbuy;
                // }
            }
        }
    }
    return closest_wallbuy; // Return the closest valid wallbuy found
}
