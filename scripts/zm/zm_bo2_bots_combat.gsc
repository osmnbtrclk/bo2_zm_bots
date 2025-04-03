#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include scripts\zm\zm_bo2_bots;

bot_combat_think( damage, attacker, direction )
{
	self allowattack( 0 );
	self pressads( 0 );
	for ( ;; )
	{
		if ( !bot_can_do_combat() )
		{
			return;
		}
		if(self atgoal("flee"))
			self cancelgoal("flee");
		//FLEE CODE. IF ZOMBIE IS CLOSE TO BOT, BOT WILL TRY TO FIND A PLACE TO RUN AWAY
		//LOOKING FOR ANOTHER ALTERNATIVE IF DOORS ARE CLOSED AND THE BOT CAN NOT REACH SAID PATH.
		if(Distance(self.origin, self.bot.threat.position) <= 75 || isdefined(damage))
		{
			nodes = getnodesinradiussorted( self.origin, 1024, 256, 512 );
			nearest = bot_nearest_node(self.origin);
			if ( isDefined( nearest ) && !self hasgoal( "flee" ) )
			{
				foreach ( node in nodes )
				{
					if ( !nodesvisible( nearest, node ) && FindPath(self.origin, node.origin, undefined, 0, 1) )
					{
						self addgoal( node.origin, 24, 4, "flee" );
						break;
					}
				}
			}
		}
		if(self GetCurrentWeapon() == "none")
			return;
		sight = self bot_best_enemy();
		if(!isdefined(self.bot.threat.entity))
			return;
		if ( threat_dead() )
		{
			self bot_combat_dead();
			return;
		}
		//ADD OTHER COMBAT TASKS HERE.
		self bot_combat_main();
		self bot_pickup_powerup();
		if(is_true(level.using_bot_revive_logic))
		{
			self bot_revive_teammates();
		}
		wait 0.05; //fu difficulty
	}
}

bot_combat_main() //checked partially changed to match cerberus output changed at own discretion
{
	weapon = self getcurrentweapon();
	currentammo = self getweaponammoclip( weapon ) + self getweaponammostock( weapon );
	if ( !currentammo )
	{
		return;
	}
	time = getTime();
	if ( !self bot_should_hip_fire() && self.bot.threat.dot > 0.96 )
	{
		ads = 1;
	}
	if ( ads )
	{
		self pressads( 1 );
	}
	else
	{
		self pressads( 0 );
	}
	frames = 4;
	if ( time >= self.bot.threat.time_aim_correct )
	{
		self.bot.threat.time_aim_correct += self.bot.threat.time_aim_interval;
		frac = ( time - self.bot.threat.time_first_sight ) / 100;
		frac = clamp( frac, 0, 1 );
		if ( !threat_is_player() )
		{
			frac = 1;
		}
		self.bot.threat.aim_target = self bot_update_aim( frames );
		self.bot.threat.position = self.bot.threat.entity.origin;
		self bot_update_lookat( self.bot.threat.aim_target, frac );
	}
	if ( self bot_on_target( self.bot.threat.entity.origin, 30 ) )
	{
		self allowattack( 1 );
	}
	else
	{
		self allowattack( 0 );
	}
	if ( is_true( self.stingerlockstarted ) )
	{
		self allowattack( self.stingerlockfinalized );
		return;
	}
}

bot_combat_dead( damage ) //checked matches cerberus output
{
	wait 0.1;
	self allowattack( 0 );
	wait_endon( 0.25, "damage" );
	self bot_clear_enemy();
}

bot_should_hip_fire() //checked matches cerberus output
{
	enemy = self.bot.threat.entity;
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 0;
	}
	if ( weaponisdualwield( weapon ) )
	{
		return 1;
	}
	class = weaponclass( weapon );
	if ( isplayer( enemy ) && class == "spread" )
	{
		return 1;
	}
	distsq = distancesquared( self.origin, enemy.origin );
	distcheck = 0;
	switch( class )
	{
		case "mg":
			distcheck = 250;
			break;
		case "smg":
			distcheck = 350;
			break;
		case "spread":
			distcheck = 400;
			break;
		case "pistol":
			distcheck = 200;
			break;
		case "rocketlauncher":
			distcheck = 0;
			break;
		case "rifle":
		default:
			distcheck = 300;
			break;
	}
	if ( isweaponscopeoverlay( weapon ) )
	{
		distcheck = 500;
	}
	return distsq < ( distcheck * distcheck );
}

