module netd.ftp;

import netd.uri;
import std.socket, std.stream, std.conv;
import std.traits;
import std.typecons, std.array, std.string;
import core.thread;

import std.stdio : writeln, writef, readln, writefln;
import std.datetime: Clock;

import std.c.stdio;

/*
* TODO: Secure FTP
*/

/**
* Ftp client class
*
* Example:
* ---------
* auto ftp = new Ftp("ftp.digitalmars.com", 21);
* ftp.open();
* ftp.download("dmd-2.056.zip", "localfile.zip");
* ftp.close();
* ---------
*/
class FtpClient
{
    enum defaultUser = "anonymous";
    enum defaultPass = "anonymous@anonymous";
    enum defaultPort = 21;
    enum bufferSize = 1024 * 4;
    
    private
    {
        alias Tuple!(ushort, "code", string, "msg") Response;
        alias Tuple!(string, "ip", ushort, "port") dataSocketInfo;
    
        bool _connected = false;
        Uri _uri;
        TcpSocket _socket;
        FtpStream _stream;
        Format _format;
        Mode _mode;
    }
    
    protected
    {
        bool _stopDownload = false;
    }
    
    /**
    * FTP transfer format
    */
    enum Format
    {
        Binary,
        Ascii,
    }
    
    /**
    * FTP transfer mode
    */
    enum Mode
    {
        Active,
        Passive,
    }
    
    /**
    * Delegate for reporting progress in downloading/uploading
    */
    void delegate(size_t current, size_t total) Progress;
    
    /**
    * Creates new FtpClient object
    *
    * Params:
    * host = Ftp server's host
    * port = Ftp server's port
    *
    */
    this(string host, ushort port = 21)
    {
        this();
        _uri.parse(host, port); 
    }
    
    /**
    * Creates new FtpClient
    *
    * Creates object without any host or port 
    * secified. You need to set host and port
    * manually, by using Ftp.host() method
    *
    */
    this()
    {
        _socket = new TcpSocket();
        _stream = FtpStream(_socket, 30);
        _mode = Mode.Passive;
        _format = Format.Binary;
    }
    
    /**
    * Ftp destructor
    *
    * Disconnects from host if connection
    * is still alive
    *
    */
    ~this()
    {
        close();
    }
    
    /**
    * Adds new authorization scheme
    *
    * Params:
    * username = Username
    * password = Password
    */
    void auth(string username, string password)
    {
        _uri.user     = username;
        _uri.password = password;
    }
    
