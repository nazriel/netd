/**
 * HTTP package 
 */
module std.net.http;

import std.socket 		: Socket, TcpSocket, InternetAddress;
import std.stream       : Stream, BufferedFile, FileMode;
import std.string 		: strip, toLower, indexOf, splitLines;
import std.conv 		: to, parse;
import std.traits 		: isSomeString;
import std.net.uri;

import std.zlib;

// debug
debug(Http)
{
    import std.stdio;
}
   
/**
 * HTTP request method
 */
enum RequestMethod : string
{
    Get 	= "GET",
    Post 	= "POST",
    Put		= "PUT",
    Delete  = "DELETE",
    Trace	= "TRACE",
    Head	= "HEAD",
    Options	= "OPTIONS",
    Connect = "CONNECT"
}

private enum bufferSize = 4096;

/**
 * Represents single HTTP header
 */
struct Header
{
    string name;
    string value;
}

/**
 * Represents HTTP headers
 */
class Headers
{
    protected 
    {
        /// Response Code
        ushort _code;
        
        /// Headers
        Header[] _headers;
    }
    
    /**
     * Sets header value
     * 
     * Params:
     *  name    =   Header name
     *  value   =   Value to set
     */
    void set(V)(string name, V value)
    {
        add(name, to!(string)(value));
    }

    /**
     * Checks if header exists
     * 
     * Params:
     *  name    =   Header name to check
     * 
     * Returns:
     *  True if header exists, false otherwise
     */
    bool exist(string name)
    {
        foreach ( cur; _headers )
        {
            if ( toLower(cur.name) == toLower(name) )
            {
                return true;
            }
        }

        return false;
    }

    /**
     * Adds new header
     * 
     * Params:
     *  name    =   Header name
     *  value   =   Value to set
     */
    void add(string name, string value)
    {
        foreach (ref cur; _headers )
        {
            if ( toLower(cur.name) == toLower(name) )
            {
                cur.value = value;
                return;
            }
        }

        _headers ~= Header(name, value);
    }
    
    /**
     * Returns header value
     * 
     * Params:
     *  name    =   Header name to get
     * 
     * Returns:
     *  Header value, as string
     */
    string get(string name)
    {
        foreach (_value; _headers)
        {
            if ( toLower(_value.name) == toLower(name) )
            {
                return _value.value;
            }
        }

        // Throw exception?
        
        return null;
    }
    
    /**
     * Returns HTTP response code
     * 
     * Returns:
     *  HTTP response code
     */
    ushort code()
    {
        return _code;
    }
    
    string opIndex(string name)
    {
        return get(name);
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
    
    void parseStream(Socket _ss)
    {
        char[bufferSize] buffer;
        char[1] Char;
        size_t len = 0;
        size_t totalLen = 0;
        
        while (true)
        {
            len = _ss.receive(Char);
            if ( len < 1 ) break;
            
            buffer[totalLen++] = Char[0];
            
            if ( totalLen > 8 )
            {
                if ( buffer[totalLen - 8 .. totalLen - 4] == "\r\n\r\n" )
                {
                    break;
                }
            }
        }
        
        sizediff_t pos;
        
        foreach (line; buffer[0..totalLen].splitLines())
        {
            pos = line.indexOf(": ");
            
            if ( pos != -1 )
            {
                set(line[0..pos].idup, line[pos+2..$].idup);
            }
            else
            {
                if ( line.length > 4 )
                {
                    if ( line[0..4] == "HTTP")
                    {
                        _code = to!(ushort)(line[9..12]);
                    }
                }
            }
        }
    }
}


 
/**
 * HTTP client class 
 * 
 * Example:
 * ---------
 * auto http = new Http("http://google.com");
 * http.get(new BufferedFile("googlecontents.html", FileMode.Out));
 * ---------
 */
class HttpClient
{
    
    protected
    {		
        Socket _sock;  
        RequestMethod _method;
        Uri _uri;
        
        /// HTTP protocol version
        ushort _httpVersion = 1;
        
        /// Server response headers
        Headers _responseHeaders;
        
        /// Server request headers
        Headers _requestHeaders;
    }
    
    
    struct Options
    {
        /**
         * Should follow 'Location' header?
         */
        bool FollowLocation = true;
    }
    Options options;
    alias options this;
    
