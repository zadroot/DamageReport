/**
* DoD:S Damage Report by Root
*
* Description:
*   When a client dies, show how many hits client do and take with damage stats in a menu.
*   Also show most destructive player & overall player stats at end of the round.
*
* Version 1.6
* Changelog & more info at http://goo.gl/4nKhJ
*/

// ====[ SEMICOLON ]================================================================
#pragma semicolon 1

// ====[ INCLUDES ]=================================================================
#include <sourcemod>
#include <clientprefs>
#include <morecolors> // 1.6 update

// ====[ CONSTANTS ]================================================================
#define PLUGIN_NAME      "DoD:S Damage Report"
#define PLUGIN_VERSION   "1.6"

#define DOD_MAXPLAYERS   33
#define DOD_MAXHITGROUPS 7

// ====[ VARIABLES ]================================================================
new	Handle:damagereport_enable, // ConVars
	Handle:damagereport_mdest,
	Handle:damagereport_info[DOD_MAXPLAYERS + 1], // Welcome timer
	Handle:dmg_chatprefs, // Clientprefs
	Handle:dmg_panelprefs,
	Handle:dmg_endroundprefs,
	cookie_chatmode[DOD_MAXPLAYERS + 1]    = {false, ...}, // Cookies
	cookie_deathpanel[DOD_MAXPLAYERS + 1]  = {false, ...},
	cookie_resultpanel[DOD_MAXPLAYERS + 1] = {true,  ...},
	bool:roundend = false, // Round end stats
	kills[DOD_MAXPLAYERS + 1],
	deaths[DOD_MAXPLAYERS + 1],
	headshots[DOD_MAXPLAYERS + 1],
	captures[DOD_MAXPLAYERS + 1],
	damage_temp[DOD_MAXPLAYERS + 1], // Damage (given, taken & summary)
	damage_summ[DOD_MAXPLAYERS + 1],
	damage_given[DOD_MAXPLAYERS + 1][DOD_MAXPLAYERS + 1],
	damage_taken[DOD_MAXPLAYERS + 1][DOD_MAXPLAYERS + 1],
	hits[DOD_MAXPLAYERS + 1][DOD_MAXPLAYERS + 1], // Hits data
	hurts[DOD_MAXPLAYERS + 1][DOD_MAXPLAYERS + 1],
	String:yourstatus[DOD_MAXPLAYERS + 1][DOD_MAXPLAYERS + 1][32], // Player status (killed or injured)
	String:killerstatus[DOD_MAXPLAYERS + 1][DOD_MAXPLAYERS + 1][32];

// ====[ PLUGIN ]===================================================================
public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "Shows damage stats, round stats & most destructive player *clientprefs",
	version     = PLUGIN_VERSION,
	url         = "http://dodsplugins.com/"
};


/**
 * ---------------------------------------------------------------------------------
 *     ____           ______                  __  _
 *    / __ \____     / ____/__  ______  _____/ /_(_)____  ____  _____
 *   / / / / __ \   / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *  / /_/ / / / /  / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *  \____/_/ /_/  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * ---------------------------------------------------------------------------------
*/

/* OnPluginStart()
 *
 * When the plugin starts up.
 * --------------------------------------------------------------------------------- */
