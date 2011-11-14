module net.http;

import std.socket, std.socketstream;
import std.string, std.conv;

// debug
import std.stdio;

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
        
        ushort _httpVersion = 1;
        
        ushort _port = 80;
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
            url = url[offset + 3 .. $];
        
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
            _port = to!ushort(_domain[offset .. $]);
            _domain = _domain[0 .. offset];
        }
    }
    
    void open()
    {
        _sock = new TcpSocket(new InternetAddress(_domain, _port));
        _ss = new SocketStream(_sock);
    }
    
    void close()
    {
        _ss.close();
    }
    
    // Returns raw headers for now
    /*HttpResponse*/ string[] response()
    {
        _ss.writeString( buildRequest() );
        
        return getHeaders();
    }
    
    string buildRequest()
    {
        string request;
        
        request ~= to!string(_method) ~ " ";
        request ~= _url ~ " " ~ ["HTTP/1.0", "HTTP/1.1"][_httpVersion];
        request ~= "\r\nHost: " ~ _domain ~ "\r\n\r\n";
        return request;
                       
    }
    
    protected string[] getHeaders()
    {
        char[] line;
        string[] headers;
        for(;;)
        {
            line = _ss.readLine();
            
            if(line.length == 0)
                break;
            
            headers ~= line.idup;   
        }
        
        return headers;
    }
    
    HttpMethod method() const
    {
        return _method;
    }
    
    void method(HttpMethod method)
    {
        _method = method;
    }
    
    ushort httpVersion() const
    {
        return _httpVersion;
    }
    
    void httpVersion(ushort ver)
    {
        _httpVersion = ver ? 1 : 0;
    }
}

version(Main)
{
    void main()
    {
        auto http = new Http("http://google.com/");
        http.open;
        
        scope(exit) http.close;
        
        //writeln(http.buildRequest);
        foreach(header; http.response)
            writeln(header);
    }
}