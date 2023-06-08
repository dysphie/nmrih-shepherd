#include <sourcemod>
#include <sdktools>
#include <morecolors>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_PREFIX	"[Shepherd] "
#define MAX_EDICTS		(1 << 11)

#define OBS_MODE_IN_EYE 4
#define OBS_MODE_CHASE	5
#define OBS_MODE_POI	6

#define NMR_MAXPLAYERS	9

ArrayList g_PreviewingTriggers[NMR_MAXPLAYERS + 1];
bool	  g_Touched[MAX_EDICTS + 1];

int		  offs_m_hTouchingEntities = -1;
int		  g_LaserIndex;
int		  g_HaloIndex;

ConVar	  cvHighlightTrigger;
ConVar	  cvDefaultAction;
ConVar	  cvDefaultSeconds;
ConVar	  cvSound;

public Plugin myinfo =
{
	name		= "Shepherd",
	author		= "Dysphie",
	description = "Helps round progression by tracking and managing missing players",
	version		= "1.0.0",
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("GetColoredName");
	return APLRes_Success;
}

ArrayList g_AutoTriggers;

enum TriggerAction
{
	TriggerAction_Invalid = -1,
	TriggerAction_Teleport,
	TriggerAction_TeleportStrip,
	TriggerAction_Kill
};

enum struct AutoTrigger
{
	char		  targetname[128];
	int			  hammerID;
	TriggerAction type;
	int			  seconds;
}

enum struct TriggerPreview
{
	float mins[3];
	float maxs[3];
	float pos[3];
	char  targetname[128];
	int	  hammerID;
	int	  possibleIndex;
	int	  r;
	int	  g;
	int	  b;
}

public void OnPluginStart()
{
	LoadTranslations("shepherd.phrases");
	GameData gamedata		 = new GameData("shepherd.games");
	offs_m_hTouchingEntities = GetOffsetOrFail(gamedata, "CBaseTrigger::m_hTouchingEntities");
	delete gamedata;

	g_AutoTriggers	= new ArrayList(sizeof(AutoTrigger));

	cvSound			= CreateConVar("sm_shepherd_ultimatum_sound", "ui/challenge_checkpoint.wav");

	cvDefaultAction = CreateConVar("sm_shepherd_ultimatum_default_action", "tp",
								   "Default action to take on missing players when no action type is specified via command." ... "tp = Teleport, kill = Kill, strip = Strip weapons and teleport");
	cvDefaultAction.AddChangeHook(OnCvarDefaultActionChanged);

	cvDefaultSeconds   = CreateConVar("sm_shepherd_ultimatum_default_seconds", "120",
									  "Default waiting time, in seconds, for missing players when no duration is specified via command");

	cvHighlightTrigger = CreateConVar("sm_shepherd_highlight_bounds", "1",
									  "Whether to highlight the checkpoint's bounding box during ultimatums");

	RegConsoleCmd("sm_missing", Cmd_Missing, "Displays the names of players who are absent from areas that require the whole team");

	RegAdminCmd("sm_ultimatum", Cmd_Ultimatum, ADMFLAG_SLAY);
	RegAdminCmd("sm_ult", Cmd_Ultimatum, ADMFLAG_SLAY);

	RegAdminCmd("sm_checkpoints", Cmd_PreviewMode, ADMFLAG_ROOT);

	HookEntityOutput("trigger_allplayer", "OnStartTouch", OnStartTouch);

	AutoExecConfig(true, "shepherd");
}

void OnCvarDefaultActionChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (ActionNameToEnum(newValue, false) == TriggerAction_Invalid)
	{
		PrintToServer("Invalid value '%s', reverting to old value", newValue);
		convar.SetString(oldValue);
	}
}

int GetAliveCount()
{
	int count = 0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsPlayerAlive(client))
		{
			count++;
		}
	}

	return count;
}

