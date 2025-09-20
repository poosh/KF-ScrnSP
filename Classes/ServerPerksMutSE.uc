Class ServerPerksMutSE extends ServerPerksMut
    Config(ScrnServerPerks);

// TODO: move to ServerPerksPrivate.ini
var globalconfig int DataPortRangeStart, DataPortRangeEnd;
var transient int LastDataPortUsed;
var globalconfig int BufferSize;
var globalconfig bool bBroadcastFTPDebug, bBroadcastFTPErrors, bBroadcastToAdminsOnly;

var byte MidSaveCountDown;


static function string GetVersionStr(int v, optional bool bClean)
{
    return class'ScrnF'.static.VersionStr(v, bClean);
}

function Mutate(string MutateString, PlayerController Sender)
{
    if ( MutateString ~= "VERSION" ) {
        Sender.ClientMessage(FriendlyName @ GetVersionStr(VersionNumber));
    }

    super(Mutator).Mutate(MutateString, Sender);
}

function PostBeginPlay()
{
    local int i,j;
    local class<SRVeterancyTypes> V;
    local class<Pickup> P;
    local string S;
    local byte Cat;
    local class<PlayerRecordClass> PR;
    local Texture T;
    local KFLevelRules R;

    // hardcoded setting that are incompatible with ScrN Balance
    bForceGivePerk = true;
    // hardcoded to false unless TestMap
    bNoSavingProgress = false;
    bAllowAlwaysPerkChanges = false;

    if ( DataPortRangeEnd < DataPortRangeStart) {
        warn("DataPortRangeEnd > DataPortRangeStart!");
        DataPortRangeEnd = DataPortRangeStart + 99;
    }
    LastDataPortUsed = DataPortRangeStart-1;
    BufferSize = clamp(BufferSize, 32, 4096);


    // C&P to remove ScrN-incompatible stuff
    if( RulesMod==None )
        RulesMod = Spawn(Class'SRGameRules');

    KFGT = KFGameType(Level.Game);
    bEnabledEmoIcons = bEnableChatIcons;

    // Load perks.
    for( i=0; i<Perks.Length; i++ )
    {
        V = class<SRVeterancyTypes>(DynamicLoadObject(Perks[i],Class'Class'));
        if( V!=None )
        {
            LoadPerks[LoadPerks.Length] = V;
            ImplementPackage(V);
        }
    }

    // Setup categories
    LoadedCategories.Length = WeaponCategories.Length;
    for( i=0; i<WeaponCategories.Length; ++i )
    {
        S = WeaponCategories[i];
        j = InStr(S,":");
        if( j==-1 )
        {
            LoadedCategories[i].Name = S;
            LoadedCategories[i].PerkIndex = 255;
        }
        else
        {
            LoadedCategories[i].Name = Mid(S,j+1);
            LoadedCategories[i].PerkIndex = int(Left(S,j));
        }
    }
    if( LoadedCategories.Length==0 )
    {
        LoadedCategories.Length = 1;
        LoadedCategories[0].Name = "All";
        LoadedCategories[0].PerkIndex = 255;
    }

    // Init rules
    foreach AllActors(class'KFLevelRules',R)
        break;
    if( R==None && KFGT!=None )
    {
        R = KFGT.KFLRules;
        if( R==None )
        {
            R = Spawn(class'KFLevelRules');
            KFGT.KFLRules = R;
        }
    }
    if( R!=None )
    {
        // Empty all stock weapons first.
        R.MediItemForSale.Length = 0;
        R.SuppItemForSale.Length = 0;
        R.ShrpItemForSale.Length = 0;
        R.CommItemForSale.Length = 0;
        R.BersItemForSale.Length = 0;
        R.FireItemForSale.Length = 0;
        R.DemoItemForSale.Length = 0;
        R.NeutItemForSale.Length = 0;
    }

    // Load up trader inventory.
    for( i=0; i<TraderInventory.Length; i++ )
    {
        S = TraderInventory[i];
        j = InStr(S,":");
        if( j>0 )
        {
            Cat = Min(int(Left(S,j)),LoadedCategories.Length-1);
            S = Mid(S,j+1);
        }
        else Cat = 0;
        P = class<Pickup>(DynamicLoadObject(S,Class'Class'));
        if( P!=None )
        {
            // Inform bots.
            if( R!=None )
                R.MediItemForSale[R.MediItemForSale.Length] = P;

            LoadInventory[LoadInventory.Length] = P;
            LoadInvCategory[LoadInvCategory.Length] = Cat;
            if( P.Outer.Name!='KFMod' )
                ImplementPackage(P);
        }
    }

    // Load custom chars.
    for (i = 0; i < CustomCharacters.Length; ++i) {
        // Separate group from actual skin.
        S = CustomCharacters[i];
        j = InStr(S, ":");
        if (j >= 0)
            S = Mid(S, j + 1);
        if (InStr(S, ".") == -1)
            S $= "Mod." $ S;
        PR = class<PlayerRecordClass>(DynamicLoadObject(S, class'Class', true));
        if (PR!=None) {
            if (PR.Default.MeshName != "")
                ImplementPackage(DynamicLoadObject(PR.Default.MeshName, class'Mesh', true));
            if (PR.Default.BodySkinName != "")
                ImplementPackage(DynamicLoadObject(PR.Default.BodySkinName, class'Material', true));
            ImplementPackage(PR);
        }
    }

    // Load chat icons
    if( bEnabledEmoIcons )
    {
        j = 0;
        for( i=0; i<SmileyTags.Length; ++i )
        {
            if( SmileyTags[i].IconTexture=="" || SmileyTags[i].IconTag=="" )
                continue;
            T = Texture(DynamicLoadObject(SmileyTags[i].IconTexture,class'Texture',true));
            if( T==None )
                continue;
            ImplementPackage(T);
            SmileyMsgs.Length = j+1;
            SmileyMsgs[j].SmileyTex = T;
            if( SmileyTags[i].bCaseInsensitive )
                SmileyMsgs[j].SmileyTag = Caps(SmileyTags[i].IconTag);
            else SmileyMsgs[j].SmileyTag = SmileyTags[i].IconTag;
            SmileyMsgs[j].bInCAPS = SmileyTags[i].bCaseInsensitive;
            ++j;
        }
        bEnabledEmoIcons = (j!=0);
    }

    Log("Adding"@AddedServerPackages.Length@"additional serverpackages",Class.Outer.Name);
    for( i=0; i<AddedServerPackages.Length; i++ )
        AddToPackageMap(string(AddedServerPackages[i]));
    AddedServerPackages.Length = 0;

    AddToPackageMap("CountryFlagsTex");

    if( bUseRemoteDatabase )
    {
        Log("Using remote database:"@RemoteDatabaseURL$":"$RemotePort,Class.Outer.Name);
        RespawnNetworkLink();
    }
}

