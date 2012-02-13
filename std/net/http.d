/**
 * 
 * Http Client
 * 
 * Basic HTTP Client functionality.
 * 
 * Authors: $(WEB github.com/robik, Robert 'Robik' Pasiński), $(WEB dzfl.pl, Damian "nazriel" Ziemba)
 * Copyright: 2012, Damian Ziemba, Robert Pasiński
 * License: $(WEB http://www.boost.org/users/license.html, Boost license)
 * 
 * Example:
 * 
 * The hard way:
 * ----
 * import std.stdio;
 * import std.net.http;
 * 
 * Http http = new Http("http://www.google.com/search?hl=en&q=%20D%20Programming%20Language&btnI=I%27m+Feeling+Lucky");
 * 
 * http.connect();
 * writeln(http.get());
 * http.disconnect();
 * ----
 * 
 * 
 * The simple way:
 * ----
 * 
 * import std.stdio;
 * import std.net.http;
 * 
 * writeln( Http.simpleGet("http://google.com");
 * 
 * ----
 * 
 * 
 */
 
/**
 * 
 * TODO: Http over SSL, (Head, Put, Delete etc), Resuming transfers.
 * 
 */
module netd.http;

import std.socket;
import std.stream;
import std.string;
import std.conv;

import netd.uri;
import std.base64;

class HttpException : Exception
{
	public this(string msg)
	{
		super(msg);
	}
}

class HttpHeaders
{
	private string[string] _header;
	public HttpCookies cookies;
	
	void opIndexAssign(T)(T headerValue, string headerName)
	{
		_header[headerName] = to!(string)(headerValue);
	}
	
	string opIndex(string headerName)
	{
		foreach (name, value; _header)
		{
			if (toLower(name) == toLower(headerName))
			{
				return value;
			}
		}
		
		return null;
	}
	
    int opApply (int delegate(ref string, ref string) dg)
    {
        int      result = 0;
		
        foreach (name, value; _header)
        {
            result = dg(name, value);
            
            if (result)
                break;
        }

        return result;
    }
    
    void remove(string headerName)
    {
   		foreach (name, value; _header)
		{
			if (toLower(name) == toLower(headerName))
			{
				_header.remove(name);
			}
		}
    }
}

struct HttpCookies
{
	private string[string] _cookie;
	
	void opIndexAssign(T)(T cookieValue, string cookieName)
	{
		_cookie[cookieName] = to!(string)(cookieValue);
	}
	
	string opIndex(const(char)[] cookieName)
	{
		foreach (name, value; _cookie)
		{
			if (toLower(name) == toLower(cookieName))
			{
				return value;
			}
		}
		
		return null;
	}
	
    int opApply (int delegate(string, string) dg)
    {
        int      result = 0;
		
        foreach (name, value; _cookie)
        {
            result = dg(name, value);
            
            if (result)
                break;
        }

        return result;
    }
}

struct HttpPostData
{
	private string[string] _field;
	
	public this(const(char)[] input)
	{
		auto splitedInput = split(input, "&");
		
		foreach (set; splitedInput)
		{
			auto fieldSet = split(set, "=");
			
			this[fieldSet[0]] = fieldSet[1];
		}
	}
	void opIndexAssign(T)(T fieldValue, const(char)[] fieldName)
	{
		foreach (name, ref value; _field)
		{
			if (toLower(name) == toLower(fieldName))
			{
				value = to!(string)(fieldValue);
				return;
			}
		}
		
		_field[fieldName] = to!(string)(fieldValue);
	}
	
	string opIndex(const(char)[] fieldName)
	{
		foreach (name, value; _field)
		{
			if (toLower(name) == toLower(fieldName))
			{
				return value;
			}
		}
		
		return null;
	}
	
    int opApply (int delegate(ref string, ref string) dg)
    {
        int      result = 0;
		
        foreach (name, value; _field)
        {
            result = dg(name, value);
            
            if (result)
                break;
        }

        return result;
    }
	
	public size_t dataLength()
	{	
		size_t totalLength = 0;
		
		foreach (name, value; _field)
		{
			totalLength += name.length;
			totalLength += 1; // = 
			totalLength += Uri.encode(value).length;
			totalLength += 1; // &
		}
		
		totalLength -= 1;
		
		return totalLength;
	}
}

private struct HttpResponseStatus
{
	ushort code;
	const(char)[] message;
	ushort version_;
}
	
