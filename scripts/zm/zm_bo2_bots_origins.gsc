#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_laststand;
#include scripts\zm\zm_bo2_bots_combat; // Include combat functions for aiming

init()
{
    // Initialization logic for Origins bots, if any needed beyond the main script
    if (level.script == "zm_tomb")
    {
        iprintln("^2ZM BO2 Bots: Origins module initialized.");
        
    }
    else
    {
        iprintln("^1ZM BO2 Bots: Origins module not initialized, not in the correct map.");
        return;
    }
       
}

// Main thinking loop for Origins-specific actions
bot_origins_think()
{
	// Ensure this logic only runs on Origins
	if (level.script != "zm_tomb")
		return;

    self endon("disconnect");
    self endon("death");
    level endon("game_ended");

    while(true)
    {
        // Attempt to activate a generator
        self bot_activate_generator();

        // Add logic for defending generators under recapture attack later if needed
        // self bot_defend_generator();

        wait 1.5; // Check every 1.5 seconds
    }
}

// Function for bots to find and activate generators
bot_activate_generator()
{
    // Only attempt periodically and check cooldowns
    if (!isDefined(self.bot.generator_check_time) || GetTime() > self.bot.generator_check_time)
    {
        self.bot.generator_check_time = GetTime() + 7500; // Check every 7.5 seconds

        // Don't try if in last stand
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;

        // Check if another generator capture is already in progress globally
        if (flag("zone_capture_in_progress"))
            return;

        // Check if another bot is already activating/capturing a generator
        if (isDefined(level.generator_in_use_by_bot) && level.generator_in_use_by_bot != self)
            return;

        // Global cooldown for generator activation attempts
        if (isDefined(level.last_bot_generator_time) && (GetTime() - level.last_bot_generator_time < 45000)) // 45 second global cooldown
            return;

        // Personal cooldown
        if (isDefined(self.bot.last_generator_time) && (GetTime() - self.bot.last_generator_time < 60000)) // 60 second personal cooldown
            return;

        // Check if bot has enough points
        generator_cost = 200 * get_players().size;
        if (self.score < generator_cost)
            return;

        // Find the closest inactive generator
        closest_generator = undefined;
        closest_dist = 10000; // Start with a large distance
        generators = getstructarray("s_generator", "targetname");

        foreach (generator in generators)
        {        // Skip if already player controlled or currently being contested
            if (generator.ent_flag["player_controlled"] || generator.ent_flag["zone_contested"])
                continue;

            dist = Distance(self.origin, generator.origin);
            if (dist < closest_dist)
            {
                // Check if there's a path
                if (FindPath(self.origin, generator.origin, undefined, 0, 1))
                {
                    closest_generator = generator;
                    closest_dist = dist;
                }
            }
        }

        // If no valid generator found
        if (!isDefined(closest_generator))
            return;

        // Move to the generator if not close enough
        if (closest_dist > 128) // Need to be relatively close
        {
            if (!self hasgoal("generatorBuy") || Distance(self GetGoal("generatorBuy"), closest_generator.origin) > 50)
            {
                 self AddGoal(closest_generator.origin, 75, 2, "generatorBuy");
            }
            return; // Wait until closer
        }

        // Cancel movement goal if we arrived
        if (self hasgoal("generatorBuy"))
            self cancelgoal("generatorBuy");

        // Look at the generator
        aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
        self lookat(closest_generator.origin + aim_offset);
        wait randomfloatrange(0.5, 1.2); // Simulate hesitation        // Re-check conditions before activating
        if (flag("zone_capture_in_progress") ||
            (isDefined(level.generator_in_use_by_bot) && level.generator_in_use_by_bot != self) ||
            self.score < generator_cost ||
            closest_generator.ent_flag["player_controlled"] ||
            closest_generator.ent_flag["zone_contested"])
        {
            return;
        }

        // Mark this bot as using a generator
        level.generator_in_use_by_bot = self;

        // Deduct points and notify the generator system
        self maps\mp\zombies\_zm_score::minus_to_player_score(generator_cost);
        closest_generator notify("start_generator_capture", self);
        self PlaySound("zmb_cha_ching"); // Play purchase sound

        // Update cooldowns
        self.bot.last_generator_time = GetTime();
        level.last_bot_generator_time = GetTime();

        // Start monitoring the capture process
        self thread bot_monitor_generator_capture(closest_generator, generator_cost);
    }
}

