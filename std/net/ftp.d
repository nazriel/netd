module std.net.ftp;

import std.net.uri;
import std.socket, std.stream, std.conv;
import std.typecons, std.array, std.string;
import core.thread;

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

class FtpClient
{
    enum defaultUser = "anonymous";
    enum defaultPass = "anonymous@anonymous";
    enum defaultPort = 21;
    enum bufferSize = 1024 * 4;
    
    alias Tuple!(ushort, "code", string, "msg") Response;
    alias Tuple!(string, "ip", ushort, "port") dataSocketInfo;
    
    bool _passive = true;
    bool _connected = false;
    
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
    
    ~this()
    {
        //close();
        // need to implement somekind of lock in order to wait for
        // Async downloads to finish their work
    }
    
    void open()
    {
        if ( _connected == true ) return;
        
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
        
        _connected = true;
    }
    
    void close(ulong line = __LINE__)
    {
        writeln("Calling QUIT from line: ", line);
        if ( _connected == false ) return;
        
        scope(exit) 
        {
            _socket.close();
        }
        
        exec("QUIT");
        
        _connected = false;
    }
    
    void list(string path = "/")
    {   
        exec("TYPE I");
        auto info = requestDataSocket();
        
        exec("NLST", path);
        
        auto sock = createDataSocket(info);
        
        char[bufferSize] buffer;
        ptrdiff_t len = sock.receive(buffer);
        writeln(buffer[0..len]);
        
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
    
    void createDir(string name)
    {
        exec("MKD", name);
        
        if ( response.code != 257 )
        {
            throw new FtpException(this);
        }
    }
    
    void deleteDir(string name)
    {
        exec("RMD", name);
        
        if ( response.code != 250 )
        {
            throw new FtpException(this);
        }
    }
    
    void rename(string oldName, string newName)
    {
        exec("RNFR", oldName);
        if ( response.code != 350 )
        {
            throw new FtpException(this);
        }
        
        exec("RNTO", newName);
        if ( response.code != 250 )
        {
            throw new FtpException(this);
        }
    }
    
    void deleteFile(string filename)
    {
        exec("DELE", filename);
        
        if ( response.code != 250 )
        {
            throw new FtpException(this);
        }
    }
    
    string currentDir()
    {
        exec("PWD");
        
        if ( response.code != 257 )
        {
            throw new FtpException(this);
        }
        
        string resp = response.msg.idup;
        sizediff_t startPos = resp.indexOf(`"`);
        sizediff_t endPos = resp.lastIndexOf(`"`);
        
        if ( startPos == -1 || startPos == endPos || endPos == -1 )
        {
            return "";
        }
        
        return resp[startPos + 1..endPos];
    }
    
    void changeWorkingDir(string path)
    {
        exec("CWD", path);
        if ( response.code != 550 )
        {
            throw new FtpException(this);
        } 
    }
    
    void stat(string name)
    {
        exec("TYPE I");
        exec("STAT", name);
        writeln(response.code, " : ", response.msg);
    }
/**
string s = download(string "fileOnFtp.zip");
ubyte[] s = download!(ubyte)("fileOnFtp.zip");
void download(string "fileOnFtp.zip", string "localFile.zip");
void download("fileOnFtp.zip", Stream new File("localFile.zip"));
void download("fileOnFtp.zip", ubyte[] buffer);

string s = downloadAsync(string "fileOnFtp.zip");
void downloadAsync(string "fileOnFtp.zip", string "localFile.zip");
void downloadAsync("fileOnFtp.zip", Stream new File("localFile.zip"));
void downloadAsync("fileOnFtp.zip", ubyte[] buffer);

foreach ( chunk; struct FtpChunk downloadByChunk(4096)(string "fileOnFtp") )
{
}

upload(string sourceFile, string destFile);
upload(Stream sourceFile, string destFile);
upload(T[]  sourceBuffer, string destFile);
    
uploadAsync(string sourceFile, string destFile);
uploadAsync(Stream sourceFile, string destFile);
uploadAsync(T[]  sourceBuffer, string destFile);
    
uploadByChunk(string sourceFile, string destFile); // ? not sure about it
uploadByChunk(Stream sourceFile, string destFile); // ? not sure about it
uploadByChunk(T[]  sourceBuffer, string destFile); // ? not sure about it
 */   
    void download()(string remoteFile, string localFile)
    {
        download(remoteFile, new BufferedFile(localFile, FileMode.Out, bufferSize));
    }
    
    void download()(string remoteFile, Stream localFile)
    {
        exec("TYPE I");
        auto info = requestDataSocket();
        
        if ( _resume == true )
        {
            ulong size = localFile.size();
            localFile.position(size);
            exec("REST", size);
        }
        exec("RETR", remoteFile);
        
        auto sock = createDataSocket(info);
        
        ubyte[bufferSize] buffer;
        ptrdiff_t len = 0;
        
        while (true)
        {
             len = sock.receive(buffer);
             
             if ( len < 1 )
             {
                break;
             }
               
             localFile.write(buffer[0..len]);
        }
        
        localFile.close();
    }
    
    T[] download(T = immutable(char))(string remoteFile)
    {
        T[] buffer;
        
        download!(T)(remoteFile, buffer);
        
        return buffer;
    }
    
    void download(T = ubyte)(string remoteFile, ref T[] buffer)
    {
        exec("TYPE I");
        auto info = requestDataSocket();
        
        if ( _resume == true )
        {
            /*ulong size = localFile.size();
            localFile.position(size);
            exec("REST", size);*/
        }
        exec("RETR", remoteFile);
        
        auto sock = createDataSocket(info);
        
        ubyte[bufferSize] tmpBuffer;
        ptrdiff_t len = 0;
        ptrdiff_t totalLen = 0;
        
        while (true)
        {
             len = sock.receive(tmpBuffer);
             totalLen += len;
             
             if ( len < 1 )
             {
                break;
             }
               
             buffer ~= cast(T[]) tmpBuffer[0..len];
             
        }
        
        buffer = buffer[0..totalLen];
    }
    
    void downloadAsync(string remoteFile, string localFile)
    {
        downloadAsync(remoteFile, new BufferedFile(localFile, FileMode.Out, bufferSize));
    }
    
    void downloadAsync(string remoteFile, Stream localFile)
    {
        if ( _asyncDownloadInProgress == true )
        {
            //throw new Exception("Already blabla");
            //maybe spawn new class?
            _uri.path = currentDir();
            auto newTmp = new FtpClient(_uri);
            newTmp.open();
            newTmp.downloadAsync(remoteFile, localFile);
            
            return;
        }
        
        DownloadAsyncImpl impl = new DownloadAsyncImpl(this, remoteFile, localFile);
        impl.start();
        _asyncDownloadInProgress = true;
    }
    
    FtpChunk downloadByChunk(size_t chunkSize)(string remoteFile)
    {
        return FtpChunk(this, chunkSize, remoteFile);
    }
    
    struct FtpChunk
    {
        size_t chunkSize;
        string remoteFile;
        Socket sock;
        FtpClient client;
        
        this(FtpClient client, size_t chunkSize, string remoteFile)
        {
            this.client = client;
            this.chunkSize = chunkSize;
            this.remoteFile = remoteFile;
            
            client.exec("TYPE I");
            auto info = client.requestDataSocket();
            client.exec("RETR", remoteFile);
            
            sock = client.createDataSocket(info);
        }
        
        int opApply (int delegate(ref ubyte[]) dg)
        {
            ubyte[]   buffer = new ubyte[chunkSize];
            int         result = 0;
    
            sock.receive(buffer);
            
            result = dg(buffer);
                
            return result;
        }
    }
    
    private class DownloadAsyncImpl : Thread
    {
        FtpClient parent;
        Stream localFile;
        string remoteFile;
        
        this (FtpClient parent, string remoteFile, Stream localFile)
        {
            this.parent = parent;
            this.remoteFile = remoteFile;
            this.localFile = localFile;
            
            super(&run);
        }
        
        void run()
        {
            scope(exit)
            {
                parent._asyncDownloadInProgress = false;
            }
            
            parent.download(remoteFile, localFile);
        }
    }
    
    bool _resume;
    bool _append;
private:

    /*
    * Meh, I really need to start work on it...
    * list() and info() requires this method
    *
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
    */
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
            try
            {
                response.code = to!(ushort)(resp[0..3]);
            }
            catch ( Exception e )
            {
                response.code = 500;
            }
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
    
    private shared(bool) _asyncDownloadInProgress = false;
}

class FtpException : Exception
{
    ushort code;
    string msg;
    
