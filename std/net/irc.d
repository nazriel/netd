module std.net.irc;
/// TODO: FIX Channel data in callbacks etc
import std.socket : TcpSocket, InternetAddress;
import std.socketstream;
import std.stdio;
import std.string : split, indexOf, toUpper;
import std.net.uri;


struct IrcUser
{
    string user;
    string nick;
    string realname;
    
    public this(string _user, string _nick, string _realname)
    {
        user = _user;
        nick = _nick;
        realname = _realname;
    }
}

struct IrcMessage
{
    string channel;
    string message;
    IrcTarget author;
}

struct IrcEvents
{
    void delegate(IrcTarget usr) OnJoin;
    void delegate(IrcTarget usr) OnPart;
    
    //void delegate() OnMeJoin;
    //void delegate() OnMePart;
    
    void delegate() OnConnectionLost;
    void delegate(IrcMessage msg) OnMessageRecv;
    void delegate(string msg) OnMessageSend;
}

struct IrcResponse
{
    string command;
    IrcTarget target;
    string[] params;
}

struct IrcTarget
{
    string host;
    string user;
    string nick;
}

class IrcSession
{
    protected
    {
        TcpSocket _sock;
        SocketStream _reader;
        SocketStream _writer;
        Uri _uri;
        IrcUser _user;
        IrcEvents events;
    }
    public alias events this; 
    
    
    this(Uri uri)
    {
        _uri = uri;
    }
    
    public void connect()
    {
        _sock = new TcpSocket(new InternetAddress(_uri.host, _uri.port));
        _reader = new SocketStream(_sock);
        _writer = new SocketStream(_sock);
    }
    
    public void auth(IrcUser user)
    {
        _user = user;
        send("USER " ~ user.user ~ " 8 * :" ~ user.realname);
        send("NICK " ~ user.nick);
    }
    
    public void join(string channel)
    {
        send("JOIN #" ~channel);
    }
    
    public void part(string channel)
    {
        send("PART #"~channel);
    }
    
    public void me(string channel, string msg)
    {
        sendMessage(channel, "\x01ACTION" ~ msg ~ "\x01");
    }
    
    public void sendMessage(string channel, string msg)
    {
        send("PRIVMSG #"~channel~" :"~msg);
    }
    
    public bool read()
    {
        string line = cast(string)_reader.readLine();
        //writeln("> ", line);
        if(!_sock.isAlive() || !line.length)
        {
            OnConnectionLost();
            return false;
        }
        
        auto res = parseLine(line);
        parseResponse(res);
            
        return true;
    }
    
    public void close()
    {    
        send("QUIT");
        _reader.close();
        _writer.close();
    }
    
    protected void send(string msg)
    {
        writeln("< ",msg);
        
        if(OnMessageSend !is null)
            OnMessageSend(msg);
        
        _writer.writeLine(msg);
    }
    
    /*
     * The Original Code is the Team15 library.
     *
     * The Initial Developer of the Original Code is
     * Stéphan Kochen <stephan@kochen.nl>
     * Portions created by the Initial Developer are Copyright (C) 2006
     * the Initial Developer. All Rights Reserved.
     */
    protected IrcResponse parseLine(string line)
    {
        size_t colon = -1, space = -1;
        string target;
        string[] params;
        string command;
        string usr;
        
        colon = line.indexOf(':');
        
        if(colon == 0)
        {
            space = line.indexOf(' ');
            target = line[1..space];
            line = line[space + 1 .. $];
            colon = line.indexOf(':');
        }
        
        if(colon == -1)
        {
            params = line.split();
        }
        else
        {
            params = line[0..colon].split();
            params.length = params.length + 1;
            params[$-1] = line[colon+1 .. $];
        }
        
        command = toUpper(params[0]);
        params = params[1..$];
        
        switch(command)
        {
            case "001":
                // success
                break;
            
            case "433":
                // nick name in use
                writeln("Nickname in use!");
                break;
            
            case "JOIN":
                if(OnJoin !is null)
                    OnJoin(parseTarget(target));
                break;
                
            case "PART":
                if(OnPart !is null)
                    OnPart(parseTarget(target));
                break;
                
            default:
        }
            
            
        
        auto res = IrcResponse();
        res.target = parseTarget(target);
        res.command = command;
        res.params = params;
        return res;
    }
    
    protected IrcTarget parseTarget(string target)
    {
        IrcTarget res = IrcTarget();
        
        size_t userpos = target.indexOf('!');
        if(userpos == -1)
        {
            res.nick = target;
        }
        else
        {
            res.nick = target[0..userpos];
            
            size_t hostpos = target.indexOf('@');
            if(hostpos == -1)
            {
                res.host = null;
                res.user = null;
            }
            else
            {
                res.user = target[userpos+1..hostpos];
                res.host = target[hostpos+1..$];
            }
        }
        
        return res;
    }
    
    protected void parseResponse(IrcResponse r)
    {
        // Temp
        if(r.command == "433")
            writeln("Nickname in use");
        
        if(r.command == "PING")
            send("PONG :" ~ r.params[0]);
        else if(r.command == "PRIVMSG")
        {
            if(r.params.length != 2)
                return;
                
            string txt = r.params[1];
            
            if(txt.length >= 7 && txt[0..7] == "\x01ACTION" )
            { 
                // CHANGE v
                writeln(r.target.nick ~" * " ~txt[8..$-1]);
                return;
            }
            
            auto msg = IrcMessage();
            msg.author = r.target;
            msg.message = txt;
            
            if(OnMessageRecv !is null)
                OnMessageRecv(msg);
        }    
    }
    
    protected string parseUserName(string target)
    {
        size_t at = target.indexOf('@');
        
        if(at != -1)
        {
            return target[1..at];
        }
        else
            return null;
    }
}

debug(Irc)
{
    void main()
    {
        auto irc = new IrcSession(new Uri("irc.freenode.net:6667"));
        irc.connect();
        scope(exit) irc.close();
        
        irc.auth(IrcUser("Robik__", "Robik__", "real name"));
        irc.join("dragonov");
        
        irc.OnMessageRecv = (IrcMessage msg)
        { 
            if(msg.message == "!bye")
                irc.close();
                
            writefln("<%s> %s", msg.author.nick, msg.message);
        };
        irc.OnConnectionLost = (){ writeln("Connection lost :<"); };
        irc.OnJoin = (IrcTarget usr)
            { writefln("[%s] joined the channel", usr.nick); };
        irc.OnPart = (IrcTarget usr)
            { writefln("[%s] left the channel", usr.nick); };
        
        bool loop = true;
        
        irc.me("dragonov", "works");
        do
        {
            loop = irc.read();
        }while(loop);
    }
}