void OnStartTouch(const char[] output, int trigger, int activator, float delay)
{
	if (!IsEntityPlayer(activator) || g_Touched[trigger] || GetAliveCount() < 2)
	{
		PrintToServer("g_Touched[trigger] || GetAliveCount() < 2");
		return;
	}

	int			hammerID = GetEntityHammerID(trigger);

	AutoTrigger data;
	if (!hammerID || !GetAutoTriggerByHammerID(hammerID, data))
	{
		return;
	}

	BeginUltimatum(trigger, activator, data.seconds, data.type);
	g_Touched[trigger] = true;
}

bool IsEntityPlayer(int entity)
{
	return 0 < entity <= MaxClients;
}

int GetEntityHammerID(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_iHammerID");
}

void LoadTriggersFromConfig()
{
	Regex g_CfgRegex = new Regex("(\\w+)\\s+(\\d+)\\s+(\\d+)\\s+(tp|kill|strip|default)");

	g_AutoTriggers.Clear();

	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/shepherd_triggers.txt");

	File f = OpenFile(path, "r");
	if (!f)
	{
		LogError("Failed to open %s", path);
		return;
	}

	int	 count = 0;

	char line[4096];
	while (f.ReadLine(line, sizeof(line)))
	{
		TrimString(line);

		// Ignore empty space and comments
		if (!line[0] || strncmp(line, "//", 2) == 0)
		{
			continue;
		}

		if (g_CfgRegex.Match(line) == -1)
		{
			LogError("Invalid line: %s", line);
			continue;
		}

		char mapName[PLATFORM_MAX_PATH];
		g_CfgRegex.GetSubString(1, mapName, sizeof(mapName));

		if (!StrEqual(mapName, currentMap, false))
		{
			continue;
		}

		AutoTrigger autoTrigger;

		char		triggerID[12];
		g_CfgRegex.GetSubString(2, triggerID, sizeof(triggerID));

		char seconds[12];
		g_CfgRegex.GetSubString(3, seconds, sizeof(seconds));

		char action[12];
		g_CfgRegex.GetSubString(4, action, sizeof(action));

		autoTrigger.hammerID = StringToInt(triggerID);
		autoTrigger.seconds	 = StringToInt(seconds);
		autoTrigger.type	 = ActionNameToEnum(action);

		g_AutoTriggers.PushArray(autoTrigger);

		count++;
	}

	// LogMessage(PLUGIN_PREFIX... "Loaded %d auto-triggers", count);
	delete f;
	delete g_CfgRegex;
}

bool GetAutoTriggerByHammerID(int id, AutoTrigger data)
{
	int idx = g_AutoTriggers.FindValue(id, AutoTrigger::hammerID);
	if (idx != -1)
	{
		g_AutoTriggers.GetArray(idx, data);
		return true;
	}

	return false;
}

TriggerAction ActionNameToEnum(const char[] actionName, bool allowDefault = true)
{
	if (StrEqual(actionName, "tp", false))
	{
		return TriggerAction_Teleport;
	}

	if (StrEqual(actionName, "kill", false))
	{
		return TriggerAction_Kill;
	}

	if (StrEqual(actionName, "strip", false))
	{
		return TriggerAction_TeleportStrip;
	}

	if (allowDefault && StrEqual(actionName, "default", false))
	{
		return GetDefaultAction();
	}

	return TriggerAction_Invalid;
}

public void OnEntityDestroyed(int entity)
{
	if (0 < entity < sizeof(g_Touched))
	{
		g_Touched[entity] = false;
	}
}

public void OnMapEnd()
{
	g_AutoTriggers.Clear();
}

public void OnMapStart()
{
	LoadTriggersFromConfig();

	g_LaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_HaloIndex	 = PrecacheModel("materials/sprites/halo01.vmt");

	char ultSound[PLATFORM_MAX_PATH];
	cvSound.GetString(ultSound, sizeof(ultSound));

	if (ultSound[0])
	{
		PrecacheSound(ultSound);
	}
}

int GetObserverTarget(int client)
{
	int obsMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
	if (obsMode == OBS_MODE_IN_EYE || obsMode == OBS_MODE_CHASE || obsMode == OBS_MODE_POI)
	{
		int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
		if (target != client && IsEntityPlayer(target) && IsPlayerAlive(target))
		{
			return target;
		}
	}
	return -1;
}

