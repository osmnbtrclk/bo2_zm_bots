#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_pers_upgrades_system;
#include maps\mp\zombies\_zm_pers_upgrades;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_pers_upgrades_functions;
#include common_scripts\utility;
#include maps\mp\_utility;

init()
{
    // Setup monitoring system
    level.pers_upgrades = [];
    level.pers_upgrades_keys = [];
    
    // Force system to always be active
    level.force_pers_system_active = true;
    
    // Register all permaperks first
    pers_register_upgrade("board", ::pers_upgrade_boards_active, "pers_boarding", 74, 0);
    pers_register_upgrade("revive", ::pers_upgrade_revive_active, "pers_revivenoperk", 17, 1);
    pers_register_upgrade("multikill_headshots", ::pers_upgrade_headshot_active, "pers_multikill_headshots", 5, 0);
    pers_register_upgrade("cash_back", ::pers_upgrade_cash_back_active, "pers_cash_back_bought", 50, 0);
    pers_register_upgrade("insta_kill", ::pers_upgrade_insta_kill_active, "pers_insta_kill", 2, 0);
    pers_register_upgrade("jugg", ::pers_upgrade_jugg_active, "pers_jugg", 3, 0);
    pers_register_upgrade("carpenter", ::pers_upgrade_carpenter_active, "pers_carpenter", 1, 0);
    pers_register_upgrade("flopper", ::pers_upgrade_flopper_active, "pers_flopper_counter", 1, 0);
    pers_register_upgrade("perk_lose", ::pers_upgrade_perk_lose_active, "pers_perk_lose_counter", 3, 0);
    pers_register_upgrade("pistol_points", ::pers_upgrade_pistol_points_active, "pers_pistol_points_counter", 1, 0);
    pers_register_upgrade("double_points", ::pers_upgrade_double_points_active, "pers_double_points_counter", 1, 0);
    pers_register_upgrade("sniper", ::pers_upgrade_sniper_active, "pers_sniper_counter", 1, 0);
    pers_register_upgrade("box_weapon", ::pers_upgrade_box_weapon_active, "pers_box_weapon_counter", 5, 0);
    pers_register_upgrade("nube", ::pers_upgrade_nube_active, "pers_nube_counter", 1, 0);
    
    // Setup default values for level vars
    if(!isdefined(level.pers_boarding_number_of_boards_required))
        level.pers_boarding_number_of_boards_required = 74;
    if(!isdefined(level.pers_revivenoperk_number_of_revives_required))
        level.pers_revivenoperk_number_of_revives_required = 17;
    if(!isdefined(level.pers_multikill_headshots_required))
        level.pers_multikill_headshots_required = 5;
    if(!isdefined(level.pers_cash_back_num_perks_required))
        level.pers_cash_back_num_perks_required = 50;
    if(!isdefined(level.pers_insta_kill_num_required))
        level.pers_insta_kill_num_required = 2;
    if(!isdefined(level.pers_jugg_upgrade_health_bonus))
        level.pers_jugg_upgrade_health_bonus = 90;
    if(!isdefined(level.pers_carpenter_zombie_kills))
        level.pers_carpenter_zombie_kills = 1;
    if(!isdefined(level.pers_flopper_counter))
        level.pers_flopper_counter = 1;
    if(!isdefined(level.pers_perk_lose_counter))
        level.pers_perk_lose_counter = 3;
    if(!isdefined(level.pers_pistol_points_counter))
        level.pers_pistol_points_counter = 1;
    if(!isdefined(level.pers_double_points_counter))
        level.pers_double_points_counter = 1;
    if(!isdefined(level.pers_sniper_counter))
        level.pers_sniper_counter = 1;
    if(!isdefined(level.pers_box_weapon_counter))
        level.pers_box_weapon_counter = 5;
    if(!isdefined(level.pers_nube_counter))
        level.pers_nube_counter = 1;
        
    // Enable all permaperk systems
    level.pers_upgrade_boards = 1;
    level.pers_upgrade_revive = 1;
    level.pers_upgrade_multi_kill_headshots = 1;
    level.pers_upgrade_cash_back = 1;
    level.pers_upgrade_insta_kill = 1;
    level.pers_upgrade_jugg = 1;
    level.pers_upgrade_carpenter = 1;
    level.pers_upgrade_flopper = 1;
    level.pers_upgrade_perk_lose = 1;
    level.pers_upgrade_pistol_points = 1;
    level.pers_upgrade_double_points = 1;
    level.pers_upgrade_sniper = 1;
    level.pers_upgrade_box_weapon = 1;
    level.pers_upgrade_nube = 1;
    
    level thread on_player_connect();
}