bot_patrol_near_enemy( damage, attacker, direction ) //checked matches cerberus output
{
	if ( isDefined( attacker ) )
	{
		self bot_lookat_entity( attacker );
	}
	if ( !isDefined( attacker ) )
	{
		attacker = self bot_get_closest_enemy( self.origin );
	}
	if ( !isDefined( attacker ) )
	{
		return;
	}
	node = bot_nearest_node( attacker.origin );
	if ( !isDefined( node ) )
	{
		nodes = getnodesinradiussorted( attacker.origin, 1024, 0, 512, "Path", 8 );
		if ( nodes.size )
		{
			node = nodes[ 0 ];
		}
	}
	if ( isDefined( node ) )
	{
		if ( isDefined( damage ) )
		{
			self addgoal( node, 24, 4, "enemy_patrol" );
			return;
		}
		else
		{
			self addgoal( node, 24, 2, "enemy_patrol" );
		}
	}
}

bot_lookat_entity( entity ) //checked matches cerberus output
{
	if ( isplayer( entity ) && entity getstance() != "prone" )
	{
		if ( distancesquared( self.origin, entity.origin ) < 65536 )
		{
			origin = entity getcentroid() + vectorScale( ( 0, 0, 1 ), 10 );
			self lookat( origin );
			return;
		}
	}
	offset = target_getoffset( entity );
	if ( isDefined( offset ) )
	{
		self lookat( entity.origin + offset );
	}
	else
	{
		self lookat( entity getcentroid() );
	}
}

bot_update_lookat( origin, frac ) //checked matches cerberus output
{
	angles = vectorToAngles( origin - self.origin );
	right = anglesToRight( angles );
	error = bot_get_aim_error() * ( 1 - frac );
	if ( cointoss() )
	{
		error *= -1;
	}
	height = origin[ 2 ] - self.bot.threat.entity.origin[ 2 ];
	height *= 1 - frac;
	if ( cointoss() )
	{
		height *= -1;
	}
	end = origin + ( right * error );
	end += ( 0, 0, height );
	red = 1 - frac;
	green = frac;
	self lookat( end );
}

bot_update_aim( frames ) //checked matches cerberus output
{
	ent = self.bot.threat.entity;
	prediction = self predictposition( ent, frames );
	if ( !threat_is_player() )
	{
		height = ent getcentroid()[ 2 ] - prediction[ 2 ];
		return prediction + ( 0, 0, height );
	}
	height = ent getplayerviewheight();
	torso = prediction + ( 0, 0, height / 1.6 );
	return torso;
}

bot_on_target( aim_target, radius ) //checked matches cerberus output
{
	angles = self getplayerangles();
	forward = anglesToForward( angles );
	origin = self getplayercamerapos();
	len = distance( aim_target, origin );
	end = origin + ( forward * len );
	if ( distance2dsquared( aim_target, end ) < ( radius * radius ) )
	{
		return 1;
	}
	return 0;
}

bot_get_aim_error() //checked changed at own discretion
{
	return 1;
}

bot_has_lmg() //checked changed at own discretion
{
	if ( bot_has_weapon_class( "mg" ) )
	{
		return 1;
	}
	return 0;
}

bot_has_weapon_class( class ) //checked changed at own discretion
{
	if ( self isreloading() )
	{
		return 0;
	}
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 0;
	}
	if ( weaponclass( weapon ) == class )
	{
		return 1;
	}
	return 0;
}

bot_can_reload() //checked changed to match cerberus output
{
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 0;
	}
	if ( !self getweaponammostock( weapon ) )
	{
		return 0;
	}
	if ( self isreloading() || self isswitchingweapons() || self isthrowinggrenade() )
	{
		return 0;
	}
	return 1;
}