int GetCommandTarget(int issuer, int arg)
{
	int	 target = issuer;

	char cmdTarget[MAX_TARGET_LENGTH];
	if (GetCmdArg(arg, cmdTarget, sizeof(cmdTarget)))
	{
		target = FindTarget(issuer, cmdTarget);
	}
	else if (!issuer)
	{
		return -1;
	}
	else if (!IsPlayerAlive(issuer)) {
		target = GetObserverTarget(issuer);
	}

	return target;
}

Action Cmd_Ultimatum(int issuer, int args)
{
	int target = GetCommandTarget(issuer, 1);
	if (target == -1)
	{
		return Plugin_Handled;
	}

	int seconds = cvDefaultSeconds.IntValue;
	if (args >= 2)
	{
		seconds = GetCmdArgInt(2);
	}

	TriggerAction action = GetDefaultAction();

	if (args >= 3)
	{
		char actionName[32];
		GetCmdArg(3, actionName, sizeof(actionName));
		action = ActionNameToEnum(actionName);
		if (action == TriggerAction_Invalid)
		{
			return ReplyBadCommandUsage(issuer);
		}
	}

	int trigger = FindTrigger(target);
	if (trigger == -1)
	{
		return ReplyNotInsideTrigger(issuer, target);
	}

	BeginUltimatum(trigger, target, seconds, action);
	return Plugin_Handled;
}

TriggerAction GetDefaultAction()
{
	char cvarValue[32];
	cvDefaultAction.GetString(cvarValue, sizeof(cvarValue));
	TriggerAction action = ActionNameToEnum(cvarValue);
	return action == TriggerAction_Invalid ? TriggerAction_Teleport : action;
}

void GetEntityCenter(int entity, float center[3])
{
	float mins[3], maxs[3], pos[3];
	GetEntityMins(entity, mins);
	GetEntityMaxs(entity, maxs);
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", pos);

	center[0] = pos[0] + (mins[0] + maxs[0]) / 2.0;
	center[1] = pos[1] + (mins[1] + maxs[1]) / 2.0;
	center[2] = pos[2] + (mins[2] + maxs[2]) / 2.0;
}

void GetEntityMins(int entity, float mins[3])
{
	GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);
}

void GetEntityMaxs(int entity, float maxs[3])
{
	GetEntPropVector(entity, Prop_Data, "m_vecMaxs", maxs);
}

void RemoveWorldTextAll(int entity)
{
	Handle	msg = StartMessageAll("RemovePointMessage", USERMSG_BLOCKHOOKS);
	BfWrite bf	= UserMessageToBfWrite(msg);
	bf.WriteShort(entity);
	EndMessage();
}

void RemoveWorldText(int client, int entity)
{
	Handle	msg = StartMessageOne("RemovePointMessage", client, USERMSG_BLOCKHOOKS);
	BfWrite bf	= UserMessageToBfWrite(msg);
	bf.WriteShort(entity);
	EndMessage();
}

void DrawWorldText(int client, int entity, float pos[3], int r, int g, int b, const char[] format, any...)
{
	SetGlobalTransTarget(client);

	char text[255];
	VFormat(text, sizeof(text), format, 8);

	Handle	msg = StartMessageOne("PointMessage", client, USERMSG_BLOCKHOOKS);
	BfWrite bf	= UserMessageToBfWrite(msg);
	bf.WriteString(text);
	bf.WriteShort(entity);
	bf.WriteShort(0);	 // flags
	bf.WriteVecCoord(pos);
	bf.WriteFloat(-1.0);	// radius
	bf.WriteString("PointMessageDefault");
	bf.WriteByte(r);	// r
	bf.WriteByte(g);	// g
	bf.WriteByte(b);	// b

	EndMessage();
}

