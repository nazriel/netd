module net.http;

import std.socket, std.socketstream;
import std.string, std.conv;

enum HttpMethod : string
{
    Get = "GET",
    Post = "POST"
}

alias HttpClient Http;
class HttpClient
{
    private
    {
        Socket _sock;
        
        SocketStream _ss;
        
        HttpMethod _method;
        
        string _domain;
        string _url;
        
        uint _port = 80;
    }
    
    this(string url, HttpMethod method = HttpMethod.Get)
    {
        parseUrl(url);
        _method = method;
    }
    
    void parseUrl(string url)
    {
        int offset;
        
        if(url[0..5] == "https")
            _port = 443;
        
        // Remove http:// and https:// 
        offset = indexOf(url, "://");
        if(offset != -1)
            url = url[offset .. $];
        
        // Remove Anchor href
        offset = indexOf(url, "#");
        if(offset != -1)
            url = url[0 .. offset];
        
        // Split domain and url
        offset = indexOf(url, "/");
        if(offset == -1)
        {
            _domain = url;
            _url = "/";
        }
        else
        {
            _domain = url[0 .. offset];
            _url = url[offset .. $];
        }
        
        // Get port
        offset = indexOf(_domain, ":");
        if(offset != -1)
        {
            _port = to!uint(_domain[offset .. $]);
            _domain = _domain[0 .. offset];
        }
    }
}