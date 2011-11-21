module std.net.ftp;

import std.net.uri;
import std.socket, std.stream, std.conv;
import std.typecons, std.array, std.string;

import std.stdio : writeln, writef;


enum FtpResponse : ushort
{
    Ok = 200,
    NotLoggedIn = 530,
    FileOk = 150,
}

enum FtpItemType 
{
    File,
    Directory,
    Link,
    Unknown,
}

class FtpFile
{
    string name;
    FtpItemType itemType;
    FtpClient _client;
    bool _append = false;
    bool _resume = false;
    
    this(string name_, FtpClient client)
    {
        name = name_;
        _client = client;
    }
    
    void download(void delegate(Socket) sockPtr)
    {
        _client.exec("TYPE I");
        auto info = _client.requestDataSocket();
        
        _client.exec("RETR", name);
        
        auto sock = _client.createDataSocket(info);
        sockPtr(sock);
    }
    
    void download(string localFile)
    {
        FileMode mode;
        
        if ( itemType == FtpItemType.File )
        {
            if ( _append == false )
            {
                if ( _resume == true )
                {
                    mode = FileMode.Append;
                }
                else
                {
                    mode = FileMode.Out;
                }
            }
            else
            {
                mode = FileMode.Append;
            }
            
            download(new File(localFile, mode));
        }
        else
        {
            // recurse into...
        }
    }
    
    void download(Stream outputFile)
    {
        _client.exec("TYPE I");
        auto info = _client.requestDataSocket();
        
        if ( _resume == true )
        {
            ulong size = outputFile.size();
            
            _client.exec("REST", size);
        }
        _client.exec("RETR", name);
        
        auto sock = _client.createDataSocket(info);
        
        ubyte[_client.bufferSize] buffer;
        ptrdiff_t len;
        
        while (true)
        {
             len = sock.receive(buffer);
             if ( len == 0 ) break;
             outputFile.write(buffer[0..len]);
        }
    }
    
    void upload(string localFile)
    {
        auto file = new File(localFile, FileMode.In);
        upload(file);
    }
    
    void upload(Stream inputFile)
    {
        _client.exec("TYPE I");
        
        auto info = _client.requestDataSocket();
        
        /*if ( _resume == true )
        {
            ulong size = outputFile.size();
            
            _client.exec("REST", size);
        }
        NO RESUME YET
        */
        _client.exec("STOR", name);
        
        auto sock = _client.createDataSocket(info);
        
        ubyte[_client.bufferSize] buffer;
        ptrdiff_t len;
        
        while (true)
        {
             len = inputFile.read(buffer);//sock.receive(buffer);
             double perc = (cast(double) inputFile.position/ cast(double) inputFile.size);
             debug(Ftp)
             {
                writef("\r%d/%d (%d%%)", inputFile.position, inputFile.size, cast(int) (perc * 100) );
                if ( len == 0 )
                {
                  writeln();
                }
             }
             
             if ( len == 0 )
             {
                 break;
             }
             
             sock.send(buffer[0..len]);
        }
        
    }
    @property FtpFile append(bool cond)
    {
        _append = cond;
        
        return this;
    }
    
    @property FtpFile resume(bool cond)
    {
        _resume = cond;
        
        return this;
    }
}

class FtpClient
{
    enum defaultUser = "anonymous";
    enum defaultPass = "anonymous@anonymous";
    enum defaultPort = 21;
    enum bufferSize = 1024 * 4;
    
    alias Tuple!(ushort, "code", string, "msg") Response;
    alias Tuple!(string, "ip", ushort, "port") dataSocketInfo;
    
    bool _passive = true;
    
    Response response;
    
    Uri _uri;
    Socket _socket;
    
    this(Uri uri)
    {
        if ( uri.user is null )
        {
            uri.user = defaultUser;
            uri.password = defaultPass;
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
    
    FtpFile item(string item_)
    {
        return new FtpFile(item_, this);
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
        
        exec("LIST", path);
        //exec("LIST");
        
        auto sock = createDataSocket(info);
        
        char[bufferSize] buffer;
        ptrdiff_t len = sock.receive(buffer);
        //writeln(buffer[0..len]);
        parser(buffer[0..len]);
        
        return [new FtpFile("lol", this), new FtpFile("lol2", this)];
    }
    
    void kek()
    {
        exec("FEAT");
        writeln(response.msg);
    }
    
    @property FtpClient passive(bool cond)
    {
        _passive = cond;
        return this;
    }
    
private:

    void parser(char[] stream)
    {
        FtpFile[] ftpFiles;
        FtpFile curFile;
        
        char[] parse_word(char[] line) 
        {
            size_t start = 0, end = 0, pos = 0;

            // Skip whitespace before.
            while(pos < line.length && line[pos] == ' ')
                pos++;

            start = pos;
            while(pos < line.length && line[pos] != ' ')
                pos++;
            end = pos;

            // Skip whitespace after.
            while(pos < line.length && line[pos] == ' ')
                pos++;

            return line[start .. end];
        }
        
        char[][] files = stream.split("\n");
        
        foreach (file; files)
        {
            if (file.length == 0) continue;
            curFile = new FtpFile("lol", this);
            
            if ( file[0] == 'd' )
            {
                curFile.itemType = FtpItemType.Directory;
            }
            else if ( file[0] == '-' )
            {
                curFile.itemType = FtpItemType.File;
            }
            else if ( file[0] == 'l' )
            {
                curFile.itemType = FtpItemType.Link;
            }
            else
            {
                curFile.itemType = FtpItemType.Unknown;
            }
            
            ftpFiles ~= curFile;
        }
        
        writeln(curFile.itemType);
        //writeln(split);
    }
    
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
        dataSocketInfo tuple;
       
        if ( _passive == true )
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
                writeln("origin: ", ip, " : ", parts[4], " - ", parts[5]);
                writeln("dataSocket adress: ", ip, " : ", port);
            }

            tuple.ip = ip;
            tuple.port = port;
        }
        else
        {
            tuple.ip = "localhost";
            tuple.port = 21;
            exec("PORT", tuple.ip, tuple.port);
        }
        
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

        auto ftp = new FtpClient("*", 21, "*", "*");
        ftp.open();
        
        //ftp.item("benjamin3.mp3").upload("benjamin.mp3");
        //ftp.item("benjamin.mp3").download("benjamin.mp3");
        ftp.item("index.php").download( 
            delegate void(Socket sock)
            { 
                char[4096] buffer;
                ptrdiff_t len;
                
                while (true)
                {
                     len = sock.receive(buffer);
                     if ( len == 0 ) break;
                     writeln(buffer[0..len]);
                }
            });
        ftp.close();
    }
}