void DrawWorldTextAll(int entity, float pos[3], const char[] format, any...)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		SetGlobalTransTarget(i);

		char text[255];
		VFormat(text, sizeof(text), format, 4);

		Handle	msg = StartMessageOne("PointMessage", i, USERMSG_BLOCKHOOKS);
		BfWrite bf	= UserMessageToBfWrite(msg);
		bf.WriteString(text);
		bf.WriteShort(entity);
		bf.WriteShort(0);	 // flags
		bf.WriteVecCoord(pos);
		bf.WriteFloat(-1.0);	// radius
		bf.WriteString("PointMessageDefault");
		bf.WriteByte(255);	  // r
		bf.WriteByte(0);	  // g
		bf.WriteByte(0);	  // b

		EndMessage();
	}
}

Action ReplyBadCommandUsage(int client)
{
	CReplyToCommand(client, "Usage: sm_ult <#userid|name> [seconds] [tp/kill/strip]");
	return Plugin_Handled;
}

Action ReplyNotInsideTrigger(int client, int target)
{
	if (client == target)
	{
		CReplyToCommand(client, "%t", "Not Inside Trigger, Second Person");
	}
	else
	{
		CReplyToCommand(client, "%t", "Not Inside Trigger, Third Person", target);
	}

	return Plugin_Handled;
}

void BeginUltimatum(int trigger, int activator, int seconds, TriggerAction type)
{
	float teleportPos[3];
	GetClientAbsOrigin(activator, teleportPos);

	float	 endTime	= GetGameTime() + (float)(seconds);
	int		 triggerRef = EntIndexToEntRef(trigger);

	DataPack data;
	CreateDataTimer(1.0, Timer_UltimatumThink, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

	data.WriteCell(triggerRef);
	data.WriteFloat(endTime);
	data.WriteCell(type);
	data.WriteFloatArray(teleportPos, sizeof(teleportPos));

	char humanTime[32];
	SecondsToHumanTime(seconds, humanTime, sizeof(humanTime));

	char TriggerActionPhrase[][] = {
		"Teleported, Third Person",
		"Teleported and Stripped, Third Person",
		"Killed, Third Person"
	};

	CPrintToChatAll("%t", "Must be at Marked Location", humanTime, TriggerActionPhrase[type]);

	float textPos[3];
	GetEntityCenter(trigger, textPos);
	DrawWorldTextAll(trigger, textPos, "%t", "Waiting for Players", humanTime);
	HighlightTriggerToAll(trigger, 1.0);

	char ultSound[PLATFORM_MAX_PATH];
	cvSound.GetString(ultSound, sizeof(ultSound));

	if (ultSound[0])
	{
		// EmitSoundToAll doesn't work properly with SOUND_FROM_PLAYER, loop manually
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				EmitSoundToClient(i, ultSound, SOUND_FROM_PLAYER);
			}
		}
	}
}

Action Timer_UltimatumThink(Handle timer, DataPack data)
{
	data.Reset();

	int trigger = EntRefToEntIndex(data.ReadCell());
	if (!IsValidEntity(trigger))
	{
		return Plugin_Stop;
	}

	float		  endTime		= data.ReadFloat();
	TriggerAction type			= data.ReadCell();

	float		  curTime		= GetGameTime();

	float		  remainingTime = endTime - curTime;

	if (remainingTime <= 0.0)
	{
		float teleportPos[3];
		data.ReadFloatArray(teleportPos, sizeof(teleportPos));
		UltimatumFinish(trigger, type, teleportPos);
		return Plugin_Stop;
	}

	// We recompute the center every think in case the trigger moves
	float textPos[3];
	GetEntityCenter(trigger, textPos);

	char humanTime[32];
	SecondsToHumanTime(RoundToFloor(remainingTime), humanTime, sizeof(humanTime));

	DrawWorldTextAll(trigger, textPos, "%t", "Waiting for Players", humanTime);

	if (cvHighlightTrigger.BoolValue)
	{
		HighlightTriggerToAll(trigger, 1.0);
	}

	return Plugin_Continue;
}

void SecondsToHumanTime(int seconds, char[] buffer, int maxlen)
{
	int minutes		  = seconds / 60;
	int remainingSecs = seconds % 60;
	Format(buffer, maxlen, "%02d:%02d", minutes, remainingSecs);
}