bot_best_enemy() //checked partially changed to match cerberus output did not change while loop to foreach see github for more info
{
	enemies = getaispeciesarray( level.zombie_team, "all" );
	enemies = arraysort( enemies, self.origin );
	i = 0;
	while ( i < enemies.size )
	{
		if ( threat_should_ignore( enemies[ i ] ) )
		{
			i++;
			continue;
		}
		if ( self botsighttracepassed( enemies[ i ] ) )
		{
			self.bot.threat.entity = enemies[ i ];
			self.bot.threat.time_first_sight = getTime();
			self.bot.threat.time_recent_sight = getTime();
			self.bot.threat.dot = bot_dot_product( enemies[ i ].origin );
			self.bot.threat.position = enemies[ i ].origin;
			return 1;
		}
		i++;
	}
	return 0;
}

bot_weapon_ammo_frac() //checked matches cerberus output
{
	if ( self isreloading() || self isswitchingweapons() )
	{
		return 0;
	}
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 1;
	}
	total = weaponclipsize( weapon );
	if ( total <= 0 )
	{
		return 1;
	}
	current = self getweaponammoclip( weapon );
	return current / total;
}

bot_select_weapon() //checked partially changed to match cerberus output did not change while loop to foreach see github for more info
{
	if ( self isthrowinggrenade() || self isswitchingweapons() || self isreloading() )
	{
		return;
	}
	if ( !self isonground() )
	{
		return;
	}
	ent = self.bot.threat.entity;
	if ( !isDefined( ent ) )
	{
		return;
	}
	primaries = self getweaponslistprimaries();
	weapon = self getcurrentweapon();
	stock = self getweaponammostock( weapon );
	clip = self getweaponammoclip( weapon );
	if ( weapon == "none" )
	{
		return;
	}
	if ( weapon == "fhj18_mp" && !target_istarget( ent ) )
	{
		foreach ( primary in primaries )
		{
			if ( primary != weapon )
			{
				self switchtoweapon( primary );
				return;
			}
		}
		return;
	}
	if ( !clip )
	{
		if ( stock )
		{
			if ( weaponhasattachment( weapon, "fastreload" ) )
			{
				return;
			}
		}
		i = 0;
		while ( i < primaries.size )
		{
			if ( primaries[ i ] == weapon || primaries[ i ] == "fhj18_mp" )
			{
				i++;
				continue;
			}
			if ( self getweaponammoclip( primaries[ i ] ) )
			{
				self switchtoweapon( primaries[ i ] );
				return;
			}
			i++;
		}
		if ( self bot_has_lmg() )
		{
			i = 0;
			while ( i < primaries.size )
			{
				if ( primaries[ i ] == weapon || primaries[ i ] == "fhj18_mp" )
				{
					i++;
					continue;
				}
				else
				{
					self switchtoweapon( primaries[ i ] );
					return;
				}
				i++;
			}
		}
	}
}

bot_can_do_combat() //checked matches cerberus output
{
	if ( self ismantling() || self isonladder() )
	{
		return 0;
	}
	return 1;
}

bot_dot_product( origin ) //checked matches cerberus output
{
	angles = self getplayerangles();
	forward = anglesToForward( angles );
	delta = origin - self getplayercamerapos();
	delta = vectornormalize( delta );
	dot = vectordot( forward, delta );
	return dot;
}

threat_should_ignore( entity ) //checked matches cerberus output
{
	return 0;
}

bot_clear_enemy() //checked matches cerberus output
{
	self clearlookat();
	self.bot.threat.entity = undefined;
}

bot_has_enemy() //checked changed at own discretion
{
	if ( isDefined( self.bot.threat.entity ) )
	{
		return 1;
	}
	return 0;
}

threat_dead() //checked changed at own discretion
{
	if ( self bot_has_enemy() )
	{
		ent = self.bot.threat.entity;
		if ( !isalive( ent ) )
		{
			return 1;
		}
		return 0;
	}
	return 0;
}

threat_is_player() //checked changed at own discretion
{
	ent = self.bot.threat.entity;
	if ( isDefined( ent ) && isplayer( ent ) )
	{
		return 1;
	}
	return 0;
}