    /**
     * Creates new HTTPClient object from URL
     * 
     * Params:
     * 	url	=	Web site URL, http(s):// can be omitted
     * 	method	=	Request method
     * 
     * 
     */
    this(ref Uri uri, RequestMethod method = RequestMethod.Get)
    {
        _uri = uri;
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
     * auto http = new Http("http://google.com", 80);
     * --------
     */
    this(string uri, RequestMethod method = RequestMethod.Get)
    {
		this(Uri(uri), method);
	}
    
    /**
     * Opens connection to server
     */
    void open()
    {
        _sock = new TcpSocket(new InternetAddress(_uri.domain, _uri.port));
        _sock.send(buildRequest());
        getResponse();
    }
    
    /**
     * Closes connection
     */
    void close()
    {
        _sock.close();
    }
    
    /**
     * Creates request
     * 
     * Returns:
     * 	Request as string
     */
    string buildRequest()
    {
        string request;
  
		/// HTTP method
        request ~= to!string(_method) ~ " ";
        
        /// URL and Protocol version
        request ~= _uri.path ~ " " ~ ["HTTP/1.0", "HTTP/1.1"][_httpVersion];
        
        /// Host
        request ~= "\r\nHost: " ~ _uri.domain ~ "\r\n";
        
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
        responseHeaders.parseStream(_sock); 
        
        int length = -1;
        
        if( _responseHeaders.exist("Content-Length") )
            length = to!int(_responseHeaders["Content-Length"]);

       
        if ( (_responseHeaders.code == 301 || _responseHeaders.code == 302 || _responseHeaders.code == 303 ) && 
                FollowLocation == true && _responseHeaders.exist("Location") )
        {
            _uri.parse(_responseHeaders["Location"]);
            debug(Http) {
                writeln("Redirecting");
            }
            open();
        }
    }
    
    /**
     * Gets contents and saves in localFile
     * 
     * Params:
     *  localFile   =   Where to save contents
     */
    void get()(string localFile)
    {
        if ( responseHeaders.code() != 200 ) 
        {
            return;
        }
        
        get(new BufferedFile(localFile, FileMode.Out));
    }
    
    /**
     * Gets contetns and saves into stream
     * 
     * Params:
     *  localStream = Stream to write contents
     */
    void get()(Stream localStream)
    {
        if ( responseHeaders.code() != 200 ) 
        {
            return;
        }
        
        ubyte[bufferSize] buffer;
        sizediff_t len;
        
        while (true)
        {
            len = _sock.receive(buffer);
            
            if ( len <= 0 )
            {
                break;
            }
            
            localStream.write(buffer[0..len]);
        }
        
        localStream.close();
    }
    
    /**
     * Returns contents
     * 
     * Returns:
     *  Page contents
     */
    T[] get(T = immutable(char))()
    {
        if ( responseHeaders.code() != 200 ) 
        {
            return null;
        }
        
        T[] buffer;
        
        get(buffer);
        
        return buffer[0..$];
    }
    
    /**
     * Returns contents with operating on specified buffer
     * 
     * Params:
     *  buffer  =   Buffer to work on
     * 
     * Returns:
     *  Contents
     */
    T[] get(T = immutable(char))(T[] buffer)
    {
        if ( responseHeaders.code() != 200 ) 
        {
            return null;
        }
        
        ubyte[bufferSize] _char;
        sizediff_t len;
        
        while (true)
        {
           len = _sock.receive(_char);
           if ( len < 1 ) break;
           
           buffer~= cast(T[]) _char[0..len];
        }
        
        return buffer[0..$];
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
        auto http = new Http("http://google.com/");
        
        http.requestHeaders.set("Accept-Charset", "UTF-8,*");
        //http.requestHeaders.set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:7.0.1) Gecko/20100101 Firefox/7.0.1");
        http.requestHeaders.set("Accept-Language", "en-us,en;q=0.5");
        //http.requestHeaders.set("Accept-Encoding", "gzip");
        http.requestHeaders.set("Connection", "keep-alive");
        
        
        http.open();
        
        
        writeln("\nRequest headers are: ");
        foreach( header; http.requestHeaders() )
        {
            writeln("Name: ", header.name, " -> Value: ", header.value);
        }
       
        
        writeln("\nResponse code: ", http.responseHeaders.code);
        writeln("Response headers are: ");
        foreach( header; http.responseHeaders() )
            writeln("Name: ", header.name, " -> Value: ", header.value);
        
        writeln("Content-Type will be: ", http.responseHeaders["Content-Type"]);
        
        writeln("\nPage content:");
        http.get(new BufferedFile("webpaage.html", FileMode.Out));
        
        http.close();
    }
}
/// Ditto
alias HttpClient Http;
