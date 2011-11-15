/**
 * HTTP package 
 */
module net.http;

/*
 * TODO:
 *  - Rebuild? HttpHeaders class
 */

import std.socket 		: Socket, TcpSocket, InternetAddress;
import std.socketstream : SocketStream;
import std.string 		: strip, toLower, indexOf;
import std.conv 		: to;
import std.traits 		: isSomeString;

// debug
import std.stdio;


/**
 * HTTP request method
 */
enum RequestMethod : string
{
    Get 	= "GET",
    Post 	= "POST",
    Put		= "PUT",
    Trace	= "TRACE",
    Head	= "HEAD",
    Options	= "OPTIONS",
    Connect = "CONNECT"
}

/**
 * HTTP headers list
 */
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

enum HttpResponseCode : ushort
{
    Continue                    = 100,
    SwitchingProtocols          = 101,
    
    OK                          = 200,
    Created                     = 201,
    Accepted                    = 202,
    NonAuthoritativeInformation = 203,
    NoContent                   = 204,
    ResetContent                = 205,
    PartialContent              = 206,
    
    MultipleChoies              = 300,
    MovedPermanently            = 301,
    Found                       = 302,
    SeeOther                    = 303,
    NotModified                 = 304,
    UseProxy                    = 305,
    TemponaryRedirect           = 307,
    
    BadRequest                  = 400,
    Unauthorized                = 401,
    PaymentRequired             = 402,
    Forbidden                   = 403,
    NotFound                    = 404,
    MethodNotAllowed            = 405,
    NotAcceptable               = 406,
    ProxyAuthenticationRequired = 407,
    RequestTimeout              = 408,
    Conflict                    = 409,
    Gone                        = 410,
    LengthRequired              = 411,
    PreconditionFailed          = 412,
    RequestEntityTooLarge       = 413,
    RequestURITooLarge          = 414,
    UnsupportedMediaType        = 415,
    RequestedRangeNotSatisfiable= 416,
    ExpectationFailed           = 417,
    
    InternalServerError         = 500,
    NotImplemented              = 501,
    BadGateway                  = 502,
    ServiceUnavaible            = 503,
    GatewayTimeout              = 504,
    VersionNotSupported         = 505
       
}

/**
 * Represents single HTTP header
 */
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
        add(name, to!string(value));
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

/**
 * HTTP client class 
 */
alias HttpClient Http;

/// ditto
class HttpClient
{
    protected
    {		
        Socket _sock;
        SocketStream _ss;        
        RequestMethod _method;
        
        /// Domain to connect to
        string _domain;
        
        /// Request URL
        string _url;
        
        /// Page contents
        string _content;
        
        /// HTTP protocol version
        ushort _httpVersion = 1;
        
        /// Port to connect on
        ushort _port = 80;
        
        /// Server response headers
        Headers _responseHeaders;
        
        /// Server request headers
        Headers _requestHeaders;
    }
    
    /**
     * Creates new HTTPClient object from URL
     * 
     * Params:
     * 	url	=	Web site URL, http(s):// can be omitted
     * 	method	=	Request method
     * 
     * Example:
     * --------
     * auto http = new Http("http://localhost:6666/");
     * --------
     */
    this(string url, RequestMethod method = RequestMethod.Get)
    {
        parseUrl(url);
        _method = method;
        _responseHeaders = new Headers();
        _requestHeaders  = new Headers();        
    }
    
    /**
     * Creates new HTTPClient object from domain, port and url
     * 
     * Params:
     * 	domain	=	Domain to connect to
     * 	port	=	Port to connect on
     * 	url		=	URL to send request to
     * 
     * Example:
     * --------
     * auto http = new Http("google.com", 80);
     * --------
     */
    this(string domain, ushort port, string url = "/", RequestMethod method = RequestMethod.Get)
    {
		_domain = domain;
		_port = port;
		_url = url;
		_method = method;
        _responseHeaders = new Headers();
        _requestHeaders  = new Headers();
	}
    
    /**
     * Slits URL into domain, port and URL
     * 
     * Params:
     * 	url	=	URL to "parse"     
     */
    protected void parseUrl(string url)
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
    
    /**
     * Opens connection to server
     */
    void open()
    {
        _sock = new TcpSocket(new InternetAddress(_domain, _port));
        _ss = new SocketStream(_sock);
    }
    
    /**
     * Closes connection
     */
    void close()
    {
        _ss.close();
    }
    
    /**
     * Sends request to the server
     */
    void send()
    {
        _ss.writeString( buildRequest() );
        getResponse();
    }
    
    /**
     * Creates request
     * 
     * Returns:
     * 	Request
     */
    string buildRequest()
    {
        string request;
  
		/// HTTP method
        request ~= to!string(_method) ~ " ";
        
        /// URL and Protocol version
        request ~= _url ~ " " ~ ["HTTP/1.0", "HTTP/1.1"][_httpVersion];
        
        /// Host
        request ~= "\r\nHost: " ~ _domain ~ "\r\n";
        
        foreach ( currentHeader; requestHeaders() )
        {
            request ~= currentHeader.name ~ ": " ~ currentHeader.value ~ "\r\n";
        }
        
        request ~= "\r\n";

        return request;                       
    }
    
    /**
     * Gets server response: headers and content
     */    
    protected void getResponse()
    {
		/// Headers
        responseHeaders.parseStream(_ss);
        
        /// Content
        char[] line;
        uint l;
        
        if( !_responseHeaders.exist(HttpHeader.ContentLength) )
            return;
        
        int length = to!int(_responseHeaders[HttpHeader.ContentLength].strip);
        while(!_ss.eof())
        {
            line = cast(char[])_ss.readLine();
            l += line.length + 2;
            _content ~= line;
            
            if(l >= length)
                break;
        }
    }
    
    /**
     * Returns: Page content, empty if no content specified
     */
    string content() const
    {
        return _content;
    }    
    
    /**
     * Returns: Request method
     */
    RequestMethod method() const
    {
        return _method;
    }
    
    /**
     * Sets HTTP request method
     * 
     * Params:
     * 	method = Request method
     */
    void method(RequestMethod method)
    {
        _method = method;
    }
    
    /**
     * Returns: HTTP version
     */
    ushort httpVersion() const
    {
        return _httpVersion;
    }
    
    /**
     * Sets HTTP version
     * 
     * Params:
     * 	ver =	HTTP version, 0 - HTTP/1.0, 1 - HTTP/1.1
     */
    void httpVersion(ushort ver)
    {
        _httpVersion = ver ? 1 : 0;
    }
    
    /**
     * Returns: response headers
     */
    Headers responseHeaders()
    {
        return _responseHeaders;
    }

	/**
	 * Returns: request headers
	 */
    Headers requestHeaders()
    {
        return _requestHeaders;
    }
}


debug(Http)
{
    void main()
    {
        auto http = new Http("http://www.google.pl/");
        http.requestHeaders().set(HttpHeader.AcceptCharset, "UTF-8,*");
        
        writeln("\nRequest headers are: ");
        foreach( header; http.requestHeaders() )
        {
            writeln("Name: ", header.name, " -> Value: ", header.value);
        }

        http.open;
        http.send;
        
        scope(exit) http.close();
        
        writeln("\nResponse headers are: ");
        foreach( header; http.responseHeaders() )
        {
            writeln("Name: ", header.name, " -> Value: ", header.value);
        }
        
        writeln("\nPage content:");
        writeln(http.content);
    }
}
