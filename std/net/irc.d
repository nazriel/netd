/**
 * std.net IRC client
 * 
 * Authors:
 *  
 */
module std.net.irc;
/// TODO: \x03COLORCODE?
import std.socket : TcpSocket, InternetAddress;
import std.socketstream;
import std.stdio;
import std.string : split, indexOf, toUpper;
import std.net.uri;


/**
 * Represents IRC user
 */
struct IrcUser
{
    /**
     * User name
     */
    string user;
    
    /**
     * Nick name
     */
    string nick;
    
    /**
     * Host name
     */
    string host;
    
    /**
     * Creates new user object
     * 
     * Params:
     *  user    =   User name
     *  nick    =   Nick name
     *  host    =   Host name
     */
    public this(string _user, string _nick, string _host = "")
    {
        user = _user;
        nick = _nick;
        host = _host;
    }
    
    
}

/**
 * Represents IRC message
 */
struct IrcMessage
{
    private
    {
        string  _channel;
        string  _message;
        IrcUser _author;
    }
    
    /**
     * Creates new IRC message object
     * 
     * Params:
     *  channel =   Channel name
     *  message =   Message contents
     *  author  =   Message author
     */
    public this(string channel, string message, IrcUser author)
    {
        _channel = channel;
        _message = message;
        _author = author;
    }
    
    /**
     * Returns channel name
     * 
     * Returns:
     *  Channel name
     */
    public @property channel()
    {
        return _channel;
    }
    
    /**
     * Returns message contents
     * 
     * Returns:
     *  Message contents
     */
    public @property message()
    {
        return _message;
    }
    
    /**
     * Returns message author data
     * 
     * Returns:
     *  Author data
     */
    public @property author()
    {
        return _author;
    }
}

/**
 * Represents IRC response
 */
struct IrcResponse
{
    /**
     * IRC server response command
     */
    string command;
    
    /**
     * Event target, user or host
     */
    IrcUser target;
    
    /**
     * Command params, 1st is (not sure if always) channel
     */
    string[] params;
        
    
    /**
     * Creates new Irc response object
     * 
     * Params:
     *  _command    =  Response command
     *  _params =   Command params
     *  _target = Event source
     */
    public this(string _command, string[] _params, IrcUser _target)
    {
        command = _command;
        params  = _params;
        target = _target;
    }
}


/**
 * Represents IRC session
 */
class IrcSession
{
    protected
    {
        TcpSocket _sock;
        SocketStream _ss;
        Uri _uri;
        IrcUser _user;
        string _bind;
    }
    
    void delegate(string channel, IrcUser usr) OnJoin;
    void delegate(string channel, IrcUser usr) OnPart;
    
    void delegate() OnConnectionLost;
    void delegate(IrcMessage msg) OnMessageRecv;
    void delegate(string msg) OnMessageSend;
    
    bool _alive = false;
    /**
     * Creates new IRC session
     */
    this(Uri uri)
    {
        _uri = uri;
        this();
    }
    
    /// ditto
    protected this()
    {
        _sock = new TcpSocket();
    }

    /**
    * Checks if connection is still working
    */
    @property bool alive() const
    {
        return _alive;
    }
    
    /**
     * Connects to the server
     */
    public void connect()
    {
        if ( _bind !is null )
        {
            _sock.bind(new InternetAddress(_bind, InternetAddress.PORT_ANY));
        }

        _sock.connect(new InternetAddress(_uri.host, _uri.port));

        _ss = new SocketStream(_sock);
        _alive = true;
    }

    /**
    * Binds connection
    */
    public void bind(string ip)
    {
        _bind = ip;
    }
    /**
     * Authorizes user
     * 
     * Params:
     *  user    =   User data you want to exist with
     *  realname    =   Real name
     */
    public void auth(IrcUser user, string realname)
    {
        _user = user;
        send("USER " ~ user.user ~ " 8 * :" ~ realname);
        send("NICK " ~ user.nick);
    }
    
    /**
     * Joins room
     * 
     * Params:
     *  channel =   Channel name, including #
     */
    public void join(string channel)
    {
        writeln("Joining ", channel);
        send("JOIN " ~channel);
    }
    
    /**
     * Joins rooms
     * 
     * Params:
     *  ... =   Room names
     */
    public void join(string[] channels...)
    {
        foreach(channel; channels)
            join(channel);
    }
    
    /**
     * Leaves rooms
     * 
     * Params:
     *  channel =   Channel name to leave
     */
    public void part(string channel)
    {
        send("PART "~channel);
    }
    
    /**
     * Tells server client is away
     */
    public void away(string msg)
    {
        send("AWAY :" ~ msg);
    }
    
    /**
     * Tells server client is back
     */ 
    public void away()
    {
        send("AWAY");
    }
    
    /**
     * Sends action command, equivalent to /me
     * 
     * Params:
     *  channel =   Channel to send action
     *  msg =   Action contents
     */
    public void action(string channel, string msg)
    {
        sendMessage(channel, "\x01ACTION " ~ msg ~ "\x01");
    }
    
