Class FTPDataConnectionSE extends TcpLink;

var string Data;
var int BufferSize;

function PostBeginPlay()
{
    LinkMode = MODE_Text;
}

defaultproperties
{
    BufferSize=250
}