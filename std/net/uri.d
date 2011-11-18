/**
 * Uri parser
 *
 * Parse URI (Uniform Resource Identifiers) into parts described in RFC, based on tango.net.uri and GIO
 *
 * Authors: $(WEB github.com/robik, Robert 'Robik' Pasiński), $(WEB github.com/nazriel, Damian Ziemba)
 * Copyright: Robert 'Robik' Pasiński, Damian Ziemba 2011
 * License: $(WEB http://www.boost.org/users/license.html, Boost license)
 *
 * Source: $(REPO std/net/uri.d)
 */
module std.net.uri;

import std.string : indexOf;
import std.conv   : to;
import std.array  : split;

import std.stdio;


/** 
 * Represents query parameter
 */
struct QueryParam
{
    /**
     * Creates new QueryParam object
     * 
     * Params:
     *  n   =   Query param name
     *  v   =   Query param value
     */
    this(string n, string v)
    {
        name = n;
        value = v;
    }
    
    /// Query param name
    string name;
    
    /// Query param value
    string value;
}

/**
 * Represents URI query
 */
struct UriQuery
{
    /**
     * Array of params
     */
    QueryParam[255] params;
    size_t count = 0;
    
    /**
     * Returns query param value with specified name
     * 
     * Params:
     *  name    =   Query param name
     * 
     * Throws:
     *  Exception if not exists
     * 
     * Return:
     *  String with contents
     */
    string opIndex(string name)
    {
        foreach(param; params)
        {
            if(param.name == name)
                return param.value;
        }
        
        throw new Exception("Param with name '"~name~"' does not exists");
    }
    
    int length()
    {
        return params.length;
    }
    
    /**
     * Returns QueryParam with specified index
     * 
     * Params:
     *  i   =   Query param index
     * 
     * Returns:
     *  QueryParam
     * 
     * Throws:
     *  Exception if index is out of bounds
     */
    QueryParam opIndex(int i)
    {
        if(i >= params.length)
            throw new Exception("Trying to get index that does not exits");
        
        return params[i];
    }
    
    /**
     * Adds new QueryParam
     * 
     * Params:
     *  param   =   Param to add
     */
    void add(QueryParam param)
    {
        params[count++] = param;
    }
}


/**
 * Represents URI
 * 
 * Examples:
 * ---------
 * auto uri = new Uri("http://domain.com/path"); 
 * assert(uri.domain == "domain.com");
 * assert(uri.path == "/path");
 * ---------
 */
