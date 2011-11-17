module std.net.uri;

import std.string : indexOf;
import std.conv   : to;

import std.stdio;

class Uri
{
    protected
    {
        string _scheme;
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
    
    void parse(string uri)
    {
        size_t i,j;
        
        // SCHEME
        i = uri.indexOf("://");
        if(i != -1) {
            _scheme = uri[0 .. i];
            uri = uri[i + 3 .. $];
        } else {
            i = uri.indexOf(":");
        }
        
        // USER AND PASS
        i = uri.indexOf("@");
        if(i != -1) {
            j = uri[0..i+1].indexOf(":");
            
            if(j != -1) {
                _user = uri[0..j];
                _password = uri[j+1..i];
            } else {
                _user = uri[0..i];
            }
            
            uri = uri[i+1 .. $]; 
        }
        
        // DOMAIN AND PORT
        i = uri.indexOf("/");
        if(i == -1) i = uri.length;
        
        j = uri.indexOf(":");
        if(j != -1) {
            _domain = uri[0..j];
            _port = to!(ushort)(uri[j+1..i]);
        } else {
            _domain = uri[0..i];
        }
        
        // PATH
        // TODO
        
    }
    
    alias build toString;
    string build()
    {
        return "";
    }
    
    
    
    string scheme()
    {
        return _scheme;
    }
    
    string domain()
    {
        return _domain;
    }
    
    ushort port()
    {
        return _port;
    }
    
    string path()
    {
        return _path;
    }
    
    string query()
    {
        return _query;
    }
    
    string user()
    {
        return _user;
    }
    
    string password()
    {
        return _password;
    }
    
    string fragment()
    {
        return _fragment;
    }
}

debug(Uri)
{
    void main()
    {
        string uri1 = "http://user:pass@domain.com:80/path/a?q=query#fragment";
        auto uri = new Uri(uri1);
        
        writeln(uri.scheme);
        writeln(uri.user);
        writeln(uri.password);
        writeln(uri.domain);
        writeln(uri.port);
    }
}