    /**
     * Sends message to channel
     * 
     * Params:
     *  channel =   Channel name
     *  msg =   Message contents
     */
    public void sendMessage(string channel, string msg)
    {
        send("PRIVMSG "~channel~" :"~msg);
    }
    
    /**
     * Sends message to channel
     * 
     * Params:
     *  msg = Message to send
     */
    public void sendMessage(IrcMessage msg)
    {
        send("PRIVMSG "~msg.channel~" :"~msg.message);
    }
    
    
    /**
     * Lists users on the channel
     * 
     * Todo:
     *  Add callbacks
     * 
     * Params:
     *  channel =   Channel name
     */
    public void listUsers(string channel)
    {
        send("LIST " ~ channel);
    }
    
    /// ditto
    alias listUsers names;
    
    /**
     * Requests server to list channels
     */
    public void listChannels()
    {
        send("LIST");
    }
    
    /**
     * Request server to send Message Of the Day
     */
    public void msod()
    {
        send("MOTD " ~ _uri.host);
    }
    
    /**
     * Invites user to channel
     */
    public void invite(string user, string channel)
    {
        send("INVITE " ~ user ~ " " ~ channel);
    }
    
    /**
     * Changes nick
     * 
     * Params:
     *  nick    =   New nick
     */
    public void nick(string nick)
    {
        send("NICK "~nick);
    }
    
    /**
     * Sends connection password
     * 
     * Params:
     *  pass    =   Password
     */
    public void pass(string pass)
    {
        send("PASS "~pass);
    }
    
    /**
     * Sends notice to target
     * 
     * Params:
     *  target  =   Notice target
     *  msg =   Notice contents
     */
    public void notice(string target, string msg)
    {
        send("NOTICE "~target ~ " :" ~msg);
    }
    
    /**
     * Reads data from IRC
     */
    public bool read()
    {
        string line = cast(string) _ss.readLine();
        //writeln("> ", line);
        if(!_sock.isAlive() || !line.length)
        {
            _alive = false;
            if ( OnConnectionLost !is null )
            	OnConnectionLost();
            	
            return false;
        }
        
        auto res = parseLine(line);
        parseResponse(res);
            
        return true;
    }
    
    /**
     * Closes the connection
     * 
     * Params:
     *  msg =   Quit message
     */
    public void close()
    {    
        quit();      
    }
    
    /// ditto 
    public void quit(string msg = "")
    {
        send("QUIT" ~ (msg != "" ? " :" ~ msg : ""));
        _alive = false;
        _ss.readLine();
        _ss.close();
    }
    
    /**
     * Sends raw command to IRC server
     * 
     * Params:
     *  msg =   Command to send
     */
    public void send(string msg)
    {
        writeln("< ",msg);
        
        if(OnMessageSend !is null)
            OnMessageSend(msg);
        
        _ss.writeLine(msg);
    }
    
    /*
     * The Original Code is the Team15 library.
     *
     * The Initial Developer of the Original Code is
     * Stéphan Kochen <stephan@kochen.nl>
     * Portions created by the Initial Developer are Copyright (C) 2006
     * the Initial Developer. All Rights Reserved.
     */
    /**
     * Parses IRC server response line
     * 
     * Params:
     *  line = Line to parse
     * 
     * Returns:
     *  Parsed response
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
            
        return IrcResponse(command, params, parseTarget(target));
    }
    
    /**
     * Parses target to user data
     * 
     * Params:
     *  target = Target to parse
     * 
     * Returns:
     *  IrcUser
     */
    protected IrcUser parseTarget(string target)
    {
        IrcUser res = IrcUser();
        
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
    
    /**
     * Operate on parsed IRC respones
     * 
     * Params:
     *  r   =   Parsed response
     */
    protected void parseResponse(IrcResponse r)
    {
        switch(r.command)
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
                    OnJoin(r.params[0], r.target);
                break;
                
            case "PART":
                if(OnPart !is null)
                    OnPart(r.params[0], r.target);
                break;
            
            case "PING":
                send("PONG :" ~ r.params[0]);
                break;
            
            case "PRIVMSG":
                if(OnMessageRecv !is null)
                {
                    auto msg = IrcMessage(r.params[0], r.params[1], r.target);
                    OnMessageRecv(msg);
                }
                break;    
                
            default:
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
        
        irc.auth(IrcUser("nubot", "nubot"), "real name");
        irc.join("#dragonov");
        
        irc.OnMessageRecv = (IrcMessage msg)
        { 
            if(msg.message == "!bye")
            {
                irc.quit("Bye!");
                return;
            }
                
            writefln("[%s]<%s> %s", msg.channel, msg.author.nick, msg.message);
        };
        irc.OnConnectionLost = (){ writeln("Connection lost :<"); };
        irc.OnJoin = (string channel, IrcUser usr)
            { writefln("[%s] joined the %s", usr.nick, channel); irc.invite("Robik", "#testroom"); };
        irc.OnPart = (string channel, IrcUser usr)
            { writefln("[%s] left the %s", usr.nick, channel); };
        
        while(irc.alive)
        {
            irc.read();
        }
    }
}