static function FillPlayInfo(PlayInfo PlayInfo)
{
    super(Mutator).FillPlayInfo(PlayInfo);

    PlayInfo.AddSetting(default.ServerPerksGroup,"MinPerksLevel","Min Perk Level",1,0, "Text", "4;-1:70");
    PlayInfo.AddSetting(default.ServerPerksGroup,"MaxPerksLevel","Max Perk Level",1,0, "Text", "4;0:70");
    PlayInfo.AddSetting(default.ServerPerksGroup,"RequirementScaling","Req Scaling",1,0, "Text", "6;0.01:4.00");
    // PlayInfo.AddSetting(default.ServerPerksGroup,"bForceGivePerk","Force perks",1,0, "Check");
    // PlayInfo.AddSetting(default.ServerPerksGroup,"bNoSavingProgress","No saving",1,0, "Check");
    // PlayInfo.AddSetting(default.ServerPerksGroup,"bAllowAlwaysPerkChanges","Unlimited perk changes",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bNoPerkChanges","No perk changes",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bUseRemoteDatabase","Use remote database",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bUseFTPLink","Use FTP remote database",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"RemoteDatabaseURL","Remote database URL",1,1,"Text","64");
    PlayInfo.AddSetting(default.ServerPerksGroup,"RemotePort","Remote database port",1,0, "Text", "5;0:65535");
    PlayInfo.AddSetting(default.ServerPerksGroup,"RemotePassword","Remote database password",1,0, "Text", "64");
    PlayInfo.AddSetting(default.ServerPerksGroup,"RemoteFTPUser","Remote database user",1,0, "Text", "64");
    PlayInfo.AddSetting(default.ServerPerksGroup,"RemoteFTPDir","Remote database dir",1,0, "Text", "64");
    PlayInfo.AddSetting(default.ServerPerksGroup,"FTPKeepAliveSec","FTP Keep alive sec",1,0, "Text", "6;0:600");
    PlayInfo.AddSetting(default.ServerPerksGroup,"MidGameSaveWaves","MidGame Save Waves",1,0, "Text", "5;0:10");
    PlayInfo.AddSetting(default.ServerPerksGroup,"ServerNewsURL","Newspage URL",1,0, "Text", "64");

    PlayInfo.AddSetting(default.ServerPerksGroup,"bUsePlayerNameAsID","Use PlayerName as ID",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bMessageAnyPlayerLevelUp","Notify any levelup",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bUseLowestRequirements","Use lowest req",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bBWZEDTime","BW ZED-time",1,0, "Check");
    // PlayInfo.AddSetting(default.ServerPerksGroup,"bUseEnhancedScoreboard","Enhanced scoreboard",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bForceCustomChars","Force Custom Chars",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bEnableChatIcons","Enable chat icons",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bEnhancedShoulderView","Shoulder view",1,0, "Check");
    // PlayInfo.AddSetting(default.ServerPerksGroup,"bFixGrenadeExploit","No Grenade Exploit",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bAdminEditStats","Admin edit stats",1,0, "Check");
    PlayInfo.AddSetting(default.ServerPerksGroup,"bEnableWebAdmin","SP WebAdmin",1,0, "Check");
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
    ServerState.ServerInfo.insert(l, 5 + LoadPerks.Length);

    ServerState.ServerInfo[l].Key     = "ScrN Veterancy Handler";
    ServerState.ServerInfo[l++].Value = GetVersionStr(VersionNumber);
    ServerState.ServerInfo[l].Key     = "Perk level min";
    ServerState.ServerInfo[l++].Value = string(MinPerksLevel);
    ServerState.ServerInfo[l].Key     = "Perk level max";
    ServerState.ServerInfo[l++].Value = string(MaxPerksLevel);
    ServerState.ServerInfo[l].Key     = "Num trader weapons";
    ServerState.ServerInfo[l++].Value = string(LoadInventory.Length);
    ServerState.ServerInfo[l].Key     = "Num perks";
    ServerState.ServerInfo[l++].Value = string(LoadPerks.Length);

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


state TestMap
{
    ignores SaveStats, SaveStatsSE, CheckWinOrLose, InitNextWave;

    function BeginState()
    {
        Log("TestMap: Perk progress DISABLED", class.outer.name);
        bAllowAlwaysPerkChanges = true;
        bNoSavingProgress = true;
    }
}


defaultproperties
{
    VersionNumber=97220
    FriendlyName="ScrN Server Veterancy Handler"

    DataPortRangeStart=19400
    DataPortRangeEnd=19499
    BufferSize=250

    bBroadcastFTPErrors=True
    bBroadcastToAdminsOnly=True
    bEnableWebAdmin=False
}
