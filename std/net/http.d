module net.http;

import std.socket, std.socketstream;
import std.string, std.conv, std.traits;

// debug
import std.stdio;

enum HttpMethod : string
{
    Get = "GET",
    Post = "POST"
}

public enum HttpHeader : string
{       
    Accept            = "Accept",
    AcceptCharset     = "Accept-Charset",
    AcceptEncoding    = "Accept-Encoding",
    AcceptLanguage    = "Accept-Language",
    AcceptRanges      = "Accept-Ranges",
    Age               = "Age",
    Allow             = "Allow",
    Authorization     = "Authorization",
    CacheControl      = "Cache-Control",
    Connection        = "Connection",
    ContentEncoding   = "Content-Encoding",
    ContentLanguage   = "Content-Language",
    ContentLength     = "Content-Length",
    ContentLocation   = "Content-Location",
    ContentRange      = "Content-Range",
    ContentType       = "Content-Type",
    Cookie            = "Cookie",
    Date              = "Date",
    ETag              = "ETag",
    Expect            = "Expect",
    Expires           = "Expires",
    From              = "From",
    Host              = "Host",
    Identity          = "Identity",
    IfMatch           = "If-Match",
    IfModifiedSince   = "If-Modified-Since",
    IfNoneMatch       = "If-None-Match",
    IfRange           = "If-Range",
    IfUnmodifiedSince = "If-Unmodified-Since",
    KeepAlive         = "Keep-Alive",
    LastModified      = "Last-Modified",
    Location          = "Location",
    MaxForwards       = "Max-Forwards",
    MimeVersion       = "MIME-Version",
    Pragma            = "Pragma",
    ProxyAuthenticate = "Proxy-Authenticate",
    ProxyConnection   = "Proxy-Connection",
    Range             = "Range",
    Referrer          = "Referer",
    RetryAfter        = "Retry-After",
    Server            = "Server",
    ServletEngine     = "Servlet-Engine",
    SetCookie         = "Set-Cookie", 
    SetCookie2        = "Set-Cookie2",
    TE                = "TE",
    Trailer           = "Trailer",
    TransferEncoding  = "Transfer-Encoding",
    Upgrade           = "Upgrade",
    UserAgent         = "User-Agent",
    Vary              = "Vary",
    Warning           = "Warning",
    WwwAuthenticate   = "WWW-Authenticate",
    Todo              = "TODO",
}


struct Header
{
    HttpHeader name;
    string value;
}

class Headers
{
    this() {}

    void set(K : HttpHeader, V)(K name, V value)
    {
        add(name, to!(string)(value));
    }
    
    void set(K, V)(K name, V value)
    if ( isSomeString!K )
    {
        string key = cast(string) toLower(name);

        foreach (cur; __traits(allMembers, HttpHeader))
        {
            if ( toLower(cur) == key )
            {
                add( cast(HttpHeader) cur, to!(string)(value) );
            }
        }
    }
    
    HttpHeader stringToEnum(string name)
    {
        foreach (cur; __traits(allMembers, HttpHeader))
        {
            if ( toLower(cur) == toLower(name) )
            {
                return cast(HttpHeader) cur;
            }
        }

        /** TODO:
            handle some exotic headers
        */
        return cast(HttpHeader) "TODO";
    }
    bool exist(HttpHeader name)
    {
        foreach ( cur; _headers )
        {
            if ( cur.name == name )
            {
                return true;
            }
        }

        return false;
    }

    void add(HttpHeader name, string value)
    {
        foreach (ref cur; _headers )
        {
            if ( cur.name == name )
            {
                cur.value = value;
                return;
            }
        }

        _headers ~= Header(name, value);
    }
    string get(HttpHeader name)
    {
        foreach (_value; _headers)
        {
            if ( _value.name == name )
            {
                return _value.value;
            }
        }

        return null;
    }

    string opIndex(HttpHeader name)
    {
        return get(name);
    }

    string opIndex(string name)
    {
        return get(stringToEnum(name));
    }

    int opApply (int delegate(ref Header) dg)
    {
        Header   cur;
        int      result = 0;

        foreach (Header header; _headers)
        {
            cur.name = header.name;
            cur.value = header.value;
            result = dg(cur);
            
            if (result)
                break;
        }

        return result;
    }
    
    void parseStream(SocketStream stream)
    {
        sizediff_t pos = -1;

        for(;;)
        {
            char[] line = stream.readLine();
            
            if(line.length == 0)
                break;

            pos = line.indexOf(':');

            if ( pos != -1)
            {
                set(line[0..pos], line[pos..$]);
            }
        }
    }
    private 
    {
        Header[] _headers;
    }
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
        Headers _responseHeaders;
        Headers _requestHeaders;
    }
    
    this(string url, HttpMethod method = HttpMethod.Get)
    {
        parseUrl(url);
        _method = method;
        _responseHeaders = new Headers();
        _requestHeaders  = new Headers();
        
    }
    
    Headers responseHeaders()
    {
        return _responseHeaders;
    }

    Headers requestHeaders()
    {
        return _requestHeaders;
    }

    void parseUrl(string url)
    {
        size_t offset;
        
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
        response();
    }
    
    void close()
    {
        _ss.close();
    }
    
    // Returns raw headers for now
    string[] response()
    {
        _ss.writeString( buildRequest() );
        
        return getHeaders();
    }
    
    string buildRequest()
    {
        string request;
  
        request ~= to!string(_method) ~ " ";
        request ~= _url ~ " " ~ ["HTTP/1.0", "HTTP/1.1"][_httpVersion];
        request ~= "\r\nHost: " ~ _domain ~ "\r\n";
        
        foreach ( currentHeader; requestHeaders() )
        {
            request ~= currentHeader.name ~ ": " ~ currentHeader.value ~ "\r\n";
        }
        
        request ~= "\r\n";

        return request;
                       
    }
    
    protected string[] getHeaders()
    {
        responseHeaders.parseStream(_ss);
        /*
        char[] line;
        string[] headers;
        for(;;)
        {
            line = _ss.readLine();
            
            if(line.length == 0)
                break;
            
            headers ~= line.idup;   
        }
        */
        return [""];
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

debug(Http)
{
    void main()
    {
        auto http = new Http("http://google.com/");
        http.requestHeaders().set(HttpHeader.AcceptCharset, "UTF-8,*");
        
        writeln("\nRequest headers are: ");
        foreach( header; http.requestHeaders() )
        {
            writeln("Name: ", header.name, " -> Value: ", header.value);
        }

        http.open();
        
        scope(exit) http.close();
        
        writeln("\nResponse headers are: ");
        foreach( header; http.responseHeaders() )
        {
            writeln("Name: ", header.name, " -> Value: ", header.value);
        }
    }
}