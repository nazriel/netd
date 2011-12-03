module std.net.irc;

import std.net.uri;
import std.socket, std.socketstream;
import std.typecons;
import std.stdio, std.string, std.random;

struct IrcMsg
{
    struct Author
    {
        string nick;
        string name;
        string host;
    }
    
    Author author;
    string message;
    string channel;
    string full_msg;
}

class Irc
{
    private 
    {
        Uri _uri;
        Socket _sock;
        SocketStream _reader;
        SocketStream _writer;
        
       
    }   
        string nick;
        string user;
        string realname;
        string[] channel;
    
    this (Uri uri)
    {
        _uri = uri;
    }
    
    void open()
    {
        _sock = new TcpSocket(new InternetAddress(_uri.host, _uri.port));
        _reader  = new SocketStream(_sock);
        _writer = new  SocketStream(_sock);
        
        send("USER " ~ user ~ " 8 * :" ~ realname);
        send("NICK " ~ nick);
        
        foreach ( _channel; channel )
        {
            send("JOIN #" ~ _channel);
        }
    }
    
    IrcMsg read()
    {
        char[] msg = _reader.readLine();
        sizediff_t blockBegin = -1;
        sizediff_t blockEnd = -1;
        
        if ( msg.length > 1 )
        {
            if ( msg[0] == ':' )
            {
                blockBegin = 0;
                blockEnd = msg[1..$].indexOf(":");
            }
            else
            {
                blockBegin = -1;
                blockEnd = msg.indexOf(":"); // i.e PING request
            }
        }
        
        
        string channel, message, full_message, nick, host, full_msg;
        
        IrcMsg ircMsg = IrcMsg(IrcMsg.Author(nick, "", host), message, channel, full_msg);
        
        if ( blockBegin != -1 && blockEnd != -1 )
        {
            sizediff_t privMsgPos = msg.indexOf("PRIVMSG");
            
            if ( privMsgPos != -1 )
            {
                if ( privMsgPos + 9 <= msg.length ) {
                    ircMsg.channel = msg[privMsgPos + 9 .. blockEnd].idup;
                }
                ircMsg.message = msg[blockEnd+2..$].idup;
                full_msg = msg.idup;
                
                char[] author = msg[blockBegin .. privMsgPos - 1];
                
                if ( author.indexOf("!") != -1 )
                {
                    ircMsg.author.nick = author[ 1 ..  author.indexOf("!") ].idup;
                    ircMsg.author.name = author[ author.indexOf("!") + 1 .. author.indexOf("@")].idup;
                }
                if ( author.indexOf("@") != -1 )
                {
                    ircMsg.author.host = author[ author.indexOf("@")+1 .. $ ].idup;
                }
            }
        }
        
        if ( msg.length > 5 ) 
        {
            if ( msg[0..4] == "PING" )
            {
                send("PONG");
            }
        }
        
        if ( onMsgReceive !is null )
        {
            onMsgReceive(ircMsg);
        }
        
        return ircMsg;
    }
    void send(const(char)[] command)
    {
        _writer.writeLine(command);
    }
    
    void sendMsg(const(char)[] channel, const(char)[] msg)
    {
        send("PRIVMSG #" ~ channel ~ " :" ~ msg);
    }
    
    void close()
    {
        _reader.close();
        _writer.close();
    }
    
    private Tuple!(string, string, string, string, string)
    parseResponse()
    {
        return tuple("", "" ,"", "", "");
    }
    void delegate(IrcMsg msg) onMsgReceive;
}

debug(Irc)
{
    void main()
    {
        auto irc = new Irc( new Uri("irc.freenode.net", 6667) );
        irc.nick = "nabot";
        irc.realname = "Damian Ziemba";
        irc.user = "nabot 8 * :http://driv.pl";
        irc.channel = ["dragonov"];
        
        irc.onMsgReceive = (IrcMsg msg)
        { 
            if (msg.channel == "dragonov")
            {
                string respMsg;
                
                switch (msg.message)
                {
                    case "?gtkd":
                        respMsg = "Gtk+ bindings for D programming language: http://dsource.org/project/gtkd";
                        break;
                    case "?d":
                        respMsg = "D Programming Language: http://d-programming-language.org";
                        break;
                    case "nabot: hi":
                    case "nabot: yo":
                    case "nabot: hello":
                    case "hello nabot":
                    case "hi nabot":
                    case "yo nabot":
                        respMsg = "Hi, " ~ msg.author.nick ~ " : " ~ msg.author.host;
                        break;
                    default:
                            return;
                    break;
                }
                    
                irc.sendMsg("dragonov", respMsg);
            }
        };
       
            
        irc.open();
        
        IrcMsg msg;
        while (true)
        {
            msg = irc.read();
        }
        
        irc.close();
    }
}