    /**
    * Opens ftp connection
    *
    */
    void open()
    {
        if ( _connected == true ) return;
    
        _socket.connect(new InternetAddress(_uri.host, _uri.port));
    
        Response response = readResponse();
    
        if ( response.code != 220 )
        {
            throw new FtpException(response);
        }
    
        if ( _uri.user != "" )
        {
            response = exec("USER", _uri.user);
        
            if ( response.code != 331 )
            {
                throw new FtpException(response);
            }
        }
    
        if ( _uri.password != "" && _uri.password !is null )
        {
            response = exec("PASS", _uri.password);
        
            if ( response.code != 230 )
            {
                throw new FtpException(response);
            }
        }
        
        _connected = true;
    
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }
    }
    
    /** 
    * Stops any pending download/upload
    */
    void stopDownload()
    {
        _stopDownload = true;
        exec("ABOR");
    }
    
    /**
    * Closes connection with remote server
    *
    */
    void close()
    {
        if (_connected == false){
            return;
        }

        exec("QUIT");
        _socket.close();
        
        _connected = false;
    }
    
    /** 
    * Returns list of directories/files/links 
    * in directory
    *
    * Params:
    * path = Path to the folder which should be listed
    */
    FtpFile[] list(string path = "/")
    {
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }
        
        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        auto response = exec("LIST", path);
        
        if (response.code == 550)
        {
            throw new FtpException(response);
        }
        
        auto stream = FtpStream(sock, 30);
        char[10240] buffer;
        auto len = stream.read(buffer, this);
        
        sock.close();
        readResponse();
        
        auto data = buffer[0..len]; 
        FtpFile[] files;
        FtpFile file; 
        
        foreach (line; data.splitLines())
        {
            file = FtpFile(line);
            
            if (file.valid)
            {
                files ~= file;
            }
        }
        
        return files;
    }
    
    /**
    * Returns transfer format
    */
    @property Format format() const
    {
        return _format;
    }
    
    /**
    * Sets transfer format
    *
    * Params:
    * format = Transfer format
    */
    @property void format(Format format)
    {
        _format = format;
    }
    
    /**
    * Returns transfer mode
    */
    @property Mode mode() const
    {
        return _mode;
    }
    
    /**
    * Sets transfer mode
    * Params:
    * mode = Transfer mode
    */
    void mode(Mode mode)
    {
        _mode = mode;
    }
    
    
    /**
    * Returns size of specified file
    *
    * Params:
    * file = Name of file which sizes should be returned
    */
    size_t size(string file)
    {
        if (_format == Format.Binary)
        {
            auto response = exec("SIZE", file);
            if (response.code != 213)
            {
                throw new FtpException(response);
            }
            
            return to!(size_t)(chomp(response.msg));
        }
        else
        {
            auto _files = list(file);
            return _files[0].size;
        }
    }
    
    /**
    * Creates directory in current working directory with 
    * specified name
    *
    * Params:
    * name = Name for new directory
    */
    void createDir(string name)
    {
        auto response = exec("MKD", name);
        
        if ( response.code != 257 )
        {
            throw new FtpException(response);
        }
    }
    
    /**
    * Deletes directory in current working directory with 
    * specified name
    *
    * Params:
    * name = Name of the directory to delete
    */
    void deleteDir(string name)
    {
        auto response = exec("RMD", name);
        
        if ( response.code != 250 )
        {
            throw new FtpException(response);
        }
    }
    
    /**
    * Renames file/directory/link
    *
    * Params:
    * oldName = Old name of file
    * newName = New name of file
    */
    void rename(string oldName, string newName)
    {
        auto response = exec("RNFR", oldName);
        if ( response.code != 350 )
        {
            throw new FtpException(response);
        }
        
        response = exec("RNTO", newName);
        if ( response.code != 250 )
        {
            throw new FtpException(response);
        }
    }
    
    /**
    * Deletes file in current working directory with 
    * specified name
    *
    * Params:
    * name = Name of the file to delete
    */
    void deleteFile(string filename)
    {
        auto response = exec("DELE", filename);
        
        if ( response.code != 250 )
        {
            throw new FtpException(response);
        }
    }
    
    /**
    * Returns current working directory
    *
    */
    string currentDir()
    {
        auto response = exec("PWD");
        
        if ( response.code != 257 )
        {
            throw new FtpException(response);
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
    
    
    /**
    * Changes working directory
    *
    * Params:
    * path = Path to new working directory
    */
    void changeWorkingDir(string path)
    {
        auto response = exec("CWD", path);
        if ( response.code != 550 )
        {
            throw new FtpException(response);
        }
    }
    
    /**
    * Uploads local file to remote server
    *
    * Params:
    * localFile  = Path/Name of the file to upload
    * remoteFile = Desination name for remote file
    * resume     = Resumes transfer or starts from begining
    */
    size_t upload(string localFile, string remoteFile, bool resume = true)
    {
        return upload(new BufferedFile(localFile, FileMode.In, bufferSize), remoteFile, resume);
    }
    
    /**
    * Uploads local file to remote server
    *
    * Params:
    * localFile  = Stream for source file
    * remoteFile = Desination name for remote file
    * resume     = Resumes transfer or starts from begining
    */
    size_t upload(BufferedFile localFile, string remoteFile, bool resume = true)
    {
        writeln("Anyone calling me?");
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }
        
        size_t totalSize;
        if (Progress !is null)
        {
            totalSize = size(remoteFile);
        }
    
        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        if ( resume == true )
        {
            ulong size = size(remoteFile);
            localFile.position(size);
            exec("REST", size);
        }
        exec("STOR", remoteFile);
        writeln("STORING>>", remoteFile);
    
        ubyte[bufferSize] buffer;
        ptrdiff_t len = 0;
        size_t totalLen;
        
        enum convtime = convert!("seconds", "hnsecs")(60);
        ulong timeOut = Clock.currStdTime() + convtime;
    
        while (Clock.currStdTime() < timeOut)
        {
            len = localFile.read(buffer);
            if (len < 1) break;
            
            sock.send(buffer[0..len]);
            totalLen += len;
            
            if (Progress !is null)
            {
                Progress(totalLen, totalSize);
            }
            
            timeOut = Clock.currStdTime() + convtime;
        }

    
        sock.close();
        localFile.close();
        
        readResponse();
        
        return totalLen;
    }
    
    size_t download()(string remoteFile, string localFile, bool resume = true)
    {
        return download(remoteFile, new BufferedFile(localFile, FileMode.Out, bufferSize), resume);
    }
    
    size_t download()(string remoteFile, Stream localFile, bool resume = true)
    {
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }
    
        size_t totalSize;
        if (Progress !is null)
        {
            totalSize = size(remoteFile);
        }
    
        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        if ( resume == true )
        {
            ulong size = localFile.size();
            localFile.position(size);
            exec("REST", size);
        }
        exec("RETR", remoteFile);
    
    
        ubyte[bufferSize] buffer;
        ptrdiff_t len = 0;
        size_t totalLen;
        
        enum convtime = convert!("seconds", "hnsecs")(60);
        ulong timeOut = Clock.currStdTime() + convtime;
    
        while (Clock.currStdTime() < timeOut)
        {
            if (_stopDownload)
            {
                _stopDownload = false;
                return totalLen;
            }
            
            len = sock.receive(buffer);
            if (len < 1) break;
            
            localFile.write(buffer[0..len]);
            totalLen += len;
            
            if (Progress !is null)
            {
                Progress(totalLen, totalSize);
            }
            
            timeOut = Clock.currStdTime() + convtime;
        }

    
        sock.close();
        localFile.close();
        
        readResponse();
        
        return totalLen;
    }
    
    size_t put(T)(string filename, T data, bool append = false)
    {
        if (_format == Format.Ascii)
        {
            exec("TYPE A");
        }
        else
        {
            exec("TYPE I");
        }
        
        size_t totalSize;
        if (Progress !is null)
        {
            totalSize = data.length;
        }
    
        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        /*if ( resume == true )
        {
            ulong size = size(filename);
            localFile.position(size);
            exec("REST", size);
        }*/
        if (append == false)
        {
            exec("STOR", filename);
        }
        else
        {
            exec("APPE", filename);
        }
        
        writeln("PUTTING >>", filename);
    
        ptrdiff_t len = 0;
        size_t totalLen;
        size_t buffsize;
        
        enum convtime = convert!("seconds", "hnsecs")(60);
        ulong timeOut = Clock.currStdTime() + convtime;
    
        while (Clock.currStdTime() < timeOut)
        {
            if (totalLen == data.length) break;
            
            if (totalLen + bufferSize > data.length)
            {
                buffsize =  data.length - totalLen;
            }
            else
            {
                buffsize = bufferSize;
            }
            
            if (_format == Format.Ascii)
            {
                len = sock.send(to!(string)(data[totalLen..totalLen + buffsize]));
            }
            else
            {
                len = sock.send(data[totalLen..totalLen + buffsize]);
            }
            totalLen += len;
            
            if (Progress !is null)
            {
                Progress(totalLen, totalSize);
            }
            
            timeOut = Clock.currStdTime() + convtime;
        }

    
        sock.close();
        
        readResponse();
        
        return totalLen;
    }
    
    T[] get(T = immutable(char))(string filename, int offset = -1)
    {
        T[] buffer;
        size_t totalSize;
        if (Progress !is null)
        {
            totalSize = size(filename);
        }
    
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }

        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        if ( offset > 0 )
        {
            exec("REST", offset);
        }
        exec("RETR", filename);
        
        void[bufferSize] buff = void;
        size_t totalLen;
        
        enum convtime = convert!("seconds", "hnsecs")(60);
        ulong timeOut = Clock.currStdTime() + convtime;
        
        while (Clock.currStdTime() < timeOut)
        {
            if (_stopDownload)
            {
                _stopDownload = false;
                return buffer;
            }
            
            auto len = sock.receive(buff);
            
            if (len < 1) 
            {
                break;
            }
        
            buffer ~= cast(T[])buff[0..len];
            totalLen += len;
            
            if (Progress !is null)
            {
                Progress(totalLen, totalSize);
            }
        
            if (len < bufferSize)
            {
            //break;
            }
            timeOut = Clock.currStdTime() + convtime;
        }
        
        sock.close();
        readResponse();
        
        return buffer;
    }
    
    size_t get()(string remoteFile, scope void delegate(void[] data, size_t received) func, int offset = -1)
    {
        size_t totalSize;
        if (Progress !is null)
        {
            totalSize = size(remoteFile);
        }
    
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }

        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        if ( offset > 0 )
        {
            exec("REST", offset);
        }
        exec("RETR", remoteFile);
        
        void[bufferSize] buff = void;
        size_t totalLen;
        
        enum convtime = convert!("seconds", "hnsecs")(60);
        ulong timeOut = Clock.currStdTime() + convtime;
        
        while (Clock.currStdTime() < timeOut)
        {
            if (_stopDownload)
            {
                _stopDownload = false;
                return totalLen;
            }
            
            auto len = sock.receive(buff);
            
            if (len < 1) 
            {
                break;
            }
        
            func(buff[0..len], len);
            totalLen += len;
            
            if (Progress !is null)
            {
                Progress(totalLen, totalSize);
            }
        
            timeOut = Clock.currStdTime() + convtime;
        }
        
        sock.close();
        readResponse();
        
        return totalLen;
    }
    
    size_t get(T)(string remoteFile, ref T buffer, int offset = -1)
    if (isMutable!(T) && !isDelegate!(T))
    {
        size_t totalSize;
    
        if (Progress !is null)
        {
            totalSize = size(remoteFile);
        }
    
        if (_format == Format.Binary)
        {
            exec("TYPE I");
        }
        else
        {
            exec("TYPE A");
        }

        auto info = requestDataSocket();
        auto sock = createDataSocket(info);
        
        if ( offset > 0 )
        {
            exec("REST", offset);
        }
        exec("RETR", remoteFile);
        
        auto stream = FtpStream(sock, 60); 
        if (Progress !is null)
        {
            stream.Progress = (size_t current) { Progress(current, totalSize); };
        }
        
        auto len = stream.read(buffer, this);
        sock.close();
        readResponse();
        
        return len;
    }
    
    private:
    
    void writeRequest(T...)(string cmd, T args)
    {
        foreach ( arg; args )
        {
            cmd ~= " " ~ to!(string)(arg);
        }
    
        cmd ~= "\r\n";

        _socket.send(cmd);
        
        debug(Ftp)
        writeln("<", cmd);
    }
    
    Response exec(T...)(string cmd, T args)
    {
        writeRequest(cmd, args);
        
        return readResponse();
    }
    
    Response readResponse()
    {
        char[4096] resp;
        size_t len = _stream.readResponse(resp);
        
        Response response;
        
        if ( len < 5 ) {
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
        
        writeln(">", response.msg);
        
        return response;
    }
    
    dataSocketInfo requestDataSocket()
    {
        dataSocketInfo tuple;
        
        if ( _mode == Mode.Passive )
        {
            auto response = exec("PASV");
            if ( response.code != 227 )
            {
                throw new FtpException(response);
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
        Socket dataSock = new TcpSocket();
        dataSock.connect(new InternetAddress(info.ip, info.port));
        //dataSock.blocking(false);

        return dataSock;
    }
    
}

struct FtpFile
{
    enum Type
    {
        File,
        Directory,
        Link,
    }

    struct Time
    {
        ushort day;
        ushort month;
        string monthString;
        uint year;
        ushort hour;
        ushort min;
    }

    private
    {
        char[] 		_stream;
        bool   		_valid = false;
        
        Type  	 	_type;
        string 		_chmodString;
        ubyte[3]	_chmod;
        uint		_childs;
        string		_user;
        string 		_group;
        Time		_date;
        ulong		_size;
        string 		_filename;
    }

    this(char[] stream)
    {
        _stream = stream;
        parse();
    }

    @property Type type() const
    {
        return _type;
    }

    @property string chmodString()
    {
        return _chmodString;
    }

    @property ubyte[3] chmod() const
    {
        return _chmod;
    }

    @property uint child() const
    {
        return _childs;
    }
    
    @property string user()
    {
        return _user;
    }
    
    @property string group()
    {
        return _group;
    }
    
    @property Time time() const
    {
        return _date;
    }
    
    @property ulong size() const
    {
        return _size;
    }
    
    @property string name()
    {
        return _filename;
    }
    
    @property bool valid() const
    {
        return _valid;
    }

    void parse()
    {
        switch (_stream[0])
        {
            case 'b':
            case 'c':
            case 'd':
            case 'l':
            case 'p':
            case 's':
            case '-':
                parseDefault();
                return;
            break;
            case '+':
                parseEplf();
                return;
            break;
            default:
                parseDos();
            break;
        }
    }

    void parseDefault()
    {
        if (_stream.length < 3) return;
        
        switch (_stream[0])
        {
            case 'd':
                _type = Type.Directory;
            break;
            case '-':
                _type = Type.File;
            break;
            case 'l':
                _type = Type.Link;
            break;
            default:
                _type = Type.Directory;
            break;
        }

        char[][] split = _stream[1..$].split(" ");
        char[][] truncate = new char[][split.length];
        
        size_t iter;
        foreach (elem; split)
        {
            if (elem != "")
            {
            truncate[iter++] = elem;
            }
        }
        truncate = truncate[0..iter];
        
        if (truncate.length < 4)
        {
            _valid = false;
            return;
        }

        _chmodString = to!(string)(truncate[0]);
        _chmod = parseChmod(truncate[0]);
        _childs = to!(uint)(truncate[1]);
        _user = to!(string)(truncate[2]);
        _group = to!(string)(truncate[3]);
        _size = to!(ulong)(truncate[4]);
        _date = parseDate(truncate);
        _filename = parseFilename(truncate);
        
        if (_filename != "") {
            _valid = true;
        }
    }

    Time parseDate(const(char)[][] input)
    {
        Time time;
        
        if (_type == Type.Link)
        {
            input = input[5..$-3];
        }
        else
        {
            input = input[5..$-1];
        }
    
        foreach (elem; input)
        {
            if (!std.string.isNumeric(elem)) // either month or hour
            {
                if (elem[0] > '9') // month
                {
                    time.monthString = to!(string)(elem);
                    
                    final switch(toLower(elem))
                    {
                        case "jan":
                            time.month = 1;
                        break;
                        case "feb":
                            time.month = 2;
                        break;
                        case "mar":
                            time.month = 3;
                        break;
                        case "apr":
                            time.month = 4;
                        break;
                        case "may":
                            time.month = 5;
                        break;
                        case "jun":
                            time.month = 6;
                        break;
                        case "jul":
                            time.month = 7;
                        break;
                        case "aug":
                            time.month = 8;
                        break;
                        case "sep":
                            time.month = 9;
                        break;
                        case "oct":
                            time.month = 10;
                        break;
                        case "nov":
                            time.month = 11;
                        break;
                        case "dec":
                            time.month = 12;
                        break;
                    
                    }
                }
                else // hour:minute
                {
                    if (elem[2] == ':')
                    {
                        time.hour = to!(ushort)(elem[0..1]);
                        time.min  = to!(ushort)(elem[3..4]);
                    }
                }
            }
            else
            {
                if (elem.length == 4) // year
                {
                    time.year = to!(uint)(elem);
                }
                else if (elem.length == 2) // day
                {
                    time.day = to!(ushort)(elem);
                }
            }
        }
    
        if (time.year == 0)
        {
        time.year = Clock.currTime().year();
        }
    
        return time;
    }
    
    string parseFilename(const(char)[][] input)
    {
        if (_type == Type.Link)
        {
            // check last 3 entries
            if (input[$-2] == "->")
            {
                return to!(string)(input[$-3]);
            }
        }
    
        return to!(string)(input[$-1]);
    }

    void parseEplf(){}
    void parseDos(){}
    
    ubyte[3] parseChmod(const(char)[] chmod)
    {
        ubyte[3] octalChmod = 0;
        
        auto owner = chmod[0..3];
        if (owner[0] == 'r')
        {
            octalChmod[0] += 4;
        } 
        else if (owner[1] == 'w')
        {
            octalChmod[0] += 2;
        }
        else if (owner[2] == 'x')
        {
            octalChmod[0] += 1;
        }

        auto group = chmod[3..6];
        if (group[0] == 'r')
        {
            octalChmod[1] += 4;        
        }
        else if(group[1] == 'w')
        {
            octalChmod[1] += 2; 
        }
        else if(group[2] == 'x')
        {
            octalChmod[1] += 1;
        }
     
        auto other = chmod[6..9];
        if (other[0] == 'r')
        {
            octalChmod[2] += 4; 
        }
        else if(other[1] == 'w')
        {
            octalChmod[2] += 2; 
        }
        else if(other[2] == 'x')
        {
            octalChmod[2] += 1; 
        }
     
        writeln("owner: ", owner, "group: ", group, "other: ", other);
        
        return octalChmod;
    }
}

struct FtpStream
{
    Socket _socket;
    const ulong _timeOut;
    void delegate(size_t current) Progress;
    
    this (Socket socket, int timeOut)
    {
        _socket = socket;
        _timeOut = convert!("seconds", "hnsecs")(timeOut);
    }
    
    size_t readResponse(T)(ref T resp)
    if (isMutable!(T) &&
        (is(Unqual!(typeof(T[0])) : char) ||
        is(Unqual!(typeof(T[0])) : ubyte)))
    {
        typeof(T[0])[4096] buff;
        size_t totalLen;
        ulong timeOut = Clock.currStdTime() + _timeOut;
        
        ptrdiff_t len;
        
        if (buff.length > resp.length && resp.length > 0)
        buff = buff[0..resp.length];
        
        while (Clock.currStdTime() < timeOut && totalLen < resp.length)
        {
            len = _socket.receive(buff);
            
            resp[totalLen..totalLen+len] = buff[0..len];
            totalLen += len;
            
            if (Progress !is null)
            {
                Progress(totalLen);
            }
            
            if (len < buff.length)
            {
                break;
            }
            
            timeOut = Clock.currStdTime() + _timeOut;
        }
        
        return totalLen;
    }
    
    size_t read(T)(ref T resp, FtpClient cli)
    if ( isMutable!(T) &&
        (is(Unqual!(typeof(T[0])) : char) ||
        is(Unqual!(typeof(T[0])) : ubyte)) )
    {
        typeof(T[0])[4096] buff;
        size_t totalLen;
        ulong timeOut = Clock.currStdTime() + _timeOut;
        
        ptrdiff_t len;
        
        while (Clock.currStdTime() < timeOut && totalLen < resp.length)
        {
            if (cli._stopDownload)
            {
                cli._stopDownload = false;
                return totalLen;
            }
            
            len = _socket.receive(buff);
    
            if (len < 1)
                break;
    
            if (totalLen + len > resp.length)
            {
                auto fill = resp.length - totalLen;
                resp[totalLen..totalLen+fill] = buff[0..fill];
                return resp.length;
            }
    
            resp[totalLen..totalLen+len] = buff[0..len];
            totalLen += len;
    
            if (Progress !is null)
            {
                Progress(totalLen);
            }
    
            timeOut = Clock.currStdTime() + _timeOut;
        }
        
        return totalLen;
    }
}

class FtpException : Exception
{
    ushort code;
    string msg;
    
    this(Tuple!(ushort, "code", string, "msg") response, 
    string file = __FILE__, size_t line = __LINE__)
    {
        code = response.code;
        msg = response.msg;
        
        super("\n"~to!(string)(response.code) ~ ": " ~ response.msg ~ 
             "\n" ~ file ~ "(" ~ to!(string)(line) ~ ")\t" ~ "\t" 
         );
    }
}
