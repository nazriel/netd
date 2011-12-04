module std.net.irc;

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
    string message;
    IrcUser author;
}

struct IrcEvents
{
    void delegate() OnEnter;
    void delegate() OnLeave;
    void delegate() OnKick;
    void delegate() OnConnectionLost;
    void delegate(IrcMessage msg) OnMessageRecv;
}

struct IrcResponse
{
    string command;
    string[] params;
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
    
    public bool read()
    {
        string line = cast(string)_reader.readLine();
        writeln("> ", line);
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
        OnLeave();
        send("QUIT");
        _reader.close();
        _writer.close();
    }
    
    protected void send(string msg)
    {
        writeln("< ",msg);
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
        
        if(command == "001")
            writeln("success");
        else if(command == "433")
            writeln("Nickname in use");
        
        auto res = IrcResponse();
        res.command = command;
        res.params = params;
        return res;
    }
    
    protected void parseResponse(IrcResponse r)
    {
        // Temp
        if(r.command == "433")
            writeln("Nickname in use");
        
        if(r.command == "PING")
            send("PONG " ~ r.params[0]);
        else if(r.command == "PRIVMSG")
        {
            if(r.params.length != 2)
                return;
                
            string txt = r.params[1];
            
            if(txt.length >= 10 && txt[0..10] == "\x01ACTION" )
            { 
                writeln("ACTION");
                return;
            }
            
            auto msg = IrcMessage();
            msg.message = txt;
            msg.author = IrcUser();    
            OnMessageRecv(msg);
        }
            
    }
}

debug(Irc)
{
 
    void main()
    {
        auto irc = new IrcSession(new Uri("irc.freenode.net:6667"));
        irc.connect();
        scope(exit) irc.close();
        
        irc.auth(IrcUser("Robik_t", "Robik_t", "real name"));
        irc.join("robik");
        irc.OnMessageRecv = (IrcMessage msg) { writeln("--- ", msg.message); };
        irc.OnConnectionLost = (){ writeln("Connection lost :("); };
        
        bool loop = true;
        do
        {
            loop = irc.read();
        }while(loop);
    }
}