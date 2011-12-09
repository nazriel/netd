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
import std.array : join;
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
 * Represents IRC channel
 */
struct IrcChannel
{
    /**
     * Channel name
     */
    string name;
    
    /**
     * Channel mode, string contains number not sure if its mode for 100%
     */
    string mode;
    
    /**
     * Channel description
     */
    string desc;
    
    
    /**
     * Creates new IrcChannel object
     *
     * Params:
     *  _name   =   Channel name
     *  _mode   =   Channel mode
     *  _desc   =   Channel description
     */
    public this(string _name, string _mode, string _desc)
    {
        name = _name;
        mode = _mode;
        desc = _desc; 
    }
}

struct IrcUserData
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
     * Server
     */
    string server;
    
    
    /**
     * Creates new user object
     * 
     * Params:
     *  user    =   User name
     *  nick    =   Nick name
     *  host    =   Host name
     *  server  =   Server
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
    
    /**
     * Returns message as string
     */
    public string toString()
    {
        return message;
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
     * Raw response
     */
    string raw;
        
    
    /**
     * Creates new Irc response object
     * 
     * Params:
     *  _command    =  Response command
     *  _params =   Command params
     *  _target = Event source
     *  _raw    = Raw response
     */
    public this(string _command, string[] _params, IrcUser _target, string _raw = "" )
    {
        command = _command;
        params  = _params;
        target = _target;
        raw = _raw;
    }
    
    /**
     * Returns raw response as string
     */
    public string toString()
    {
        return raw;
    }
}


/**
 * Represents IRC session
 *
 * Examples:
 * ----
 * auto irc = new IrcSession(new Uri("irc.freenode.net:6667"));
 * 
 * irc.connect();
 * irc.auth(new IrcUser("urname", "urname"));
 * irc.join("#channel");
 * 
 * irc.OnMessageRecv = (IrcMessage msg) { writefln("[%s]<%s> %s", msg.channel,
 *                                              msg.author.nick, msg.message); };
 * 
 * while(irc.alive)
 * {
 *      irc.read();
 * }
 * ----
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
    
    public ~this()
    {
        if(_alive)
            quit();
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
     *
     * Params:
     *  ip  =   Ip to bind to
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
     *
     * Params:
     *  msg =   Away message
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
     * Requests server to return WHOIS data
     */
    public void whois(string nick)
    {
        send("WHOIS "~nick);
    }
    
    /**
     * Requests server to return WHO data
     */
    public void who(string nick)
    {
        send("WHO " ~nick);
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
        send("NAMES " ~ channel);
    }
    
    /// ditto
    alias listUsers names;
    
    /**
     * Requests server to list channels
     */
    public void listChannels(string[] channels...)
    {
        if(channels.length == 0)
        {
            send("LIST");
        }
        else
        {
            send("LIST " ~ .join(channels, ","));
        }
    }
    
    /**
     * Request server to send Message Of the Day
     */
    public void motd()
    {
        send("MOTD");
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
     * Reads data from IRC and parses response
     */
    public void read()
    {
        auto line = rawRead();
        
        auto res = parseLine(line);
        parseResponse(res);
    }
    
    /**
     * Reads data from Irc
     * 
     * Returns:
     *  IRC response line
     */
    public string rawRead()
    {
        string line = cast(string) _ss.readLine();
        
        if(OnRawRead !is null)
            OnRawRead(line);
        
        if(!_sock.isAlive() || !line.length)
        {
            _alive = false;
            
            if(OnConnectionLost !is null)
                OnConnectionLost();
                
            return null;
        }
        
        return line;
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
        if(OnRawMessageSend !is null)
            OnRawMessageSend(msg);
        
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
            
        return IrcResponse(command, params, parseTarget(target), line);
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
                if(OnNickNameInUse !is null)
                    OnNickNameInUse();
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
                auto msg = IrcMessage(r.params[0], r.params[1], r.target);
                
                if(OnMessageRecv !is null)
                    OnMessageRecv(msg);
                break;    
                
            default:
        }
    }
    
    /**
     * Returns list of users on the channel
     * 
     * Params:
     *  channel =   Channel to list users from
     * 
     * Returns:
     *  Users
     */
    public string[] getUsers(string channel)
    {
        listUsers(channel);
        string[] users;
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "366")
                break;
            else if(res.command == "353")
            {
                auto pos = line[1..$].indexOf(':');
                if(pos == -1)
                    continue;
                else
                {
                    users ~= line[pos+2 .. $].split(" ");
                }
            }
            else if(res.command == "332")
                continue;
            else
                break;
        }
        
        return users;
    }
    
    /**
     * Calls dg on each user listed by the server
     * 
     * Params:
     *  channel =   Channel to look for users
     *  dg  =   Callback to call on each user
     */
    public void getUsers(string channel, void delegate(string usr) dg)
    {
        listUsers(channel);
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "366")
                break;
            else if(res.command == "353")
            {
                auto pos = line[1..$].indexOf(':');
                if(pos == -1)
                    continue;
                else
                {
                    auto usrs = line[pos+2 .. $].split(" ");
                    
                    foreach(u; usrs)
                        dg(u);
                }
            }
            else if(res.command == "332")
                continue;
            else
                break;
        }
    }
    
    /**
     * Returns user data
     *
     * Params:
     *  nick    =   User to get data
     *
     * Returns:
     *  User data
     */
    public IrcUserData getUserData(string nick)
    {
        whois(nick);
        IrcUserData usr;
        usr.nick = nick;
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "318")
                break;
            
            switch(res.command)
            {
                case "330":
                    usr.user = res.params[2];
                    break;
                
                case "312":
                    usr.server = res.params[2];
                    break;
                
                case "311":
                    usr.host = res.params[3];
                    break;    
                
                default:    
            }
        }
        
        return usr;
    }
    
    /**
     * Returns channels available on the server
     *
     * Returns:
     *  Array of IrcChannel representing single channel
     */
    public IrcChannel[] getChannels(string[] _channels...)
    {
        listChannels(_channels);
        IrcChannel[] channels;
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "322")
            {
                if(res.params.length > 3)
                    channels ~= IrcChannel(res.params[1], res.params[2], res.params[3]);
                else
                    channels ~= IrcChannel(res.params[1], res.params[2], "");
            }
            else if( res.command == "323" )
                break;
        }
        
        return channels;
    }
    
    /**
     * Calls dg on each channel returned by server
     * 
     * Params:
     *  dg  =   Callback
     *  _channels   =   Channels to get description
     */
    public void getChannels(void delegate(IrcChannel) dg, string[] _channels...)
    {
        listChannels(_channels);
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "322")
            {
                if(res.params.length > 3)
                    dg(IrcChannel(res.params[1], res.params[2], res.params[3]));
                else
                    dg(IrcChannel(res.params[1], res.params[2], ""));
            }
            else if( res.command == "323" )
                break;
        }
    }
    
    /**
     * Reads Message of the day from server and returns it
     * 
     * Returns:
     *  Message of the day
     */
    public string getMotd()
    {
        motd();
        bool started;
        string motd;
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "375")
                started = true;
            
            else if(res.command == "376")
                break;
                
            else if(res.command == "372")
                motd ~= res.params[1] ~ '\n';
        }
        
        return motd;
    }
    
    /**
     * Calls callback on each message of the day line
     * 
     * Params:
     *  dg  =   Delegate to call on each MOTD line
     */
    public void getMotd(void delegate(IrcResponse res) dg)
    {
        motd();
        bool started;
        
        while(alive)
        {
            auto line = rawRead();
            auto res = parseLine(line);
            
            if(res.command == "375")
                started = true;
            
            else if(res.command == "376")
                break;
                
            else if(res.command == "372")
                dg(res);
        }
    }
    
    /**
     * Gets server time
     * 
     * Returns:
     *  Server time
     */
    public string getServerTime()
    {
        send("TIME");
        
        auto line = rawRead();
        auto res = parseLine(line);
        
        return res.params[2];
    }
    
    /**
     * Called when someone joins the channel, including you
     * 
     * Params:
     *  channel =   Channel where action happened
     *  usr     =   User data
     */
    void delegate(string channel, IrcUser usr) OnJoin;
    
    /**
     * Called when someone leaves the channel, including you
     * 
     * Params:
     *  channel =   Channel where action happened
     *  usr     =   User data
     */
    void delegate(string channel, IrcUser usr) OnPart;
    
    /**
     * Called when called rawRead
     *
     * Params:
     *  msg = Server response contents
     */
    void delegate(string msg) OnRawRead;
    
    /**
     * Called when lost connection to server
     */
    void delegate() OnConnectionLost;
    
    /**
     * Called when someone send message to channel 
     * 
     * Params:
     *  msg =   Message recevied
     */
    void delegate(IrcMessage msg) OnMessageRecv;
    
    /**
     * Called when send any message to server
     * 
     * Params:
     *  msg =   Message send
     */
    void delegate(string msg) OnRawMessageSend;
    
    /**
     * Called when specified nickname is in use
     */
    void delegate() OnNickNameInUse;
}


