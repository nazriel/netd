module std.net.ftp;

import std.net.uri;
import std.socket, std.socketstream, std.conv;
import std.typecons, std.array, std.string;

import std.stdio;


enum FtpResponse : ushort
{
    Ok = 200,
    NotLoggedIn = 530,
    FileOk = 150,
}

class FtpFile
{
    string name;
}

class FtpClient
{
    enum defaultUser = "anonymous";
    enum defaultPort = 21;
    enum bufferSize = 512;
    
    alias Tuple!(ushort, "code", string, "msg") Response;
    alias Tuple!(string, "ip", ushort, "port") dataSocketInfo;
    
    Response response;
    
    Uri _uri;
    Socket _socket;
    
    this(Uri uri)
    {
        if ( uri.user is null )
        {
            uri.user = defaultUser;
        }
        
        if ( uri.port == 0 )
        {
            uri.port = defaultPort;
        }
        
        _uri = uri;
    }
    
    this(string host, ushort port, string username = defaultUser, 
         string password = "", string path = "/")
    {
        _uri = (new Uri(host, port)).user(username).password(password).path(path);
    }
    
    void open()
    {
        _socket = new TcpSocket(new InternetAddress(_uri.host, _uri.port));
        
        readResponse();
        if ( response.code != 220 ) 
        {
            throw new FtpException(this);
        }
        
        if ( _uri.user != "" )
        {
            exec("USER", _uri.user);
            
            if ( response.code != 331 )
            {
                throw new FtpException(this);
            }
        }
        
        if ( _uri.password != "" && _uri.password !is null )
        {
            exec("PASS", _uri.password);
            
            if ( response.code != 230 )
            {
                throw new FtpException(this);
            }
        }
    }
    
    void close()
    {
        scope(exit) 
        {
            _socket.close();
        }
        
        exec("QUIT");
    }
    
    FtpFile[] list(string path = "/")
    {   
        exec("TYPE I");
        auto info = requestDataSocket();
        exec("LIST");
        auto sock = createDataSocket(info);
        
        char[bufferSize] buffer;
        ptrdiff_t len = sock.receive(buffer);
        writeln(buffer[0..len]);
        
        return [new FtpFile, new FtpFile];
    }
    
private:

    void exec(T...)(string cmd, T args)
    {
        foreach ( arg; args )
        {
            cmd ~= " " ~ to!(string)(arg);
        }
        
        cmd ~= "\r\n";
        
        _socket.send(cmd);
        
        debug(Ftp)
            writeln("Request: ", cmd);
        
        readResponse();
        
        debug(Ftp)
            writeln("Reponse: ", response.msg);
    }
    
    void readResponse()
    {
        char[bufferSize] resp;
        ptrdiff_t len = _socket.receive(resp);
        
        if ( len < 5 )
        {
            response.code = 500;
            response.msg = "Syntax error, command unrecognized. "
                           "This may include errors such as command line too long";
        }
        else
        {
            response.code = to!(ushort)(resp[0..3]);
            response.msg = resp[4..len].idup;
        }
    }
    
    dataSocketInfo requestDataSocket()
    {
        exec("PASV");
        if ( response.code != 227 )
        {
            throw new FtpException(this);
        }

        sizediff_t begin = response.msg.indexOf("(");
        sizediff_t end   = response.msg.indexOf(")");
        
        string ipData = response.msg[begin+1 .. end];
        string[6] parts = ipData.split(",");
        
        string ip   = parts[0] ~ "." ~ parts[1] ~ "." ~ parts[2] ~ "." ~ parts[3];
        int port1 = to!(int)(parts[4]) << 8;
        int port2 = to!(int)(parts[5]);
        ushort port = to!ushort(port1 + port2);
        
        debug(Ftp)
        {
            writeln("dataSocket adress: ", ip, " : ", port);
        }
        dataSocketInfo tuple;
        tuple.ip = ip;
        tuple.port = port;
        
        return tuple; 
    }
    
    Socket createDataSocket(dataSocketInfo info)
    {
        Socket dataSock = new TcpSocket( new InternetAddress(info.ip, info.port) );
        
        return dataSock;
    }
}

class FtpException : Exception
{
    ushort code;
    string msg;
    
    this(FtpClient client, string file = __FILE__, size_t line = __LINE__)
    {
        code = client.response.code;
        msg = client.response.msg;
        
        client.close();
        super("\n" ~ file ~ "(" ~ to!(string)(line) ~ ")\t" ~ "\t" ~ 
                        to!(string)(client.response.code) ~ ": " ~ client.response.msg);
    }
}

debug(Ftp)
{
    import std.string: chomp;
    void main()
    {
        writeln("Small FTP client v0.1 ^^");

        auto ftp = new FtpClient("google.com", 21, "***", "***");
        ftp.open();
        ftp.list();
        ftp.close();
    }
}