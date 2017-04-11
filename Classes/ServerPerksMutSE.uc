Class ServerPerksMutSE extends ServerPerksMut
	Config(ServerPerks);
    
var globalconfig int DataPortRangeStart, DataPortRangeEnd;
var transient int LastDataPortUsed;
var globalconfig int BufferSize;
var globalconfig bool bBroadcastFTPDebug, bBroadcastFTPErrors, bBroadcastToAdminsOnly; 

var byte MidSaveCountDown;
var localized string strVersion;


static final function string GetVersionStr()
{
    local String msg, s;
    local int v, sub_v;

    msg = default.strVersion;
    v = default.VersionNumber / 100;
    sub_v = default.VersionNumber % 100;

    s = String(int(v%100));
    if ( len(s) == 1 )
        s = "0" $ s;
    if ( sub_v > 0 )
        s @= "(BETA "$sub_v$")";
    ReplaceText(msg, "%n", s);

    s = String(v/100);
    ReplaceText(msg, "%m",s);

    return msg;
}

function Mutate(string MutateString, PlayerController Sender)
{
    if ( MutateString ~= "VERSION" )
        Sender.ClientMessage(default.FriendlyName @ GetVersionStr());

    super.Mutate(MutateString, Sender);
}


function PostBeginPlay()
{
    if ( DataPortRangeEnd < DataPortRangeStart) {
        warn("DataPortRangeEnd > DataPortRangeStart!");
        DataPortRangeEnd = DataPortRangeStart + 99;        
    }
    LastDataPortUsed = DataPortRangeStart-1;
    BufferSize = clamp(BufferSize, 32, 4096);
    
    super.PostBeginPlay();        
}

function RespawnNetworkLink()
{
	if( Link!=None )
		Link.Destroy();
	if( bUseFTPLink ) {
		Link = Spawn(Class'FTPTcpLinkSE');
		FTPTcpLinkSE(Link).Mut = Self;
    }
    else {
		Link = Spawn(Class'DatabaseUdpLink');
		DatabaseUdpLink(Link).Mut = Self;
	}
	Link.BeginEvent();
}


function SaveStatsSE()
{
	local int i, c;
	local ClientPerkRepLink CP;
    
    for( i=0; i<ActiveStats.Length; ++i ) 
        if( ActiveStats[i].bStatsChanged )
            ++c;

    if ( c == 0 ) {
        Log("*** No stats changed ***",Class.Outer.Name);
        return;
    }
    
	Log("*** Saving "$c$" of "$ActiveStats.Length$" stat objects ***",Class.Outer.Name);
	foreach DynamicActors(Class'ClientPerkRepLink',CP)
		if( CP.StatObject!=None && ServerStStats(CP.StatObject).MyStatsObject!=None )
			ServerStStats(CP.StatObject).MyStatsObject.SetCustomValues(CP.CustomLink);

	if( bUseRemoteDatabase ) {
		SaveAllStats();
	}
    else {
        for( i=0; i<ActiveStats.Length; ++i ) {
            if( ActiveStats[i].bStatsChanged ) {
                ActiveStats[i].bStatsChanged = false;
                ActiveStats[i].SaveConfig();
            }
        }
    }
}

function GetServerDetails( out GameInfo.ServerResponseLine ServerState )
{
	local int i, l;

	Super(Mutator).GetServerDetails( ServerState );
	l = ServerState.ServerInfo.Length;
    ServerState.ServerInfo.insert(l, 4 + LoadPerks.Length);

	ServerState.ServerInfo[l].Key     = "ScrN Veterancy Handler";
	ServerState.ServerInfo[l++].Value = GetVersionStr();
	ServerState.ServerInfo[l].Key     = "Perk level min";
	ServerState.ServerInfo[l++].Value = string(MinPerksLevel);
	ServerState.ServerInfo[l].Key     = "Perk level max";
	ServerState.ServerInfo[l++].Value = string(MaxPerksLevel);
	ServerState.ServerInfo[l].Key     = "Num trader weapons";
	ServerState.ServerInfo[l++].Value = string(LoadInventory.Length);
    
	for( i=0; i<LoadPerks.Length; ++i )
	{
		ServerState.ServerInfo[l].Key = "Veterancy";
		ServerState.ServerInfo[l++].Value = LoadPerks[i].Default.VeterancyName;
	}
}

 


Auto state EndGameTracker
{
Begin:
	if( bUploadAllStats && Level.NetMode==NM_StandAlone )
	{
		Sleep(1.f);
		FTPTcpLinkSE(Link).FullUpload();
		while( true )
		{
			if( KFGT!=None )
				KFGT.WaveCountDown = 60;
			Sleep(1.f);
		}
	}
    Sleep(1.f);
	while( !Level.Game.bGameEnded ) {
		if( Level.bLevelChange ) {
            Log("Level-change stats save",Class.Outer.Name);
			SaveStatsSE();
			Stop;
		}
        else if ( MidSaveCountDown > 0 ) {
            if ( --MidSaveCountDown == 0 ) {
                Log("Mid-game stats save @ wave " $ KFGT.WaveNum,Class.Outer.Name);
                SaveStatsSE();
            }
        }
        else if( MidGameSaveWaves>0 && KFGT!=None && KFGT.WaveNum!=LastSavedWave ) {
			LastSavedWave = KFGT.WaveNum;
            if( ++WaveCounter>=MidGameSaveWaves && KFGT.WaveNum <= KFGT.FinalWave ) {
                WaveCounter = 0;
                MidSaveCountDown = 3; // wait a bit before saving - maybe game is ending atm
            }
		}
		Sleep(1.f);
	}
	CheckWinOrLose();
    Log("End-game stats save",Class.Outer.Name);
	SaveStatsSE();
}


    
    
defaultproperties
{
    VersionNumber=91600
    strVersion="v%m.%n"
    FriendlyName="ScrN Server Veterancy Handler"
    
    DataPortRangeStart=19400
    DataPortRangeEnd=19499
    BufferSize=250
    
    bBroadcastFTPErrors=True
    bBroadcastToAdminsOnly=True
    bEnableWebAdmin=False
}
