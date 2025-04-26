// zm_bo2_bots_utility.gsc
// Utility functions for the bo2 zombies bot mod
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_ai_basic;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_turned;
#include maps\mp\zombies\_zm_equipment;
#include maps\mp\zombies\_zm_buildables;
#include maps\mp\zombies\_zm_weap_claymore;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\zombies\_zm_laststand;

zombie_healthbar( pos, dsquared )
{

    if ( distancesquared( pos, self.origin ) > dsquared )
        return;

    rate = 1;

    if ( isdefined( self.maxhealth ) )
        rate = self.health / self.maxhealth;

    color = ( 1 - rate, rate, 0 );
    text = "" + int( self.health );
    print3d( self.origin + ( 0, 0, 0 ), text, color, 1, 0.5, 1 );

}

devgui_zombie_healthbar()
{
    while ( true )
    {
        if ( getdvarint( #"_id_5B45DCAF" ) == 1 )
        {
            lp = get_players()[0]; // Changed from get_players() to getplayers()
            zombies = getaispeciesarray( "all", "all" );

            if ( isdefined( zombies ) )
            {
                foreach ( zombie in zombies )
                    zombie zombie_healthbar( lp.origin, 360000 );
            }
        }

        wait 0.05;
    }
}

// New function to initialize healthbar functionality
init_zombie_healthbar()
{
    // Create the DVar if it doesn't exist
    if(!isdefined(level.zombie_healthbar_dvar))
    {
        setdvar("_id_5B45DCAF", 1);
        level.zombie_healthbar_dvar = 1;
    }
    
    level thread devgui_zombie_healthbar();
}

// Player connection callback
on_player_connect()
{
    level endon("end_game");
    
    for(;;)
    {
        level waittill("connected", player);
        player thread on_player_spawned();
    }
}

// Player spawn callback
on_player_spawned()
{
    self endon("disconnect");
    
    for(;;)
    {
        self waittill("spawned_player");
        // Wait for black screen to end
        wait(1);

        self thread init_player_hud();
        
        // Only initialize once per game
        if(!isdefined(level.healthbar_initialized))
        {
            level.healthbar_initialized = true;
            level thread init_zombie_healthbar();
        }
    }
}

init_player_hud()
{
    self endon("disconnect");
    level endon("game_ended");

    // Sadece bir kere oluştur
    if (!isDefined(self.hud_initialized))
    {
        // Can Göstergesi
        self.hud_health_text = newClientHudElem(self);
        self.hud_health_text.alignX = "left";
        self.hud_health_text.alignY = "bottom";
        self.hud_health_text.horzAlign = "left";
        self.hud_health_text.vertAlign = "bottom";
        self.hud_health_text.x = 50;
        self.hud_health_text.y = -50;
        self.hud_health_text.fontScale = 1.5;
        self.hud_health_text.font = "objective";
        self.hud_health_text.color = (1, 1, 1);
        self.hud_health_text.alpha = 1;

        // Pozisyon Göstergesi
        self.hud_position_text = newClientHudElem(self);
        self.hud_position_text.alignX = "left";
        self.hud_position_text.alignY = "bottom";
        self.hud_position_text.horzAlign = "left";
        self.hud_position_text.vertAlign = "bottom";
        self.hud_position_text.x = 50;
        self.hud_position_text.y = -80;
        self.hud_position_text.fontScale = 1.2;
        self.hud_position_text.font = "default";
        self.hud_position_text.color = (1, 1, 1);
        self.hud_position_text.alpha = 1;

        self.hud_initialized = true;

        // Güncelleme döngüsünü başlat
        self thread update_player_hud();
    }
}

update_player_hud()
{
    self endon("disconnect");
    level endon("game_ended");

    while(true)
    {
        // Canı güncelle
        health_str = "HP: " + self.health;
        if (isDefined(self.hud_health_text))
           self.hud_health_text setText(health_str);

        // Pozisyonu güncelle
        // pos_str = "XYZ: " + int(self.origin[0]) + ", " + int(self.origin[1]) + ", " + int(self.origin[2]); // Commented out to prevent configstring overflow
        // if(isDefined(self.hud_position_text))
        //    self.hud_position_text setText(pos_str); // Commented out to prevent configstring overflow

        wait 0.1; // Saniyede 10 kere güncelle (isteğe bağlı)
    }
}

// Auto-start the connection monitoring when script loads
init()
{
    level thread on_player_connect();
}

// Custom implementation of NodeVisible function
// Checks if two points are visible to each other
NodeVisible(origin1, origin2)
{
    // Add small vertical offset to account for ground level
    origin1 = origin1 + (0, 0, 10);
    origin2 = origin2 + (0, 0, 10);
    
    // Check line of sight between points
    return SightTracePassed(origin1, origin2, false, undefined);
}
