/**
* DoD:S Damage Report by Root
*
* Description:
*   When a client dies, show how many hits client do and take with damage stats in a menu.
*   Also show most destructive player & overall player stats at end of the round.
*
* Version 1.4
* Changelog & more info at http://goo.gl/4nKhJ
*/

// ====[ SEMICOLON ]===============================================================
#pragma semicolon 1

// ====[ INCLUDES ]================================================================
#include <sourcemod>
#include <clientprefs>
#include <colors>

// ====[ CONSTANTS ]===============================================================
#define PLUGIN_NAME      "DoD:S Damage Report"
#define PLUGIN_VERSION   "1.4"

#define DOD_MAXPLAYERS   33
#define DOD_MAXHITGROUPS 7

// ====[ VARIABLES ]===============================================================
new	Handle:damagereport_enable, // ConVars
	Handle:damagereport_mdest,
	Handle:damagereport_info[DOD_MAXPLAYERS], // Welcome timer
	Handle:dmg_chatprefs, // Clientprefs
	Handle:dmg_panelprefs,
	Handle:dmg_endroundprefs,
	cookie_chatmode[DOD_MAXPLAYERS]    = {false, ...}, // Cookies
	cookie_deathpanel[DOD_MAXPLAYERS]  = {true,  ...},
	cookie_resultpanel[DOD_MAXPLAYERS] = {true,  ...},
	bool:roundend = false, // Round end stats
	kills[DOD_MAXPLAYERS],
	deaths[DOD_MAXPLAYERS],
	headshots[DOD_MAXPLAYERS],
	captures[DOD_MAXPLAYERS],
	damage_temp[DOD_MAXPLAYERS], // Damage (given/taken/summary)
	damage_summ[DOD_MAXPLAYERS],
	damage_given[DOD_MAXPLAYERS][DOD_MAXPLAYERS],
	damage_taken[DOD_MAXPLAYERS][DOD_MAXPLAYERS],
	hits[DOD_MAXPLAYERS][DOD_MAXPLAYERS], // Hits data
	hurts[DOD_MAXPLAYERS][DOD_MAXPLAYERS],
	String:yourstatus[DOD_MAXPLAYERS][DOD_MAXPLAYERS][32], // Player status (killed/injured)
	String:killerstatus[DOD_MAXPLAYERS][DOD_MAXPLAYERS][32];

// ====[ PLUGIN ]==================================================================
public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "Shows damage stats, round stats & most destructive player *clientprefs",
	version     = PLUGIN_VERSION,
	url         = "http://dodsplugins.com/"
};


/**
 * --------------------------------------------------------------------------------
 *     ____           ______                  __  _
 *    / __ \____     / ____/__  ______  _____/ /_(_)____  ____  _____
 *   / / / / __ \   / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *  / /_/ / / / /  / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *  \____/_/ /_/  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * --------------------------------------------------------------------------------
*/

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------------- */
public OnPluginStart()
{
	// Create ConVars
	CreateConVar("dod_damagestats_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED);
	damagereport_enable = CreateConVar("sm_damage_report",       "1", "Whether or not enable Damage Report",                             FCVAR_PLUGIN, true, 0.0, true, 1.0);
	damagereport_mdest  = CreateConVar("sm_damage_report_mdest", "2", "Where to show most destructive player stats: hint(1) or chat(2)", FCVAR_PLUGIN, true, 0.0, true, 2.0);

	// Hook ConVar changing
	HookConVarChange(damagereport_enable, OnConVarChange);

	// Hook player events
	HookEvent("dod_stats_player_damage", Event_Player_Damage);
	HookEvent("dod_stats_player_killed", Event_Player_Killed);

	// Hook game events
	HookEvent("dod_point_captured", Event_Point_Captured);
	HookEvent("dod_round_start",    Event_Round_Start);
	HookEvent("dod_round_win",      Event_Round_End);

	// Create/register client command
	RegConsoleCmd("dmg", DamageReportMenu);

	// Load translations
	LoadTranslations("damage_report.phrases");

	// Creates a new Client preference cookies
	dmg_chatprefs     = RegClientCookie("Chat preference",    "Damage Report", CookieAccess_Private);
	dmg_panelprefs    = RegClientCookie("Panel preference",   "Damage Report", CookieAccess_Private);
	dmg_endroundprefs = RegClientCookie("Results preference", "Damage Report", CookieAccess_Private);

	// Show "Damge Report" item in cookie settings menu
	decl String:title[48];
	Format(title, sizeof(title), "%t", "damagemenu");

	// Clientprefs avalible - create panel
	if (LibraryExists("clientprefs"))
		SetCookieMenuItem(DamageReportSelect, 0, title);
}

/* OnConVarChange()
 *
 * Called when a convar's value is changed.
 * --------------------------------------------------------------------- */
public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// Convert a string to an integer
	switch (StringToInt(newValue))
	{
		// If plugin is disabled, unhook all events
		case 0:
		{
			UnhookEvent("dod_stats_player_damage", Event_Player_Damage);
			UnhookEvent("dod_stats_player_killed", Event_Player_Killed);
			UnhookEvent("dod_point_captured",      Event_Point_Captured);
			UnhookEvent("dod_round_start",         Event_Round_Start);
			UnhookEvent("dod_round_win",           Event_Round_End);
		}

		case 1:
		{
			HookEvent("dod_stats_player_damage", Event_Player_Damage);
			HookEvent("dod_stats_player_killed", Event_Player_Killed);
			HookEvent("dod_point_captured",      Event_Point_Captured);
			HookEvent("dod_round_start",         Event_Round_Start);
			HookEvent("dod_round_win",           Event_Round_End);
		}
	}
}