public OnPluginStart()
{
	// Create ConVars
	CreateConVar("dod_damagestats_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED);
	damagereport_enable = CreateConVar("dod_damage_report",       "1", "Whether or not enable Damage Report plugin",                                             FCVAR_PLUGIN, true, 0.0, true, 1.0);
	damagereport_mdest  = CreateConVar("dod_damage_report_mdest", "2", "Determines where to show most destructive player stats:\n1 = In hint\n2 = In chat area", FCVAR_PLUGIN, true, 0.0, true, 2.0);

	// Hook ConVar changing
	HookConVarChange(damagereport_enable, OnConVarChange);

	// Hook player events
	HookEvent("dod_stats_player_damage", Event_Player_Killed);

	// Hook game events
	HookEvent("dod_point_captured", Event_Point_Captured);
	HookEvent("dod_round_start",    Event_Round_Start);
	HookEvent("dod_round_win",      Event_Round_End, EventHookMode_PostNoCopy);
	HookEvent("dod_game_over",      Event_Round_End, EventHookMode_PostNoCopy);

	// Create/register damage report client command
	RegConsoleCmd("dmg", DamageReportMenu);

	// Load all translations
	LoadTranslations("damage_report.phrases");

	// Creates a new Client preference cookies
	dmg_chatprefs     = RegClientCookie("Chat preferences",    "Damage Report", CookieAccess_Private);
	dmg_panelprefs    = RegClientCookie("Panel preferences",   "Damage Report", CookieAccess_Private);
	dmg_endroundprefs = RegClientCookie("Results preferences", "Damage Report", CookieAccess_Private);

	// Show "Damge Report" item in cookie settings menu
	decl String:title[64]; Format(title, sizeof(title), "%t", "damagemenu");

	// Add clientprefs item called "Damage Report"
	if (LibraryExists("clientprefs")) SetCookieMenuItem(DamageReportSelect, 0, title);
}

/* OnConVarChange()
 *
 * Called when a convar's value is changed.
 * --------------------------------------------------------------------------------- */
public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// Convert a string to an integer
	switch (StringToInt(newValue))
	{
		// Unhook all needed events on disabling
		case false:
		{
			UnhookEvent("dod_stats_player_damage", Event_Player_Killed);
			UnhookEvent("dod_point_captured",      Event_Point_Captured);
			UnhookEvent("dod_round_start",         Event_Round_Start);
			UnhookEvent("dod_round_win",           Event_Round_End, EventHookMode_PostNoCopy);
			UnhookEvent("dod_game_over",           Event_Round_End, EventHookMode_PostNoCopy);
		}

		case true:
		{
			HookEvent("dod_stats_player_damage", Event_Player_Killed);
			HookEvent("dod_point_captured",      Event_Point_Captured);
			HookEvent("dod_round_start",         Event_Round_Start);
			HookEvent("dod_round_win",           Event_Round_End, EventHookMode_PostNoCopy);
			HookEvent("dod_game_over",           Event_Round_End, EventHookMode_PostNoCopy);
		}
	}
}

/* OnClientPutInServer()
 *
 * Called when a client is entering the game.
 * --------------------------------------------------------------------------------- */
