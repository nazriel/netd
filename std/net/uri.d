module std.net.uri;

import std.string : indexOf;
import std.conv   : to;

import std.stdio;

class Uri
{
    enum Scheme : string
    {
        Http     = "http",
        Https    = "https",
        Ftp      = "ftp",
        Ftps     = "ftps",
        Irc      = "irc",
        Smtp     = "smtp",        
        Unknown  = "",          
    }
    alias Scheme this;
    
    protected
    {
        Scheme _scheme;
        string _domain;
        ushort _port;
        string _path;
        string _query;
        string _user;
        string _password;
        string _fragment;
    }
    
    this(string uri)
    {
        parse(uri);
    }
    
    this(string uri, ushort port)
    {
        parse(uri, port);
    }
    
    void parse(string uri, ushort port = 0)
    {
        reset();
        
        size_t i, j;
        _port = port;
        
        /* 
        Scheme
        */
        i = uri.indexOf("://");
        if(i != -1)  
        {
            switch( uri[0 .. i] )
            {
                case "http":
                    _scheme = Scheme.Http;
                    break;
                case "https":
                    _scheme = Scheme.Https;
                    break;
                case "ftp":
                    _scheme = Scheme.Ftp;
                    break;
                case "ftps":
                    _scheme = Scheme.Ftps;
                    break;
                case "irc":
                    _scheme = Scheme.Irc;
                    break;
                case "smtp":
                    _scheme = Scheme.Smtp;
                    break;
                default:
                    _scheme = Scheme.Unknown;
                    break;
            }
            
            uri = uri[i + 3 .. $];
        } 
        else
        {
            _scheme = Scheme.Unknown;
            i = uri.indexOf(":");
        }
        
        /* 
        Username and Password
        */ 
        i = uri.indexOf("@");
        if(i != -1) 
        {
            j = uri[0..i+1].indexOf(":");
            
            if(j != -1) {
                _user = uri[0..j];
                _password = uri[j+1..i];
            } else {
                _user = uri[0..i];
            }
            
            uri = uri[i+1 .. $]; 
        }
        
        /* 
        Host and port
        */
        i = uri.indexOf("/");
        if(i == -1) i = uri.length;
        
        j = uri.indexOf(":");
        if(j != -1)
        {
            _domain = uri[0..j];
            _port = to!(ushort)(uri[j+1..i]);
        } 
        else
        {
            _domain = uri[0..i];
        }
        
        // PATH
        // TODO
        if ( _port != 0 && _scheme == Scheme.Unknown )
        {
            switch(_port)
            {
                case 80:
                case 8080:
                    _scheme = Scheme.Http;
                    break;
                case 443:
                    _scheme = Scheme.Https;
                    break;
                case 21:
                    _scheme = Scheme.Ftp;
                    break;
                case 990:
                    _scheme = Scheme.Ftps;
                    break;
                case 6667:
                    _scheme = Scheme.Irc;
                    break;
                case 25:
                    _scheme = Scheme.Smtp;
                    break;
                default:
                    _scheme = Scheme.Unknown;
                    break;
            }
        }
        
        if ( _port == 0 && _scheme != Scheme.Unknown )
        {
            final switch (cast(string) _scheme)
            {
                case Scheme.Http:
                    _port = 80;
                    break;
                case Scheme.Https:
                    _port = 443;
                    break;
                case Scheme.Ftp:
                    _port = 21;
                    break;
                case Scheme.Ftps:
                    _port = 990;
                    break;
                case Scheme.Irc:
                    _port = 6667;
                    break;
                case Scheme.Smtp:
                    _port = 25;
                    break;
            }
        }
    }
    
    void reset()
    {
        _scheme = Scheme.Unknown;
        _port = 0;
        
        _domain, _path, _query, _user, _password, _fragment = null;
    }
    
    alias build toString;
    string build()
    {
        return "";
    }
    
    
    
    Scheme scheme() const
    {
        return _scheme;
    }
    
    string domain()
    {
        return _domain;
    }
    alias domain host;
    
    ushort port() const
    {
        return _port;
    }
    
    string path() const
    {
        return _path;
    }
    
    string query() const
    {
        return _query;
    }
    
    string user() const
    {
        return _user;
    }
    
    string password() const
    {
        return _password;
    }
    
    string fragment() const
    {
        return _fragment;
    }
    
    static Uri parseUri(string uri, ushort port)
    {
        return new Uri(uri, port);
    }
    
    static Uri parseUri(string uri)
    {
        return new Uri(uri);
    }
}

debug(Uri)
{
    void main()
    {
        auto uri = new Uri("http://user:pass@domain.com:80/path/a?q=query#fragment");
        
        assert(uri.scheme() == uri.Http);
        assert(uri.scheme() == uri.Scheme.Http);
        assert(uri.scheme() == Uri.Scheme.Http);
        assert(uri.scheme() == Uri.Http);
        
        writeln("Scheme:   ", uri.scheme);
        writeln("Username: ", uri.user);
        writeln("Password: ", uri.password);
        writeln("Hostname: ", uri.domain);
        writeln("Port:     ", uri.port);
        
        uri.parse("http://google.com");
        
        assert(uri.port() == 80);
        assert(uri.scheme() == uri.Http);
        
        uri.parse("google.com", 80);
        assert(uri.scheme() == uri.Http);
        
        uri.parse("google.com", 8080);
        assert(uri.scheme() == uri.Http);
        
        uri.parse("publicftp.com", 21);
        assert(uri.scheme() == uri.Ftp);
        
        uri.parse("ftp://google.com");
        assert(uri.scheme() == uri.Ftp, uri.scheme);
        
        uri.parse("smtp://gmail.com");
        assert(uri.scheme() == uri.Smtp);
        assert(uri.host() == "gmail.com");
        
        uri.parse("http://google.com:666");
        assert(uri.scheme() == uri.Http);
        assert(uri.port() == 666);
        
        assert(Uri.parseUri("http://google.com").scheme() == Uri.Http);
    }
}