    this(FtpClient client, string file = __FILE__, size_t line = __LINE__)
    {
        code = client.response.code;
        msg = client.response.msg;
        
        //client.close();
        super("\n" ~ file ~ "(" ~ to!(string)(line) ~ ")\t" ~ "\t" ~ 
                        to!(string)(client.response.code) ~ ": " ~ client.response.msg);
    }
}

debug(Ftp)
{
    import std.string: chomp;
    void main()
    {
        auto ftp = new FtpClient("***", 21, "***", "***");
        ftp.open();
        ftp.createDir("filmy");
        ftp.rename("filmy", "dupeczki");
        
        ftp.downloadAsync("benjamin.mp3", "benjamin.mp3");
        ftp.downloadAsync("benjamin.mp3", "benjamin_copy.mp3");
        ftp.downloadAsync("benjamin.mp3", "benjamin_copy2.mp3");
        
        writeln("Downloads above doesn't block main thread so I can display this"
                "message *Grins*");
        
        auto ftp2 = new FtpClient("***", 21, "***", "***");
        ftp2.open();
        
        /*
        * download to custom buffer 
        */
        ubyte[] buffer;
        ftp2.download("benjamin.mp3", buffer);
        
        /*
        * download to custom Stream
        */
        ftp2.download("benjamin.mp3", new File("myFile.mp3", FileMode.Out));
        
        /*
        * download content to string
        */
        string content = ftp2.download("index.php");
        
        /*
        * download content to specicifed type array,
        * in this case "ubyte" -> "ubyte[]"
        */
        ubyte[] mp3 = ftp2.download!(ubyte)("benjamin.mp3");
        
        /*
        * download file in background, in new thread
        */
        ftp2.downloadAsync("benjamin.mp3", "benjamin_copy.mp3");    
        
        /*
        * download file by 3 bytes chunks 
        */ 
        foreach (ubyte[] cur; ftp2.downloadByChunk!(3)("index.php") )
        {
            writeln( cast(string) cur);
        }
    }
}