public OnClientPutInServer(client)
{
	// Make sure client is valid
	if (IsValidClient(client))
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
 * --------------------------------------------------------------------------------- */
public OnClientCookiesCached(client)
{
	// If cookies was not ready until connection, wait until OnClientCookiesCached()
	if (IsValidClient(client)) LoadPreferences(client);
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * --------------------------------------------------------------------------------- */
public OnClientDisconnect(client)
{
	// Client should be valid
	if (IsValidClient(client))
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
 * ---------------------------------------------------------------------------------
 *      ______                  __
 *     / ____/_   _____  ____  / /______
 *    / __/  | | / / _ \/ __ \/ __/ ___/
 *   / /___  | |/ /  __/ / / / /_(__  )
 *  /_____/  |___/\___/_/ /_/\__/____/
 *
 * ---------------------------------------------------------------------------------
*/

/* Event_Player_Killed()
 *
 * Called when a player taking damage and dying.
 * --------------------------------------------------------------------------------- */
public Event_Player_Killed(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (roundend == false)
	{
		// Event stuff
		new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		new victim   = GetClientOfUserId(GetEventInt(event, "victim"));
		new damage   = GetEventInt(event, "damage");
		new hitgroup = GetEventInt(event, "hitgroup");

		// Make sure attacker and victim is valid
		if (attacker > 0 && victim > 0 && GetClientTeam(attacker) != GetClientTeam(victim))
		{
			// 7 hitboxes is avalible
			decl String:Hitbox[DOD_MAXHITGROUPS + 1][32], String:data[32], String:color[10];

			// I'd like to use all features of 'more colors' since its having team colors for DoD:S
			Format(color, sizeof(color), "%s", GetClientTeam(victim) == 2 ? "{allies}" : "{axis}");

			// Hitgroup definitions
			Format(data, sizeof(data), "%t", "hitbox0", victim); Hitbox[0] = data; // Generic
			Format(data, sizeof(data), "%t", "hitbox1", victim); Hitbox[1] = data; // Head
			Format(data, sizeof(data), "%t", "hitbox2", victim); Hitbox[2] = data; // Upper chest
			Format(data, sizeof(data), "%t", "hitbox3", victim); Hitbox[3] = data; // Lower Chest
			Format(data, sizeof(data), "%t", "hitbox4", victim); Hitbox[4] = data; // Left arm
			Format(data, sizeof(data), "%t", "hitbox5", victim); Hitbox[5] = data; // Right arm
			Format(data, sizeof(data), "%t", "hitbox6", victim); Hitbox[6] = data; // Left leg
			Format(data, sizeof(data), "%t", "hitbox7", victim); Hitbox[7] = data; // Right Leg

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

			// GetEventInt(event, "health") is not working here. So I'd better do GetClientHealth
			if (GetClientHealth(victim) > 0)
			{
				// If player was not killed - show status
				Format(data, sizeof(data), "%t", "injured", victim);
				yourstatus[attacker][victim] = data;

				// Dont show 'injured you' phrase
				Format(data, sizeof(data), NULL_STRING, victim);
				killerstatus[victim][attacker] = data;

				// Show chat notifications if client wants
				if (cookie_chatmode[attacker])
					CPrintToChat(attacker, "%t", "chat", color, victim, yourstatus[attacker][victim], Hitbox[hitgroup], damage);
			}
			else
			{
				decl String:buffer[32], String:given[32], String:taken[32];

				// Add kills & deaths for endround stats
				kills[attacker]++;
				deaths[victim]++;

				// NULL_STRING fix issue with unknown characters in a panel
				Format(given,  sizeof(given), "%T", "given", victim, damage_temp[victim]);
				Format(taken,  sizeof(taken), "%T", "taken", victim);
				Format(buffer, sizeof(buffer), NULL_STRING,  victim);

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

					// Draw panel wit' all results for 8 seconds
					DrawPanelText(panel, buffer);
					SendPanelToClient(panel, victim, Handler_DoNothing, 8);
					CloseHandle(panel);
				}

				// Show killed victims
				Format(data, sizeof(data), "%t", "killed", victim);
				yourstatus[attacker][victim] = data;

				// And killer's info
				Format(data, sizeof(data), "%t", "killer", victim);
				killerstatus[victim][attacker] = data;

				// Headshot
				if (hitgroup == 1) headshots[attacker]++;

				if (cookie_chatmode[attacker])
					CPrintToChat(attacker, "%t", "chat", color, victim, yourstatus[attacker][victim], Hitbox[hitgroup], damage);

				// Reset all damage to zero, otherwise panel with all results be always shown
				resethits(victim);
			}
		}
	}
}

/* Event_Point_Captured()
 *
 * When a flag/point is captured.
 * --------------------------------------------------------------------------------- */
public Event_Point_Captured(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client;

	// There may be more than 1 capper
	decl String:cappers[256];
	GetEventString(event, "cappers", cappers, sizeof(cappers));

	for (new i = 0 ; i < strlen(cappers); i++)
	{
		client = cappers[i];
		captures[client]++;
	}
}

/* Event_Round_Start()
 *
 * Called when the round starts.
 * --------------------------------------------------------------------------------- */
public Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Round started
	roundend = false;

	// Reset all data
	for (new client = 1; client <= MaxClients; client++) resetall(client);
}

/* Event_Round_End()
 *
 * Called when a round ends.
 * --------------------------------------------------------------------------------- */
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
				     String:overallcaptures[64],
				     String:overalldamage[64];

				// Dont show panel if client dont do any action below
				if (kills[client] > 0
				|| deaths[client] > 0
				|| headshots[client] > 0
				|| captures[client] > 0)
				{
					new Handle:panel = CreatePanel();

					// Draw panel as item, so clients will able to close it easily
					Format(menutitle, sizeof(menutitle), "%T:", "roundend", client);
					DrawPanelItem(panel, menutitle);

					// If player is killed at least 1 player - add kill stats
					if (kills[client] > 0)
					{
						Format(overallkills, sizeof(overallkills), "%T", "kills", client, kills[client]);
						DrawPanelText(panel, overallkills);
					}
					if (deaths[client] > 0)
					{
						// Format a string for translations
						Format(overalldeaths, sizeof(overalldeaths), "%T", "deaths", client, deaths[client]);
						DrawPanelText(panel, overalldeaths);
					}
					if (headshots[client] > 0)
					{
						Format(overallheadshots, sizeof(overallheadshots), "%T", "headshots", client, headshots[client]);

						// And draws a raw line of text on a panel
						DrawPanelText(panel, overallheadshots);
					}
					if (damage_summ[client] > 0)
					{
						Format(overalldamage, sizeof(overalldamage), "%T", "alldamage", client, damage_summ[client]);
						DrawPanelText(panel, overalldamage);
					}
					if (captures[client] > 0)
					{
						Format(overallcaptures, sizeof(overallcaptures), "%T", "captured", client, captures[client]);
						DrawPanelText(panel, overallcaptures);
					}

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
			decl String:color[10];

			// Lets colorize chat message depends on most destructive player team
			Format(color, sizeof(color), "%s", GetClientTeam(mdest) == 2 ? "{allies}" : "{axis}");

			// Draw mdest stats (kills, headshots & dmg) depends on value
			switch (GetConVarInt(damagereport_mdest))
			{
				case 1: PrintHintTextToAll("%t", "mdest", mdest, kills[mdest], headshots[mdest], damage_summ[mdest]);
				case 2: CPrintToChatAll("%s%t",  color, "mdest",  mdest, kills[mdest], headshots[mdest], damage_summ[mdest]);
			}
		}
	}
}