void UltimatumFinish(int trigger, TriggerAction action, float teleportPos[3])
{
	int touching[NMR_MAXPLAYERS];
	GetPlayersInTrigger(trigger, touching);

	int absent[NMR_MAXPLAYERS];
	int numAbsent = GetClientsNotInArray(touching, absent);

	for (int i = 0; i < numAbsent; i++)
	{
		int client = absent[i];

		switch (action)
		{
			case TriggerAction_Kill:
			{
				ForcePlayerSuicide(client);
				CPrintToChat(client, "%t", "You Were Acted Upon", "Killed, Second Person");
			}
			case TriggerAction_TeleportStrip:
			{
				DropAllWeapons(client);
				TeleportEntity(client, teleportPos);
				CPrintToChat(client, "%t", "You Were Acted Upon", "Teleported and Stripped, Second Person");
			}
			case TriggerAction_Teleport:
			{
				TeleportEntity(client, teleportPos);
				CPrintToChat(client, "%t", "You Were Acted Upon", "Teleported, Second Person");
			}
		}
	}

	RemoveWorldTextAll(trigger);
}

void DropAllWeapons(int client)
{
	SetVariantString("self.ThrowAllAmmo()");
	AcceptEntityInput(client, "RunScriptCode");

	int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i; i < size; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon == -1 || IsUndroppableWeapon(weapon))
			continue;

		SDKHooks_DropWeapon(client, weapon);
	}
}

bool IsUndroppableWeapon(int weapon)
{
	char classname[80];
	GetEntityClassname(weapon, classname, sizeof(classname));

	// NMRiH
	return StrEqual(classname, "me_fists") || StrEqual(classname, "item_zippo");
}

int FindTrigger(int client)
{
	int trigger = -1;

	int players[NMR_MAXPLAYERS];
	int numPlayers = 0;

	while ((trigger = FindEntityByClassname(trigger, "trigger_allplayer")) != -1)
	{
		numPlayers = GetPlayersInTrigger(trigger, players);

		for (int i = 0; i < numPlayers; i++)
		{
			if (players[i] == client)
			{
				return trigger;
			}
		}
	}

	return -1;
}

int GetClientsNotInArray(int present[NMR_MAXPLAYERS], int absent[NMR_MAXPLAYERS])
{
	int numAbsent = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		bool isInArray = false;
		for (int j = 0; j < sizeof(present); j++)
		{
			if (present[j] == i)
			{
				isInArray = true;
				break;
			}
		}

		if (!isInArray)
		{
			absent[numAbsent++] = i;
		}
	}

	return numAbsent;
}

int GetPlayersInTrigger(int trigger, int players[NMR_MAXPLAYERS])
{
	int		numPlayers			= 0;

	Address m_hTouchingEntities = GetEntityAddress(trigger) + view_as<Address>(offs_m_hTouchingEntities);	 // CUtlVector<CHandle<CBaseEntity>,CUtlMemory<CHandle<CBaseEntity>,int>>

	if (!m_hTouchingEntities)
	{
		LogError("CBaseTrigger::m_hTouchingEntities is null");
		return 0;
	}

	int maxEnts = LoadFromAddress(m_hTouchingEntities + view_as<Address>(0xC), NumberType_Int32);	 // CUtlVector::m_nSize
	if (maxEnts < 0 || maxEnts > GetMaxEntities() * 2)
	{
		LogError("CBaseTrigger::m_hTouchingEntities::m_nSize has bad value (%d)", maxEnts);
		return 0;
	}

	Address elements = LoadFromAddress(m_hTouchingEntities + view_as<Address>(0x10), NumberType_Int32);	   // UtlVector::m_pElements
	if (!elements)
	{
		LogError("CBaseTrigger::m_hTouchingEntities::m_pElements is null");
		return 0;
	}

	// Get all the clients touching this trigger
	for (int i = 0; i < maxEnts; i++)
	{
		int touching = LoadEntityFromHandleAddress(elements + view_as<Address>(i * 0x4));	 // The first thingy being stored
		if (IsEntityPlayer(touching))
		{
			players[numPlayers++] = touching;
		}
	}

	return numPlayers;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (client && StrEqual(sArgs, "quien falta", false))
	{
		ClientCommand(client, "sm_missing");
	}

	return Plugin_Continue;
}