// Function to monitor the generator capture process and defend
bot_monitor_generator_capture(generator, cost)
{
    self endon("disconnect");
    self endon("death");
    level endon("game_ended");    // Wait for the generator to become contested (capture zombies start spawning)
    while(!generator.ent_flag["zone_contested"])
        wait 0.05;
    iprintln("^5Bot " + self.name + " defending generator: " + generator.script_noteworthy);    // Stay near the generator and defend
    defense_radius = 250; // How far the bot will stray while defending
    defense_origin = generator.origin;

    while (generator.ent_flag["zone_contested"])
    {
        // Find nearby enemies, prioritize capture zombies
        enemies = getaispeciesarray(level.zombie_team, "all");
        closest_enemy = undefined;
        closest_dist = defense_radius * defense_radius; // Use squared distance for efficiency
        capture_zombie_target = undefined;

        foreach (enemy in enemies)
        {
            if (!isalive(enemy)) continue;

            dist_sq = DistanceSquared(self.origin, enemy.origin);

            // Prioritize capture zombies attacking the generator
            is_capture_zombie = enemy getclientfield("zone_capture_zombie"); // Check the client field set in source
            if (isdefined(is_capture_zombie) && is_capture_zombie == 1 && DistanceSquared(enemy.origin, defense_origin) < (defense_radius * 1.5)*(defense_radius * 1.5)) // Slightly larger radius for targeting capture zombies
            {
                 // Check if zombie is targeting the generator (simple distance check for now)
                 if(DistanceSquared(enemy.origin, defense_origin) < 150*150)
                 {
                     capture_zombie_target = enemy;
                     break; // Found priority target
                 }
            }

            if (dist_sq < closest_dist)
            {
                closest_enemy = enemy;
                closest_dist = dist_sq;
            }
        }

        target_enemy = capture_zombie_target;
        if (!isdefined(target_enemy))
        {
            target_enemy = closest_enemy;
        }

        // Engage the target enemy
        if (isdefined(target_enemy))
        {
            self bot_combat_think_simple(target_enemy); // Use a simplified combat logic
        }
        else
        {
             // If no enemies nearby, stay close to the generator origin
             if (DistanceSquared(self.origin, defense_origin) > 100*100) // If too far, move back
             {
                 self AddGoal(defense_origin, 50, 1, "defendGen");             }
             else if (self hasgoal("defendGen"))
             {
                 self cancelgoal("defendGen");
             }
             // Look around idly
             if (isDefined(self.bot) && (!isDefined(self.bot.update_idle_lookat) || GetTime() > self.bot.update_idle_lookat))
             {
                 // Set a random point to look at around the generator
                 random_offset = (randomfloatrange(-100, 100), randomfloatrange(-100, 100), randomfloatrange(-20, 50));
                 self lookat(defense_origin + random_offset);
                 self.bot.update_idle_lookat = GetTime() + randomintrange(1000, 3000);
             }
         }

        wait 0.1 + randomfloat(0.2); // Think interval while defending
    }    iprintln("^5Bot " + self.name + " finished defending generator: " + generator.script_noteworthy);

    // Check if capture was successful
    if (generator.ent_flag["player_controlled"])
    {
        iprintln("^2Generator " + generator.script_noteworthy + " captured successfully by bot " + self.name);
        // Refund points if bot stayed within the zone (approximated by distance)
        if (DistanceSquared(self.origin, defense_origin) < (defense_radius * defense_radius))
        {
             n_refund_amount = cost;
             b_double_points_active = level.zombie_vars["allies"]["zombie_point_scalar"] == 2;
             n_multiplier = 1;
             if (b_double_points_active)
                 n_multiplier = 0.5;
             self maps\mp\zombies\_zm_score::add_to_player_score(int(n_refund_amount * n_multiplier));
             iprintln("^2Bot " + self.name + " refunded " + int(n_refund_amount * n_multiplier) + " points for capture.");
        }
    }
    else
    {
        iprintln("^1Generator " + generator.script_noteworthy + " capture failed.");
        // No refund if failed
    }

    // Clear the global usage flag if this bot was the one using it
    if (isDefined(level.generator_in_use_by_bot) && level.generator_in_use_by_bot == self)
    {
        level.generator_in_use_by_bot = undefined;
    }
}

// Simplified combat logic for defending generator
bot_combat_think_simple(target_enemy)
{
    if (!isdefined(target_enemy) || !isalive(target_enemy))
        return;    // Aim and shoot
    self lookat(target_enemy.origin + (0,0,30)); // Aim slightly above origins
    if (self AttackButtonPressed())
    {
        wait randomfloatrange(0.1, 0.3); // Burst fire
        self lookat(target_enemy.origin + (0,0,30) + (randomintrange(-10,10), randomintrange(-10,10), randomintrange(-5,5))); // Adjust aim slightly
    }    else
    {
         self allowattack(1); // Enable shooting
         wait randomfloatrange(0.2, 0.5);
         self allowattack(0); // Disable shooting
    }

    // Melee if close
    if (DistanceSquared(self.origin, target_enemy.origin) < (70*70))
    {
        self Melee();
    }
}

// Function to handle bot cleanup if they disconnect during capture
bot_cleanup_generator_on_disconnect()
{
    self waittill("disconnect");

    // If this bot was using a generator, clear the global flag
    if (isDefined(level.generator_in_use_by_bot) && level.generator_in_use_by_bot == self)
    {
        level.generator_in_use_by_bot = undefined;
        iprintln("^1Bot " + self.name + " disconnected during generator capture, flag cleared.");
    }
}