debug(Irc)
{
    void main()
    {
        auto irc = new IrcSession(new Uri("irc.freenode.net:6667"));
        irc.connect();
        scope(exit) irc.close();
        
        irc.OnNickNameInUse = () { irc.auth(IrcUser("nabot_", "nabot_"), "Real name"); irc.join("#dragonov"); };
        
        irc.auth(IrcUser("nabot", "nabot"), "real name");
        irc.join("#dragonov");
        
        irc.OnMessageRecv = (IrcMessage msg)
        {
            auto parts = split(msg.message, " "); 
            if(msg.message == "!bye")
            {
                irc.quit("Bye!");
                return;
            }
            
            if(msg.message == "!testWhois")
                irc.getUserData("Robik");
            
            if(msg.message == "!testMotd")
                writeln(irc.getMotd());
            
            if(msg.message == "!testMotdg")
                irc.getMotd((IrcResponse res) {writeln(res.params[1]);});
            
            if(msg.message == "!testList")
            {
                auto c = irc.getChannels();
                
                foreach(ch; c)
                    writeln(ch);
            }
            
            if(msg.message == "!repeat")
            {
                irc.sendMessage(msg);
            }
            
            if(msg.message == "!testTime")
            {
                irc.getServerTime();
            }
            
            if(msg.message == "!testChannel")
            {
                auto c = irc.getChannels("#d", "#dbot");
                
                foreach(ch; c)
                    writeln(ch);
            }
                
            writefln("[%s]<%s> %s", msg.channel, msg.author.nick, msg.message);
        };
        
        //irc.OnRawRead = (string msg) { writeln("> ", msg); };
        
        irc.OnConnectionLost = (){ writeln("Connection lost :<"); };
        irc.OnJoin = (string channel, IrcUser usr)
            { writefln("[%s] joined the %s", usr.nick, channel);; };
        irc.OnPart = (string channel, IrcUser usr)
            { writefln("[%s] left the %s", usr.nick, channel); };
        
        while(irc.alive)
        {
            irc.read();
        }
    }
}
