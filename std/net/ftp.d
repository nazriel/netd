module std.net.ftp;

import std.net.uri;
import std.socket, std.stream, std.conv;
import std.traits;
import std.typecons, std.array, std.string;
import core.thread;

import std.stdio : writeln, writef, readln, writefln;
import std.datetime: Clock;


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
    
    enum Format
    {
    	Binary,
    	Ascii,
    }
    
    enum Mode
    {
    	Active,
    	Passive,
    }
    
    
    
    void delegate(size_t current, size_t total) Progress;
    
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
        this();
    }
    
    this()
    {
   		 _socket = new TcpSocket();
    	_stream = FtpStream(_socket, 30);
    	_mode = Mode.Passive;
    	_format = Format.Binary;
    }
   
    ~this()
    {
        //close();
        // need to implement somekind of lock in order to wait for
        // Async downloads to finish their work
    }
    
    void auth(string username, string password)
    {
    	_uri.user     = username;
    	_uri.password = password;
    }
    
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
    
    void close(ulong line = __LINE__)
    {
        if ( _connected == false ) return;
        
        exec("QUIT");
        _socket.close();
        
        _connected = false;
    }
    
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
       	auto len = stream.read(buffer);
       	
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
    
    @property Format format() const
    {
    	return _format;
    }
    
    @property void format(Format format_)
    {
    	_format = format_;
    }
    
    @property Mode mode() const
    {
        return _mode;
    }
    	
	void mode(Mode mode_)
	{
		_mode = mode_;
	}
 
 
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
 	
    void createDir(string name)
    {
        auto response = exec("MKD", name);
        
        if ( response.code != 257 )
        {
            throw new FtpException(response);
        }
    }
    
    void deleteDir(string name)
    {
        auto response = exec("RMD", name);
        
        if ( response.code != 250 )
        {
            throw new FtpException(response);
        }
    }
    
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
    
    void deleteFile(string filename)
    {
        auto response = exec("DELE", filename);
        
        if ( response.code != 250 )
        {
            throw new FtpException(response);
        }
    }
    
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
    
    void changeWorkingDir(string path)
    {
        auto response = exec("CWD", path);
        if ( response.code != 550 )
        {
            throw new FtpException(response);
        } 
    }
    
    void download()(string remoteFile, string localFile, bool resume = true)
    {
        download(remoteFile, new BufferedFile(localFile, FileMode.Out, bufferSize), resume);
    }
    
    void download()(string remoteFile, Stream localFile, bool resume = true)
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
        writeln("out of loop :(");
        sock.close();
        localFile.close();
        
        readResponse();
    }
    
    T[] get(T = immutable(char))(string filename, int offset = -1)
    {
    	T[] buff;
    	get(filename, buff, offset);
    	return buff;
    }
    
    size_t get(T = ubyte)(string remoteFile, ref T[] buffer, int offset = -1)
    if (!isStaticArray!(T[])) // append
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
        	auto len = sock.receive(buff);
        	
        	if (len < 1) 
        	{
        		break;
        	}	
        	
       		buffer ~= cast(typeof(buffer[0])[])buff[0..len];
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
        
       	return totalLen;
    }
   
    size_t get(T)(string remoteFile, ref T buffer, int offset = -1)
    if (isStaticArray!(T) && isMutable!(T))
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
       		//stream.Progress = (size_t current) { Progress(current, totalSize); };
   		}
   		
       	auto len = stream.read(buffer);
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
		ushort		_chmod;
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
	
	@property ushort chmod() const
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
		
		if (_filename != "")
			_valid = true;
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
	
	ushort parseChmod(const(char)[] chmod)
	{
		enforce(chmod.length == 9);
		ushort octalChmod = octal!(000);
		
		auto owner = chmod[0..3];
		if (owner[0] == 'r') {
			octalChmod = octalChmod & 100;
		}
		writeln(octalChmod);
		auto group = chmod[3..6];
		auto other = chmod[6..9];
		
		writeln("owner: ", owner, "group: ", group, "other: ", other);
		
		return octal!(000);
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
	if ( isMutable!(T) &&
		 (is(Unqual!(typeof(T[0])) : char) ||
		  is(Unqual!(typeof(T[0])) : ubyte)) )
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
	
	size_t read(T)(ref T resp)
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
        
        super("\n" ~ file ~ "(" ~ to!(string)(line) ~ ")\t" ~ "\t" ~ 
                to!(string)(response.code) ~ ": " ~ response.msg);
    }
}

debug(Ftp)
{
    import std.string, std.datetime;
    
    void main()
    {
    	
        auto ftp = new FtpClient(new Uri("ftp://ftp.mydevil.net", 21));
        ftp.auth("f11127_naz", "naz");
        //auto ftp = new FtpClient(new Uri("ftp://ftp.digitalmars.com"));
       // auto ftp = new FtpClient(new Uri("ftp://driv.pl", 5999));
        //ftp.auth("naz", "naz");
        
        ftp.open();
        auto files = ftp.list();
        
        foreach(file; files)
        writeln(file.chmod);
//        size_t filesize;
//        auto start = Clock.currStdTime();
//        ftp.Progress = (size_t current, size_t total) 
//        { 
//        	filesize = total;
//    	};
//    	auto end = Clock.currStdTime();
//    	
//        ftp.download("benjamin.mp3", "dmc.mp3", false);
        
        //writeln(z);
		//writeln(buff[0..z]);
        //string c = ftp.get("index.php");
        //ftp.createDir("chujmuje");
        
        
        
        /*char[10000] buffer;
		auto bytes = ftp.get("index.php", buffer);
		writeln(buffer[0..bytes]);
		
		string index_php = ftp.get("index.php");
		writeln(index_php);
		
		ftp.download("index.php", "local1.php");
		ftp.download("index.php", "local2.php");
		ftp.download("index.php", "local3.php");
		ftp.download("index.php", "local4.php");
		ftp.download("index.php", "local5.php");
		
		ftp.list();
		ftp.list();*/
 		ftp.close();
 		auto s = readln();
        /+ 
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
        }+/
    }
}