class Http
{
	private enum DefaultUserAgent = "Mozilla/5.0 (X11; Linux x86_64; rv:7.0.1) Gecko/20100101 Firefox/7.0.1";
	private enum RedirectLimit = 10;
	Uri _uri;
	private RequestMethod _requestMethod;
	private uint _redirectsCount = 0;
	private Socket _socket;
	private AddressFamily _family;
	private uint _responseCode;
	private HttpPostData _postData;
	public HttpHeaders requestHeaders;
	public HttpHeaders responseHeaders;
	public HttpResponseStatus responseStatus;
	public bool followLocation = true;
	
	private string _username;
	private string _password;
	
	enum RequestMethod : string
	{
		Get = "GET",
		Post = "POST",
		Head = "HEAD",
	}
	
	this()
	{
		requestHeaders = new HttpHeaders;
		responseHeaders = new HttpHeaders;
		
		if (_uri.user != "")
		{
			_username = _uri.user;
		}
		
		if (_uri.password != "")
		{
			_password = _uri.password;
		}
	}
	
	this(Uri uri, RequestMethod requestMethod = RequestMethod.Get)
	{
		_uri = uri;
		_requestMethod = requestMethod;
		this();
	}
	
	this (string url, RequestMethod requestMethod = RequestMethod.Get)
	{
		_requestMethod = requestMethod;
		_uri = new Uri(url);
		this();
	}
	
	public ~this()
	{
		disconnect();
	}
	
	public void auth(string username, string password)
	{
		_username = username;
		_password = password;
	}
	
	private void ParseResponseHeaders()
	{
		size_t colonPosition;
        char[10240] buffer;
        void[1] Char = void;
        size_t len = 0;
        size_t totalLen = 0;

        while (_socket.isAlive)
        {
            if ( totalLen > 4 )
            {
                if ( buffer[totalLen - 4 .. totalLen] == "\r\n\r\n" )
                {
                    break;
                }
            }
            len = _socket.receive(Char);
            if ( len < 1 ) break;

            buffer[totalLen++] = (cast(char[]) Char)[0];
        }

        foreach (line; splitLines(buffer[0..totalLen]))
		{
            colonPosition = indexOf(line, ": ");
			char[] headerName;
			char[] headerValue;
			
			if (colonPosition != -1)
			{
				headerName = line[0.. colonPosition];
				headerValue = line[colonPosition+2..$];
				
				if (toLower(headerName) == "set-cookie")
				{
					char[][] cookies = splitLines(line[12..$]);
					
					foreach (cookieSet; cookies)
					{
						auto cookieSet2 = split(cookieSet, "; ");
						foreach (cookie_; cookieSet2)
						{
							char[][] cookieNameValueSet = split(cookie_, "=");
							if (cookieNameValueSet.length < 2) continue;
							responseHeaders.cookies[cookieNameValueSet[0].idup] = cookieNameValueSet[1];
							continue;
						}
					}
				}
				
				responseHeaders[headerName.idup] = headerValue;
			}
			else
			{
				if ( line.length > 5 )
                {
                	if ( line[0..4] == _uri.Scheme.Http)
                    {
                    	char[][] responseSplited = split(line, " ");
                        responseStatus = HttpResponseStatus(to!(ushort)(responseSplited[1]), responseSplited[2], to!(ushort)(responseSplited[0][$-1..$]));
                    }
                }
			}
		}
		
	}
	
	public void connect()
	{
		try 
		{
			auto aa = new InternetAddress(_uri.host, _uri.port);
			_socket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
			_socket.connect(aa);
		}
		catch (SocketOSException e)
		{
			throw new HttpException("Unable to connect " ~ _uri.host ~ ": " ~ e.toString());
			
		}
		
		if (requestHeaders["Host"] is null)
		{
			requestHeaders["Host"] =  _uri.host;
		}
		
		if (requestHeaders["User-Agent"] is null)
		{
			requestHeaders["User-Agent"] = DefaultUserAgent;
		}
		
		if (requestHeaders["Accept-Charset"] is null)
		{
			requestHeaders["Accept-Charset"] = "UTF-8, *";
		}
		
		if (_requestMethod == RequestMethod.Post)
		{
			if (requestHeaders["Content-Type"] is null)
			{
				requestHeaders["Content-Type"] =  "application/x-www-form-urlencoded";
			}
			
			if (requestHeaders["Content-Length"] is null)
			{
				requestHeaders["Content-Length"] = _postData.dataLength();
			}
		}
		
		if (_username != "" && _password != "")
		{
			ubyte[] auth = cast(ubyte[])( _username ~ ":" ~ _password);
			requestHeaders["Authorization"] = "Basic " ~ cast(string) Base64.encode(auth);
		}
		
		if (keepAlive)
		{
			requestHeaders["Connection"] = "keep-alive";
		}
		else
		{
			requestHeaders["Connection"] = "close";
		}
		
		string request = _requestMethod ~ " " ~ _uri.path;
		request ~= (_uri.rawquery.length > 0 ? "?" ~ _uri.rawquery : "") ~ " " ~ _uri.scheme() ~ "/1.0\r\n";
		request ~= "Host: " ~ requestHeaders["Host"] ~ "\r\n";
		
		foreach (headerName, headerValue; requestHeaders)
		{
			if (toLower(headerName) != "host")
			{
				request ~= headerName ~ ": " ~ headerValue ~ "\r\n";
			}
		}
		
		request ~= "\r\n";
		
		write(cast(void[]) request);
		
		if (_requestMethod == RequestMethod.Post)
		{
			request = "";
		
			foreach (name, value; _postData)
			{
				request ~= name ~ "=" ~ value ~ "&";
			}
			
			write(cast(void[]) Uri.encode(request[0..$-1]) ~ "\r\n");
		}
		
		ParseResponseHeaders();
		
		if ( (responseStatus.code == 301 || responseStatus.code == 302 || responseStatus.code == 303)
			&& followLocation && responseHeaders["Location"] != "")
		{
			if (++_redirectsCount > RedirectLimit)
			{
				return;
			}
			disconnect();
			reset();
			_uri.parse(responseHeaders["Location"]);
			connect();
		}
	}
	