class Uri
{
    /**
     * URI schemes
     */
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
        Scheme   _scheme;
        string   _domain;
        ushort   _port;
        string   _path;
        UriQuery _query;
        string   _rawquery;
        string   _user;
        string   _password;
        string   _fragment;
    }
    
    /**
     * Creates new Uri object
     * 
     * Params:
     *  uri =   Uri to parse
     */
    this(string uri)
    {
        parse(uri);
    }
    
    /**
     * Creates new Uri object
     * 
     * Params:
     *  uri =   Uri to parse
     *  port    =   Port
     */
    this(string uri, ushort port)
    {
        parse(uri, port);
    }
    
    /**
     * Parses Uri
     * 
     * Params:
     *  uri =   Uri to parse
     *  port    = Port
     */
    void parse(string uri, ushort port = 0)
    {
        reset();
        
        size_t i, j;
        _port = port;
        
        /* 
         * Scheme
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
         * Username and Password
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
         * Host and port
         */
        i = uri.indexOf("/");
        if(i == -1) i = uri.length;
        
        j = uri[0..i].indexOf(":");
        if(j != -1)
        {
            _domain = uri[0..j];
            _port = to!(ushort)(uri[j+1..i]);
        } 
        else
        {
            _domain = uri[0..i];
        }
        
        if ( _port != 0 && _scheme == Scheme.Unknown )
            getDefaultScheme();
        
        else if ( _port == 0 && _scheme != Scheme.Unknown )
            getDefaultPort();
            
        uri = uri[i .. $];   
        
        
        /*
         * Fragment
         */
        i = uri.indexOf("#");
        if(i != -1)
        {
            _fragment = uri[i+1..$];
            uri = uri[0..i];
        }
        
        
        /*
         * Path and Query
         */
        i = uri.indexOf("?");
        if(i != -1)
        {
            _rawquery = uri[i+1 .. $];
            _path = uri[0 .. i];
            parseQuery();  
        }
        else
            _path = uri[0..$];
    }
    
    // TODO: Parse to Query
    void parseQuery()
    {
        auto parts = _rawquery.split("&");
        
        foreach(part; parts)
        {
            auto i = part.indexOf("=");
            _query.add( QueryParam( part[0 .. i], part[i+1..$]) );
        }
                
    }
    
    /**
     * Gets default scheme depending on port
     */
    protected void getDefaultScheme()
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
    
    
    /**
     * Gets default port depending on scheme
     */
    protected void getDefaultPort()
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
    
    /**
     * Resets Uri Data
     * 
     * Example:
     * --------
     * uri.parse("http://domain.com");
     * assert(uri.domain == "domain.com");
     * uri.reset;
     * assert(uri.domain == null);
     * --------
     */
    void reset()
    {
        _scheme = Scheme.Unknown;
        _port = 0;
        _domain = null;
        _path = null;
        _rawquery = null;
        _query = UriQuery();
        _user = null;
        _password = null;
        _fragment = null;
    }
    
    /**
     * Builds Uri string
     * 
     * Returns:
     *  Uri
     */
    alias build toString;
    
    /// ditto
    string build()
    {
        string uri;
        
        uri ~= cast(string)_scheme ~ "://";
        
        if(_user)
        {
            uri ~= _user;
            if(_password)
                uri ~= ":"~ _password;
            
            uri ~= "@";   
        }
        
        uri ~= _domain;
        
        if(_port != 0)
            uri ~= ":" ~ to!(string)(_port);
            
        uri ~= _path;
        
        if(_rawquery)
            uri ~= "?" ~ _rawquery;
        
        if(_fragment)
            uri ~= "#" ~ fragment; 
        
        return uri;
    }
    
    
    /**
     * Returns: Uri scheme
     */
    Scheme scheme() const
    {
        return _scheme;
    }
    
    /**
     * Returns: Uri domain
     */    
    string domain()
    {
        return _domain;
    }
    
    /// ditto
    alias domain host;
    
    /**
     * Returns: Uri port
     */
    ushort port() const
    {
        return _port;
    }
    
    /**
     * Returns: Uri path
     */
    string path() const
    {
        return _path;
    }
    
    /**
     * Returns: Uri query (raw)
     */
    string rawquery() const
    {
        return _rawquery;
    }
    
    UriQuery query()
    {
        return _query;
    }
    
    /**
     * Returns: Uri username
     */
    string user() const
    {
        return _user;
    }
    
    /**
     * Returns: Uri password
     */
    string password() const
    {
        return _password;
    }
    
    /**
     * Returns: Uri fragment
     */
    string fragment() const
    {
        return _fragment;
    }
    
    /**
     * Parses Uri and returns new Uri object
     * 
     * Params:
     *  uri =   Uri to parse
     *  port    =  Port
     * 
     * Returns:
     *  Uri
     * 
     * Example:
     * --------
     * auto uri = Uri.parseUri("http://domain.com", 80);
     * --------
     */
    static Uri parseUri(string uri, ushort port)
    {
        return new Uri(uri, port);
    }
    
    /**
     * Parses Uri and returns new Uri object
     * 
     * Params:
     *  uri =   Uri to parse
     * 
     * Returns:
     *  Uri
     * 
     * Example:
     * --------
     * auto uri = Uri.parseUri("http://domain.com");
     * --------
     */
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
        writeln(uri.query["q"]);
        
        writeln("Scheme:   ", uri.scheme);
        writeln("Username: ", uri.user);
        writeln("Password: ", uri.password);
        writeln("Hostname: ", uri.domain);
        writeln("Port:     ", uri.port);
        writeln("Path:     ", uri.path);
        writeln("Query:    ", uri.rawquery);
        writeln("Fragment: ", uri.fragment);
        writeln("ReBuild:  ", uri);
        
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
