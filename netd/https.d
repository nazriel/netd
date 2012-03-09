/**
 * 
 * HTTPS Client
 * 
 * HTTP over SSL client
 * 
 * Authors: $(WEB dzfl.pl, Damian "nazriel" Ziemba)
 * Copyright: 2012, Damian Ziemba
 * License: $(WEB http://www.boost.org/users/license.html, Boost license)
 * 
 */
 
module netd.https;

import netd.http;
import netd.uri;
import netd.util.sslsocket;
import std.socket;

class Https : Http
{

    this(Uri uri, RequestMethod requestMethod = RequestMethod.Get)
    {
         super(uri, requestMethod);
    }

    this (string url, RequestMethod requestMethod = RequestMethod.Get)
    {
        super(url, requestMethod);
    }

    override protected Socket CreateSocket(AddressFamily family, SocketType socket, ProtocolType protocol)
    {
        return new SslSocket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
    }

    public static size_t simpleDownload(string url, string file)
    {
        scope Http http = new Https(url);
        return http.download(file);
    }

    public static char[] simpleGet(string url)
    {
        scope Http http = new Https(url);
        return http.get();
    }

    public static char[] simplePost(string url, HttpPostData data)
    {
        scope http = new Https(url);
        return http.post(data);
    }
}