on_player_connect()
{
    for(;;)
    {
        level waittill("connecting", player);
        player thread on_player_spawned();
    }
}

on_player_spawned()
{
    self endon("disconnect");
    
    // Wait for player to fully connect
    self waittill("spawned");
    
    // debug log
    self iprintlnbold("Activating permaperks for player: " + self.name);
    
    // Initialize globals
    self pers_abilities_init_globals();
    
    // Force unlock all permaperks
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_boarding", level.pers_boarding_number_of_boards_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_revivenoperk", level.pers_revivenoperk_number_of_revives_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_multikill_headshots", level.pers_multikill_headshots_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_cash_back_bought", level.pers_cash_back_num_perks_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_insta_kill", level.pers_insta_kill_num_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_jugg", level.pers_jugg_hit_and_die_total);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_carpenter", level.pers_carpenter_zombie_kills);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_flopper_counter", level.pers_flopper_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_perk_lose_counter", level.pers_perk_lose_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_pistol_points_counter", level.pers_pistol_points_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_double_points_counter", level.pers_double_points_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_sniper_counter", level.pers_sniper_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_box_weapon_counter", level.pers_box_weapon_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_nube_counter", level.pers_nube_counter);
    
    // Immediately award all perks
    self.pers_upgrades_awarded = [];
    self.pers_upgrades_awarded["board"] = 1;
    self.pers_upgrades_awarded["revive"] = 1;
    self.pers_upgrades_awarded["multikill_headshots"] = 1;
    self.pers_upgrades_awarded["cash_back"] = 1;
    self.pers_upgrades_awarded["insta_kill"] = 1;
    self.pers_upgrades_awarded["jugg"] = 1;
    self.pers_upgrades_awarded["carpenter"] = 1;
    self.pers_upgrades_awarded["flopper"] = 1;
    self.pers_upgrades_awarded["perk_lose"] = 1;
    self.pers_upgrades_awarded["pistol_points"] = 1;
    self.pers_upgrades_awarded["double_points"] = 1;
    self.pers_upgrades_awarded["sniper"] = 1;
    self.pers_upgrades_awarded["box_weapon"] = 1;
    self.pers_upgrades_awarded["nube"] = 1;
    
    // Start upgrade threads with immediate activation
    self thread pers_upgrade_jugg_active();  // Start jugg first for health bonus
    self thread maps\mp\zombies\_zm_perks::perk_set_max_health_if_jugg("jugg_upgrade", 1, 0);
    
    self thread pers_upgrade_boards_active();
    self thread pers_upgrade_revive_active();
    self thread pers_upgrade_headshot_active();
    self thread pers_upgrade_cash_back_active();
    self thread pers_upgrade_insta_kill_active();
    self thread pers_upgrade_carpenter_active();
    self thread pers_upgrade_flopper_active();
    self thread pers_upgrade_perk_lose_active();
    self thread pers_upgrade_pistol_points_active();
    self thread pers_upgrade_double_points_active();
    self thread pers_upgrade_sniper_active();
    self thread pers_upgrade_box_weapon_active();
    self thread pers_upgrade_nube_active();
}