/**
 * ---------------------------------------------------------------------------------
 *     ______                                          __
 *    / ____/___  ____ ___  ____ ___  ____ _____  ____/ /____
 *   / /   / __ \/ __ `__ \/ __ `__ \/ __ `/ __ \/ __  / ___/
 *  / /___/ /_/ / / / / / / / / / / / /_/ / / / / /_/ (__  )
 *  \____/\____/_/ /_/ /_/_/ /_/ /_/\__,_/_/ /_/\__,_/____/
 *
 * ---------------------------------------------------------------------------------
*/

/* DamageReportMenu()
 *
 * When client called 'dmgmenu' command.
 * --------------------------------------------------------------------------------- */
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
 * --------------------------------------------------------------------------------- */
public DamageReportSelect(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
{
	// Menu shouldn't disappear on select
	if (action == CookieMenuAction_SelectOption)
		ShowMenu(client);
}


/**
 * ---------------------------------------------------------------------------------
 *     ______            __   _
 *    / ____/___  ____  / /__(_)__   ____
 *   / /   / __ \/ __ \/ //_/ / _ \/____/
 *  / /___/ /_/ / /_/ / ,< / /  __/(__ )
 *  \____/\____/\____/_/|_/_/\___/____/
 *
 * ---------------------------------------------------------------------------------
*/

/* Handler_MenuDmg()
 *
 * Cookie's main menu.
 * --------------------------------------------------------------------------------- */
public Handler_MenuDmg(Handle:menu, MenuAction:action, client, param)
{
	// When client is pressed a button
	if (action == MenuAction_Select)
	{
		// Get param
		switch (param)
		{
			case 0: /* First - chat preferences */
			{
				/* If enabled - be disabled and vice versa */
				if (cookie_chatmode[client])
					 cookie_chatmode[client] = false;
				else cookie_chatmode[client] = true;
			}
			case 1: /* Second - damage report panel */
			{
				if (cookie_deathpanel[client])
					 cookie_deathpanel[client] = false;
				else cookie_deathpanel[client] = true;
			}
			case 2: /* Third - results panel prefs */
			{
				if (cookie_resultpanel[client])
					 cookie_resultpanel[client] = false;
				else cookie_resultpanel[client] = true;
			}
		}

		// Buffer needed to store integer
		decl String:buffer[2];

		// Save chat settings
		IntToString(cookie_chatmode[client], buffer, sizeof(buffer));

		// Set the value of a Client preference cookie
		SetClientCookie(client, dmg_chatprefs, buffer);

		// Save death panel settings
		IntToString(cookie_deathpanel[client], buffer, sizeof(buffer));
		SetClientCookie(client, dmg_panelprefs, buffer);

		IntToString(cookie_resultpanel[client], buffer, sizeof(buffer));
		SetClientCookie(client, dmg_endroundprefs, buffer);

		// Call a damage report menu
		DamageReportMenu(client, MENU_TIME_FOREVER);
	}

	// Client pressed exit button - close menu
	else if (action == MenuAction_End) CloseHandle(menu);
}

/* LoadPreferences()
 *
 * Loads client's preferences on connect.
 * --------------------------------------------------------------------------------- */
LoadPreferences(client)
{
	decl String:buffer[2];

	// Retrieve the value of a Client preference cookie (for chat preferences)
	GetClientCookie(client, dmg_chatprefs, buffer, sizeof(buffer));
	if(!StrEqual(buffer, NULL_STRING)) cookie_chatmode[client] = StringToInt(buffer);

	// for death panel
	GetClientCookie(client, dmg_panelprefs, buffer, sizeof(buffer));
	if(!StrEqual(buffer, NULL_STRING)) cookie_deathpanel[client] = StringToInt(buffer);

	GetClientCookie(client, dmg_endroundprefs, buffer, sizeof(buffer));

	// Convert value
	if(!StrEqual(buffer, NULL_STRING)) cookie_resultpanel[client] = StringToInt(buffer);
}

/* ShowMenu()
 *
 * Damage Report menu.
 * --------------------------------------------------------------------------------- */
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

	// For every param
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
 * ---------------------------------------------------------------------------------
 *      __  ____
 *     /  |/  (_)__________
 *    / /|_/ / // ___/ ___/
 *   / /  / / /(__  ) /__
 *  /_/  /_/_//____/\___/
 *
 * ---------------------------------------------------------------------------------
*/

/* resetall()
 *
 * Reset all player's damage & other stats.
 * --------------------------------------------------------------------------------- */
resetall(client)
{
	if (IsClientInGame(client))
	{
		kills[client]       = 0;
		deaths[client]      = 0;
		headshots[client]   = 0;
		captures[client]    = 0;
		damage_temp[client] = 0;
		damage_summ[client] = 0;

		// Because victims was also affected
		for (new i = 1; i <= MaxClients; i++)
		{
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
 * --------------------------------------------------------------------------------- */
resethits(client)
{
	if (IsClientInGame(client))
	{
		damage_temp[client] = 0;

		for (new i = 1; i <= MaxClients; i++)
		{
			// Becaue all damage/hits is actually have done on all victims
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
 * --------------------------------------------------------------------------------- */
public Action:Timer_WelcomePlayer(Handle:timer, any:client)
{
	// Timer expired - kill timer
	damagereport_info[client] = INVALID_HANDLE;
	if (IsClientInGame(client)) CPrintToChat(client, "%t", "welcome");
}

/* Handler_DoNothing()
 *
 * Empty menu handler.
 * --------------------------------------------------------------------------------- */
public Handler_DoNothing(Handle:menu, MenuAction:action, client, param){}

/* IsValidClient()
 *
 * Checks if a client is valid.
 * --------------------------------------------------------------------------------- */
bool:IsValidClient(client) return (client > 0 && !IsFakeClient(client)) ? true : false;