#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <ttt_shop>
#include <ttt>
#include <multicolors>

#define SHORT_NAME "hurtshot"

#define PLUGIN_NAME TTT_PLUGIN_NAME ... " - Items: Hurtshot"

/* ConVars of the plugin */
ConVar cvPrice;
ConVar cvCount;
ConVar cvPrio;
ConVar cvDmg;
ConVar cvName;
ConVar cvTag;
/* Globals vars */
int gPlayersCount[MAXPLAYERS + 1] = { 0, ... }; // -> How much times they bought the item
bool gPlayersHasHS[MAXPLAYERS + 1] = { false, ... }; // -> Hurtshot mode enabled ?
ArrayList gListHS; // -> List of entities ID

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = TTT_PLUGIN_AUTHOR,
	description = TTT_PLUGIN_DESCRIPTION,
	version = TTT_PLUGIN_VERSION,
	url = TTT_PLUGIN_URL
};

public void OnPluginStart()
{
	TTT_IsGameCSGO();

	LoadTranslations("ttt.phrases");
	
	StartConfig("hurtshot");
	CreateConVar("hurtshot_version", TTT_PLUGIN_VERSION, TTT_PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_REPLICATED);
	cvName = AutoExecConfig_CreateConVar("hurts_name", "Hurtshot", "The name of the Hurtshot in the Shop");
	cvPrice = AutoExecConfig_CreateConVar("hurts_traitor_price", "5000", "The amount of credits for hurtshots costs as traitor. 0 to disable.");
	cvCount = AutoExecConfig_CreateConVar("hurts_traitor_count", "1", "The amount of usages for hurtshots per round as traitor. 0 to disable.");
	cvPrio = AutoExecConfig_CreateConVar("hurts_traitor_sort_prio", "0", "The sorting priority of the hurtshots (Traitor) in the shop menu.");
	cvDmg = AutoExecConfig_CreateConVar("hurts_traitor_damage", "50", "The damage of the hurtshot");
	EndConfig();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("weapon_fire", Event_Fire, EventHookMode_Pre);
	
	gListHS = new ArrayList();
	
	cvTag = FindConVar("ttt_plugin_tag");
}

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, EquipHS);
	SDKHook(client, SDKHook_WeaponDropPost, DropHS);		
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	/*
		Resetting client inventory
	*/
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (TTT_IsClientValid(client))
		ResetHurtshot(client);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	gListHS.Clear(); // -> Resetting the list of entities ID
}

public Action Event_Fire(Event event, const char[] name, bool dontBroadcast)
{
	/*
		Checking if the client is using the hurshot.
		IF the client is using an healthshot and if he is has hurtshot mode enabled,
		THEN we calculate the health he would lose and create the right timer,
		ELSE we do nothing.
	*/
	int client = GetClientOfUserId(event.GetInt("userid"));
	char weapon[64];
	GetEventString(event, "weapon", weapon, sizeof(weapon));
	
	if (TTT_IsClientValid(client) && StrEqual(weapon, "weapon_healthshot"))
	{
		if (gPlayersHasHS[client] && GetClientHealth(client) < 100)
		{
			DataPack data = new DataPack();
			int calcul = GetClientHealth(client) - (cvDmg.IntValue);
			if (calcul <= 0)
				CreateTimer(1.0, ChangeHP, data);		
			else
				CreateTimer(2.0, ChangeHP, data);	
			data.WriteCell(client);
			data.WriteCell(calcul);	
			gPlayersHasHS[client] = false;			
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

Action EquipHS(int client, int weapon)
{
	/*
		Enabling the hurtshot mode on the client.
	*/
	if (TTT_IsClientValid(client) && gListHS.FindValue(weapon) != -1)
		gPlayersHasHS[client] = true;
	return Plugin_Handled;
}

Action DropHS(int client, int weapon)
{
	/*
		Disabling the hurtshot mode on the client.
	*/	
	if (TTT_IsClientValid(client) && gListHS.FindValue(weapon) != -1)
		gPlayersHasHS[client] = false;	
	return Plugin_Handled;
}

public Action ChangeHP(Handle timer, Handle data)
{
	/*
		Timer to change the health of the client
	*/
	ResetPack(data);
	int client = ReadPackCell(data);
	int calcul = ReadPackCell(data);
	
	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if (calcul <= 0) // -> Health <= 0
			ForcePlayerSuicide(client);
		else
			SetEntityHealth(client, calcul);
	}
	delete data; // -> Delete the data pack.
	return Plugin_Handled;
}

public void OnConfigsExecuted()
{
	/*
		Add the item to the TTT shop.
	*/
	char itemName[128];
	cvName.GetString(itemName, sizeof(itemName));
	TTT_RegisterCustomItem(SHORT_NAME, itemName, cvPrice.IntValue, TTT_TEAM_TRAITOR, cvPrio.IntValue);
}

public Action TTT_OnItemPurchased(int client, const char[] itemshort, bool count)
{
	/*
		Check if the client is valid and if he is a traitor.
		IF he bought more than enought,
		THEN we stop,
		ELSE we give the healthshot and drop it instantly.
		
	*/
	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if (StrEqual(itemshort, SHORT_NAME, false))
		{
			int role = TTT_GetClientRole(client);
			
			if (role != TTT_TEAM_TRAITOR)
			{
				return Plugin_Stop;
			}				

			if (role == TTT_TEAM_TRAITOR && gPlayersCount[client] >= cvCount.IntValue)
			{
				char tag[128];
				char itemName[128];
				cvTag.GetString(tag, sizeof(tag));
				cvName.GetString(itemName, sizeof(itemName));
				CPrintToChat(client, "%s %t", tag, "Bought All", itemName, cvCount.IntValue);
				return Plugin_Stop;
			}
			
			int ent = GivePlayerItem(client, "weapon_healthshot");
			gListHS.Push(ent); // -> Adding the entity id to the global list
			CS_DropWeapon(client, ent, false, false); // -> Drop the hurtshot to enable it

			if (count)
				gPlayersCount[client]++;
		}
	}
	return Plugin_Continue;
}

void ResetHurtshot(int client)
{
	/* 
		Reset client inventory
	*/
	gPlayersCount[client] = 0;
	gPlayersHasHS[client] = false;	
}