Action Cmd_Missing(int issuer, int args)
{
	int target = GetCommandTarget(issuer, 1);
	if (target == -1)
	{
		return Plugin_Handled;
	}

	int trigger = FindTrigger(target);
	if (trigger == -1)
	{
		return ReplyNotInsideTrigger(issuer, target);
	}

	PrintMissing(issuer, trigger);
	return Plugin_Handled;
}

Action PrintMissing(int issuer, int trigger)
{
	int touching[NMR_MAXPLAYERS];
	GetPlayersInTrigger(trigger, touching);

	if (cvHighlightTrigger.BoolValue)
	{
		HighlightTrigger(issuer, trigger, 1.0);
	}

	int missing[NMR_MAXPLAYERS];
	int numMissing = GetClientsNotInArray(touching, missing);

	AnnounceMissing(issuer, missing, numMissing);
	return Plugin_Handled;
}

void AnnounceMissing(int issuer, int missing[NMR_MAXPLAYERS], int numMissing)
{
	char buffer[255];

	for (int i = 0; i < numMissing; i++)
	{
		int teammate = missing[i];
		if (i == 0)
		{
			Format(buffer, sizeof(buffer), "%N", teammate);
		}
		else {
			Format(buffer, sizeof(buffer), "%N, %N", buffer, teammate);
		}
	}

	CReplyToCommand(issuer, "%t", "Absent Players", numMissing, buffer);
}

int GetOffsetOrFail(GameData gamedata, const char[] key)
{
	int offset = gamedata.GetOffset(key);
	if (offset == -1)
	{
		SetFailState("Failed to find offset \"%s\"", key);
	}
	return offset;
}

void HighlightTriggerToAll(int entity, float duration)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			HighlightTrigger(i, entity, duration);
		}
	}
}

void HighlightTrigger(int client, int entity, float duration)
{
	float mins[3];
	float maxs[3];
	float pos[3];

	GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Data, "m_vecMaxs", maxs);
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	AddVectors(pos, maxs, maxs);
	AddVectors(pos, mins, mins);

	TE_Box(client, mins, maxs, 255, 0, 0, duration);
}

void TE_SendBeam(int client, const float mins[3], const float maxs[3], float duration, int r = 255, int g = 0, int b = 0)
{
	int rgba[4];
	rgba[0] = r;
	rgba[1] = g;
	rgba[2] = b;
	rgba[3] = 100;

	TE_SetupBeamPoints(mins, maxs, g_LaserIndex, g_HaloIndex, 0, 0, duration, 1.0, 1.0, 1, 0.0, rgba, 0);
	TE_SendToClient(client);
}

Action Cmd_PreviewMode(int client, int args)
{
	if (g_PreviewingTriggers[client])
	{
		EndPreviewMode(client);
	}
	else {
		BeginPreviewMode(client);
	}

	return Plugin_Handled;
}

void BeginPreviewMode(int client)
{
	delete g_PreviewingTriggers[client];

	g_PreviewingTriggers[client] = new ArrayList(sizeof(TriggerPreview));

	// Take a snapshot of current trigger_allplayer entities
	// We do this so that triggers getting deleted don't affect our rendering

	int trigger					 = -1;
	while ((trigger = FindEntityByClassname(trigger, "trigger_allplayer")) != -1)
	{
		TriggerPreview backup;

		GetEntPropVector(trigger, Prop_Data, "m_vecMins", backup.mins);
		GetEntPropVector(trigger, Prop_Data, "m_vecMaxs", backup.maxs);
		GetEntPropVector(trigger, Prop_Data, "m_vecAbsOrigin", backup.pos);
		AddVectors(backup.pos, backup.maxs, backup.maxs);
		AddVectors(backup.pos, backup.mins, backup.mins);

		backup.hammerID		 = GetEntityHammerID(trigger);
		backup.possibleIndex = trigger;

		RandomReadableColor(backup.r, backup.g, backup.b);

		g_PreviewingTriggers[client].PushArray(backup);
	}

	CreateTimer(1.0, PreviewModeThink, GetClientSerial(client), TIMER_REPEAT);

	CReplyToCommand(client, "%t", "Enabled Trigger Preview");
}