/* OnClientPutInServer()
 *
 * Called when a client is entering the game.
 * -------------------------------------------------------------------------------- */
public OnClientPutInServer(client)
{
	if (client > 0 && !IsFakeClient(client))
	{
		// Are clients cookies have been loaded from the database?
		if (AreClientCookiesCached(client)) LoadPreferences(client);

		// Show welcome message
		damagereport_info[client] = CreateTimer(30.0, Timer_WelcomePlayer, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

/* OnClientCookiesCached()
 *
 * Called once a client's saved cookies have been loaded from the database.
 * -------------------------------------------------------------------------------- */
public OnClientCookiesCached(client)
{
	// If cookies was not ready until connection, wait until OnClientCookiesCached()
	if (client > 0) LoadPreferences(client);
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * -------------------------------------------------------------------------------- */
public OnClientDisconnect(client)
{
	// Client should be valid
	if (client > 0)
	{
		// Kill timer
		if (damagereport_info[client] != INVALID_HANDLE)
		{
			CloseHandle(damagereport_info[client]);
			damagereport_info[client] = INVALID_HANDLE;
		}

		// Reset damage stats
		resetall(client);
	}
}


/**
 * --------------------------------------------------------------------------------
 *      ______                  __
 *     / ____/_   _____  ____  / /______
 *    / __/  | | / / _ \/ __ \/ __/ ___/
 *   / /___  | |/ /  __/ / / / /_(__  )
 *  /_____/  |___/\___/_/ /_/\__/____/
 *
 * --------------------------------------------------------------------------------
*/

/* Event_Player_Damage()
 *
 * Called when a player taking damage.
 * -------------------------------------------------------------------------------- */
public Event_Player_Damage(Handle:event, const String:name[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new victim   = GetClientOfUserId(GetEventInt(event, "victim"));

	// Victim and attacker should be valid and not a teammates
	if (attacker > 0 && victim > 0 && GetClientTeam(attacker) != GetClientTeam(victim))
	{
		// Finding event key
		new damage   = GetEventInt(event, "damage");
		new hitgroup = GetEventInt(event, "hitgroup");

		/** HITGROUPS
		0 = Generic - not avalible in DoD:S
		1 = Head
		2 = Upper Chest
		3 = Lower Chest
		4 = Left arm
		5 = Right arm
		6 = Left leg
		7 = Right Leg
		*/

		// Headshot event taken from psychonic's DoD:S SuperLogs plugin
		new bool:headshot = (GetEventInt(event, "health") < 1 && hitgroup == 1);

		// Overall 7 hitboxes avalible
		decl String:g_Hitbox[DOD_MAXHITGROUPS + 1][32], String:data[32];

		// Hitgroup definitions
		Format(data, sizeof(data), "%t", "hitbox0", victim);
		g_Hitbox[0] = data;
		Format(data, sizeof(data), "%t", "hitbox1", victim);
		g_Hitbox[1] = data;
		Format(data, sizeof(data), "%t", "hitbox2", victim);
		g_Hitbox[2] = data;
		Format(data, sizeof(data), "%t", "hitbox3", victim);
		g_Hitbox[3] = data;
		Format(data, sizeof(data), "%t", "hitbox4", victim);
		g_Hitbox[4] = data;
		Format(data, sizeof(data), "%t", "hitbox5", victim);
		g_Hitbox[5] = data;
		Format(data, sizeof(data), "%t", "hitbox6", victim);
		g_Hitbox[6] = data;
		Format(data, sizeof(data), "%t", "hitbox7", victim);
		g_Hitbox[7] = data;

		// Save headshots
		if (headshot) headshots[attacker]++;

		// Times hit/injured
		hits[victim][attacker]++;
		hurts[attacker][victim]++;

		// Saves summary damage done to all victims
		damage_temp[attacker] += damage;

		// Summary damage (most destructive)
		damage_summ[attacker] += damage;

		// Save damage data of every injured victim
		damage_given[attacker][victim] += damage;

		// And for every attacker
		damage_taken[victim][attacker] += damage;

		// If player was not killed - show status
		if (GetClientHealth(victim) > 0)
		{
			Format(data, sizeof(data), "%t", "injured", victim);
			yourstatus[attacker][victim] = data;

			// Dont show phrase of attackers hits you
			Format(data, sizeof(data), NULL_STRING, victim);
			killerstatus[victim][attacker] = data;

			// Show chat notifications if client wants
			if (cookie_chatmode[attacker]) CPrintToChat(attacker, "%t", "chat", victim, yourstatus[attacker][victim], g_Hitbox[hitgroup], damage);
		}
		else /* player is dead */
		{
			// Show killed victims
			Format(data, sizeof(data), "%t", "killed", victim);
			yourstatus[attacker][victim] = data;

			// And killer's info
			Format(data, sizeof(data), "%t", "killer", victim);
			killerstatus[victim][attacker] = data;

			if (cookie_chatmode[attacker]) CPrintToChat(attacker, "%t", "chat", victim, yourstatus[attacker][victim], g_Hitbox[hitgroup], damage);
		}
	}
}

/* Event_Player_Killed()
 *
 * Called when a player kills another.
 * -------------------------------------------------------------------------------- */
public Event_Player_Killed(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Check if that is not an end of round
	if (roundend == false)
	{
		new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		new victim   = GetClientOfUserId(GetEventInt(event, "victim"));

		if (attacker > 0 && victim > 0)
		{
			// Legitimate kill
			if (GetClientTeam(attacker) != GetClientTeam(victim))
			{
				decl String:buffer[32], String:given[32], String:taken[32];

				// Add kills & deaths for endround stats
				kills[attacker]++;
				deaths[victim]++;

				// NULL_STRING fix issue with unknown characters in a panel
				Format(given, sizeof(given), "%T", "given", victim, damage_temp[victim]);
				Format(taken, sizeof(taken), "%T", "taken", victim);
				Format(buffer, sizeof(buffer), NULL_STRING, victim);

				// Check client's preferences
				if (cookie_deathpanel[victim])
				{
					new Handle:panel = CreatePanel();

					// Show panel if player do any damage
					if (damage_temp[victim] > 0) DrawPanelItem(panel, given);

					for (new i = 1; i <= MaxClients; i++)
					{
						// Check for all damaged victims, otherwise not involved enemies will be shown
						if (IsClientInGame(i) && damage_given[victim][i] > 0)
						{
							// Show names of all victims
							decl String:victims[72], String:victimname[MAX_NAME_LENGTH];
							GetClientName(i, victimname, sizeof(victimname));

							Format(victims, sizeof(victims), "%T", "yourstats", victim, victimname, damage_given[victim][i], hurts[victim][i], yourstatus[victim][i]);
							DrawPanelText(panel, victims);
						}
					}

					// Panel with attackers
					DrawPanelItem(panel, taken);
					for (new i = 1; i <= MaxClients; i++)
					{
						if (IsClientInGame(i) && damage_taken[victim][i] > 0)
						{
							decl String:attackers[72], String:attackername[MAX_NAME_LENGTH];
							GetClientName(i, attackername, sizeof(attackername));

							// Getting attackers data
							Format(attackers, sizeof(attackers), "%T", "enemystats", victim, attackername, damage_taken[victim][i], hits[victim][i], killerstatus[victim][i]);
							DrawPanelText(panel, attackers);
						}
					}

					// Draw panel wit' all results for 7 seconds
					DrawPanelText(panel, buffer);
					SendPanelToClient(panel, victim, Handler_DoNothing, 7);
					CloseHandle(panel);
				}
			}

			// TK
			else
			{
				// Penalty 1 frag to teamkiller and add 1 death to victim
				kills[attacker]--;
				deaths[victim]++;
			}
		}

		// Reset all damage to zero, otherwise panel with all results be always shown
		resethits(victim);
	}
}

/* Event_Point_Captured()
 *
 * When a flag/point is captured.
 * -------------------------------------------------------------------------------- */
public Event_Point_Captured(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client;

	// There may be more than 1 capper
	decl String:cappers[256];
	GetEventString(event, "cappers", cappers, sizeof(cappers));

	for (new i = 0 ; i < strlen(cappers); i++)
	{
		client = cappers[i];

		// For round end stats
		captures[client]++;
	}
}

/* Event_Round_Start()
 *
 * Called when the round starts.
 * -------------------------------------------------------------------------------- */
public Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Round started
	roundend = false;

	// Reset all data
	for (new client = 1; client <= MaxClients; client++)
	{
		// For all players
		if (IsClientInGame(client))
		{
			kills[client]       = 0;
			deaths[client]      = 0;
			headshots[client]   = 0;
			captures[client]    = 0;
			damage_temp[client] = 0;
			damage_summ[client] = 0;

			// Damage & hits needs double index
			for (new i = 1; i <= MaxClients; i++)
			{
				damage_given[client][i] = 0;
				damage_taken[client][i] = 0;
				hits[client][i]         = 0;
				hurts[client][i]        = 0;
			}
		}
	}
}

/* Event_Round_End()
 *
 * Called when a round ends.
 * -------------------------------------------------------------------------------- */
public Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Globals
	new client, mdest;
	roundend = true;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			client = i;

			// Getting most kills & damage from all players to define most destructive
			if (kills[i] > kills[mdest]) mdest = i;
			else if (kills[i] == kills[mdest] && damage_summ[i] > damage_summ[mdest]) mdest = i;

			// Are client wants to see roundend panel?
			if (cookie_resultpanel[client])
			{
				decl String:menutitle[64],
				     String:overallkills[64],
				     String:overalldeaths[64],
				     String:overallheadshots[64],
				     String:overallcaptures[64];

				// Dont show panel if client dont do any action below
				if (kills[client] > 0 || deaths[client] > 0 || headshots[client] > 0 || captures[client] > 0)
				{
					new Handle:panel = CreatePanel();

					// Draw panel as item, so clients will able to close it easily
					Format(menutitle, sizeof(menutitle), "%T:", "roundend", client);
					DrawPanelItem(panel, menutitle);

					Format(overallkills, sizeof(overallkills), "%T", "kills", client, kills[client]);
					if (kills[client] > 0)DrawPanelText(panel, overallkills);

					Format(overalldeaths, sizeof(overalldeaths), "%T", "deaths", client, deaths[client]);
					if (deaths[client] > 0) DrawPanelText(panel, overalldeaths);

					Format(overallheadshots, sizeof(overallheadshots), "%T", "headshots", client, headshots[client]);
					if (headshots[client] > 0) DrawPanelText(panel, overallheadshots);

					Format(overallcaptures, sizeof(overallcaptures), "%T", "captured", client, captures[client]);
					if (captures[client] > 0) DrawPanelText(panel, overallcaptures);

					// Draw panel till bonusround
					SendPanelToClient(panel, client, Handler_DoNothing, 14);
					CloseHandle(panel);
				}
			}
		}
	}

	// Show most destructive player if this function is enabled
	if (GetConVarInt(damagereport_mdest))
	{
		// Most destructive player stats
		if (damage_summ[mdest] > 0)
		{
			// Draw mdest stats (kills, headshots & dmg) depends on value
			switch (GetConVarInt(damagereport_mdest))
			{
				case 1: PrintHintTextToAll    ("%t", "mdest", mdest, kills[mdest], headshots[mdest], damage_summ[mdest]);
				case 2: CPrintToChatAll("{green}%t", "mdest", mdest, kills[mdest], headshots[mdest], damage_summ[mdest]);
			}
		}
	}
}


/**
 * --------------------------------------------------------------------------------
 *     ______                                          __
 *    / ____/___  ____ ___  ____ ___  ____ _____  ____/ /____
 *   / /   / __ \/ __ `__ \/ __ `__ \/ __ `/ __ \/ __  / ___/
 *  / /___/ /_/ / / / / / / / / / / / /_/ / / / / /_/ (__  )
 *  \____/\____/_/ /_/ /_/_/ /_/ /_/\__,_/_/ /_/\__,_/____/
 *
 * --------------------------------------------------------------------------------
*/

/* DamageReportMenu()
 *
 * When client called 'dmgmenu' command.
 * -------------------------------------------------------------------------------- */
public Action:DamageReportMenu(client, args)
{
	// Shows Damage Report settings on command
	ShowMenu(client);

	// Prevents 'unknown command' reply in client console
	return Plugin_Handled;
}

/* DamageReportSelect()
 *
 * Dont closes menu when option selected.
 * -------------------------------------------------------------------------------- */
public DamageReportSelect(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
	// Menu shouldn't disappear on select
	if (action == CookieMenuAction_SelectOption)
		ShowMenu(client);
}


/**
 * --------------------------------------------------------------------------------
 *     ______            __   _
 *    / ____/___  ____  / /__(_)__   ____
 *   / /   / __ \/ __ \/ //_/ / _ \/____/
 *  / /___/ /_/ / /_/ / ,< / /  __/(__ )
 *  \____/\____/\____/_/|_/_/\___/____/
 *
 * --------------------------------------------------------------------------------
*/

/* Handler_MenuDmg()
 *
 * Cookie's main menu.
 * -------------------------------------------------------------------------------- */
public Handler_MenuDmg(Handle:menu, MenuAction:action, param1, param2)
{
	// When client is pressed a button
	if (action == MenuAction_Select)
	{
		// Switch param2
		switch (param2)
		{
			case 0: /* First - chat preferences */
			{
				/* If enabled - be disabled */
				if (cookie_chatmode[param1])
					cookie_chatmode[param1] = false;
				else /* Was disabled now enabled */
					cookie_chatmode[param1] = true;
			}
			case 1: /* Second - report panel */
			{
				if (cookie_deathpanel[param1])
					cookie_deathpanel[param1] = false;
				else
					cookie_deathpanel[param1] = true;
			}
			case 2: /* Third - results panel */
			{
				if (cookie_resultpanel[param1])
					cookie_resultpanel[param1] = false;
				else
					cookie_resultpanel[param1] = true;
			}
		}

		decl String:buffer[32];

		// Save chat settings
		IntToString(cookie_chatmode[param1], buffer, sizeof(buffer));

		// Set the value of a Client preference cookie
		SetClientCookie(param1, dmg_chatprefs, buffer);

		// Save death panel settings
		IntToString(cookie_deathpanel[param1], buffer, sizeof(buffer));
		SetClientCookie(param1, dmg_panelprefs, buffer);

		IntToString(cookie_resultpanel[param1], buffer, sizeof(buffer));
		SetClientCookie(param1, dmg_endroundprefs, buffer);

		// Call a damage report menu
		DamageReportMenu(param1, MENU_TIME_FOREVER);
	}

	// Client pressed exit button - close menu
	else if (action == MenuAction_End) CloseHandle(menu);
}

/* LoadPreferences()
 *
 * Loads client's preferences on connect.
 * -------------------------------------------------------------------------------- */
LoadPreferences(client)
{
	decl String:buffer[32];

	// Retrieve the value of a Client preference cookie (for chat preferences)
	GetClientCookie(client, dmg_chatprefs, buffer, sizeof(buffer));
	if(!StrEqual(buffer, NULL_STRING)) cookie_chatmode[client] = StringToInt(buffer);

	// for death panel
	GetClientCookie(client, dmg_panelprefs, buffer, sizeof(buffer));
	if(!StrEqual(buffer, NULL_STRING)) cookie_deathpanel[client] = StringToInt(buffer);

	GetClientCookie(client, dmg_endroundprefs, buffer, sizeof(buffer));

	// Also retrieve a cookie value
	if(!StrEqual(buffer, NULL_STRING)) cookie_resultpanel[client] = StringToInt(buffer);
}

/* ShowMenu()
 *
 * Damage Report menu.
 * -------------------------------------------------------------------------------- */
ShowMenu(client)
{
	// Creates a new, empty menu using the default style
	new Handle:menu = CreateMenu(Handler_MenuDmg);

	decl String:buffer[100];

	Format(buffer, sizeof(buffer), "%t:", "damagemenu", client);

	// Sets the menu's default title/instruction message
	SetMenuTitle(menu, buffer);

	if (cookie_chatmode[client])
		Format(buffer, sizeof(buffer), "%t", "disable text", client);
	else
		Format(buffer, sizeof(buffer), "%t", "enable text", client);

	// Something must be added on 'AddMenuItem', otherwise Damage Report menu items will not be shown
	AddMenuItem(menu, NULL_STRING, buffer);

	if (cookie_deathpanel[client])
		Format(buffer, sizeof(buffer), "%t", "disable panel", client);
	else
		Format(buffer, sizeof(buffer), "%t", "enable panel", client);

	// For every param#
	AddMenuItem(menu, NULL_STRING, buffer);

	if (cookie_resultpanel[client])
		Format(buffer, sizeof(buffer), "%t", "disable results", client);
	else
		Format(buffer, sizeof(buffer), "%t", "enable results", client);

	AddMenuItem(menu, NULL_STRING, buffer);

	// Sets whether or not the menu has an exit button
	SetMenuExitButton(menu, true);

	// Displays cookies menu until client close it
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}


/**
 * --------------------------------------------------------------------------------
 *      __  ____
 *     /  |/  (_)__________
 *    / /|_/ / // ___/ ___/
 *   / /  / / /(__  ) /__
 *  /_/  /_/_//____/\___/
 *
 * --------------------------------------------------------------------------------
*/

/* resetall()
 *
 * Reset all player's damage & other stats.
 * -------------------------------------------------------------------------------- */
resetall(client)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		// Because every hit/damage is indexed
		if (IsClientInGame(client))
		{
			kills[client]           = 0;
			deaths[client]          = 0;
			headshots[client]       = 0;
			captures[client]        = 0;
			damage_temp[client]     = 0;
			damage_summ[client]     = 0;
			damage_given[client][i] = 0;
			damage_taken[client][i] = 0;
			hits[client][i]         = 0;
			hurts[client][i]        = 0;
		}
	}
}

/* resethits()
 *
 * Reset stats of damage & hits.
 * -------------------------------------------------------------------------------- */
resethits(client)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(client))
		{
			damage_temp[client]     = 0;

			// If plugin should not show most destructive player, reset damage done by most destructive player
			if (!GetConVarInt(damagereport_mdest))
				damage_summ[client] = 0;

			// Becaue all damage/hits is actually indexed
			damage_given[client][i] = 0;
			damage_taken[client][i] = 0;
			hits[client][i]         = 0;
			hurts[client][i]        = 0;
		}
	}
}

/* Timer_WelcomePlayer()
 *
 * Shows welcome message to a client.
 * -------------------------------------------------------------------------------- */
public Action:Timer_WelcomePlayer(Handle:timer, any:client)
{
	// Timer expired, kill it now
	damagereport_info[client] = INVALID_HANDLE;
	if (IsClientInGame(client)) CPrintToChat(client, "%t", "welcome");
}

/* Handler_DoNothing()
 *
 * Empty menu handler.
 * -------------------------------------------------------------------------------- */
public Handler_DoNothing(Handle:menu, MenuAction:action, param1, param2){}