	public void disconnect()
	{
		if (!connectionAlive)
		{
			return;
		}
		
		_socket.close();
	}
	
	public bool keepAlive() const @property
	{
		return false;
	}
	
	public bool connectionAlive() const @property
	{
		if (_socket is null)
		{
			return false;
		}
		
		if (!_socket.isAlive())
		{
			return false;
		}
		
		return true;
	}
	
	void read(scope void delegate(void[]) sink)
	{
		void[4096] buff = void;
        size_t received;

        while (_socket.isAlive)
        {
            received = _socket.receive(buff);
            if (received < 1) break;
            sink(buff[0..received]);
        }
	}
	
	void write(void[] data)
	{
		size_t totalSend;

        while (_socket.isAlive)
        {
            totalSend = _socket.send(data);
            if (totalSend == data.length)
            {
                break;
            }
        }
	}
	
	public char[] get(char[] buffer = null)
	{
		if (!connectionAlive)
			connect();
		
		if (buffer is null)
		{
			buffer = new char[4096];
		}
		size_t totalLen = 0;
		
		read((void[] data)
			{
				if (buffer.length < totalLen + data.length)
				{
					if (buffer.length * 2 < totalLen + data.length)
					{
						//Console("Resizing 1");
						buffer.length = (totalLen + data.length) * 2;
					}
					else
					{
						//Console("resizing 2", data.length);
						buffer.length = buffer.length * 2;
					}
				}
				buffer[totalLen .. totalLen + data.length] = cast(string) data[0..$];
				totalLen += data.length;
			});
			
		return buffer[0..totalLen];
	}
	
	public char[] post(HttpPostData data, char[] buffer = null)
	{
		_requestMethod = RequestMethod.Post;
		_postData = data;
		
		if (!connectionAlive)
            connect();
		
		if (buffer is null)
		{
			buffer = new char[4096];
		}
		size_t totalLen = 0;
		
		read(
			(void[] data)
			{
				if (buffer.length < totalLen + data.length)
				{
					if (buffer.length * 2 < totalLen + data.length)
					{
						//Console("Resizing 1");
						buffer.length = (totalLen + data.length) * 2;
					}
					else
					{
						//Console("resizing 2", data.length);
						buffer.length = buffer.length * 2;
					}
				}
				buffer[totalLen .. totalLen + data.length] = cast(string) data[0..$];
				totalLen += data.length;
			});
			
		return buffer[0..totalLen];
	}
	
	public void reset()
	{
		_uri.reset();
		responseStatus = HttpResponseStatus();
		requestHeaders.remove("Host");
	}
	
    public size_t download(string localFile)
    {
        if (!connectionAlive)
            connect();

        BufferedFile file = new BufferedFile(localFile, FileMode.OutNew);
        size_t totalLen;

        read( (void[] data)
        {
            totalLen += data.length;
            file.write(cast(ubyte[])data);
        });

        file.close();

        return totalLen;
    }

	public static char[] simpleGet(string url)
	{
		scope Http http = new Http(url);
		return http.get();
	}
	
	public static size_t simpleDownload(string url, string file)
    {
        scope Http http = new Http(url);
        return http.download(file);
    }

	public static char[] simplePost(string url, HttpPostData data)
	{
		scope Http http = new Http(url);
		return http.post(data);
	}
}