void EndPreviewMode(int client)
{
	int maxPreviews = g_PreviewingTriggers[client].Length;
	for (int i = 0; i < maxPreviews; i++)
	{
		TriggerPreview preview;
		g_PreviewingTriggers[client].GetArray(i, preview, sizeof(preview));

		RemoveWorldText(client, preview.possibleIndex);
	}

	delete g_PreviewingTriggers[client];

	CReplyToCommand(client, "%t", "Disabled Trigger Preview");
}

Action PreviewModeThink(Handle timer, int clientSerial)
{
	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client))
	{
		delete g_PreviewingTriggers[client];
		return Plugin_Stop;
	}

	if (!g_PreviewingTriggers[client])
	{
		return Plugin_Stop;
	}

	float duration = 1.0;

	float clientPos[3];
	GetClientEyePosition(client, clientPos);

	int maxPreviews = g_PreviewingTriggers[client].Length;
	for (int i = 0; i < maxPreviews; i++)
	{
		TriggerPreview preview;
		g_PreviewingTriggers[client].GetArray(i, preview, sizeof(preview));

		// Only render nearby triggers to save on TEs
		if (GetVectorDistance(clientPos, preview.pos) < 400.0)
		{
			TE_Box(client, preview.mins, preview.maxs, preview.r, preview.g, preview.b, duration);
		}

		// Always draw text regardless of distance
		DrawWorldText(client, preview.possibleIndex, preview.pos, preview.r, preview.g, preview.b,
					  "ID: %d", preview.hammerID);
	}

	return Plugin_Continue;
}

void TE_Box(int client, float mins[3], float maxs[3], int r, int g, int b, float duration)
{
	for (int i = 0; i < 8; i++)
	{
		float vertex[3];

		vertex[0] = (i & 1) ? maxs[0] : mins[0];
		vertex[1] = (i & 2) ? maxs[1] : mins[1];
		vertex[2] = (i & 4) ? maxs[2] : mins[2];

		for (int j = 0; j < 3; j++)
		{
			float adjacent[3];
			adjacent	= vertex;
			adjacent[j] = (vertex[j] == maxs[j]) ? mins[j] : maxs[j];
			TE_SendBeam(client, vertex, adjacent, duration, r, g, b);
		}
	}
}

void RandomReadableColor(int& r, int& g, int& b)
{
	float h = GetRandomFloat(0.0, 360.0);
	float s = 1.0;
	float l = 0.5;
	HSLToRGB(h, s, l, r, g, b);
}

float HueToRGB(float v1, float v2, float vH)
{
	if (vH < 0)
		vH += 1;

	if (vH > 1)
		vH -= 1;

	if ((6 * vH) < 1)
		return (v1 + (v2 - v1) * 6 * vH);

	if ((2 * vH) < 1)
		return v2;

	if ((3 * vH) < 2)
		return (v1 + (v2 - v1) * ((2.0 / 3) - vH) * 6);

	return v1;
}

void HSLToRGB(float h, float s, float l, int& r, int& g, int& b)
{
	if (s == 0)
	{
		r = g = b = RoundToFloor(l * 255);
	}
	else
	{
		float v1, v2;
		float hue = h / 360.0;

		v2		  = (l < 0.5) ? (l * (1 + s)) : ((l + s) - (l * s));
		v1		  = 2 * l - v2;

		r		  = RoundToFloor(255 * HueToRGB(v1, v2, hue + (1.0 / 3)));
		g		  = RoundToFloor(255 * HueToRGB(v1, v2, hue));
		b		  = RoundToFloor(255 * HueToRGB(v1, v2, hue - (1.0 / 3)));
	}
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_PreviewingTriggers[i] && IsClientInGame(i))
		{
			EndPreviewMode(i);
		}
	}
}