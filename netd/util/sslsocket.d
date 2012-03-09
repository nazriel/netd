/**
 * 
 * SSL Socket
 * 
 * SSL sockets support
 * 
 * Authors: $(WEB dzfl.pl, Damian "nazriel" Ziemba)
 * Copyright: 2012, Damian Ziemba
 * License: $(WEB http://www.boost.org/users/license.html, Boost license)
 * 
 */
 
/*
  TODO: - Load libssl on runtime?
        - Windows support ;)
 */
module netd.util.sslsocket;

import std.stdio, std.string, std.conv;
import std.socket;

pragma(lib, "ssl");

class SslSocket : Socket
{
    SSLCtx ctx;
    BIO* bio;
//DynamicLib sslDll;

    this(AddressFamily af, SocketType type, ProtocolType protocol)
    {
        /*sslDll = DynamicLib("libssl");
    sslDll.LoadSymbol("SSL_CTX_new", SSL_CTX_new);
    sslDll.LoadSymbol("SSLv23_method", SSLv23_method);
    sslDll.LoadSymbol("ERR_peek_error", ERR_peek_error);
    sslDll.LoadSymbol("ERR_get_error_line_data", ERR_get_error_line_data);
    sslDll.LoadSymbol("SSL_load_error_strings", SSL_load_error_strings);
    sslDll.LoadSymbol("SSL_library_init", SSL_library_init);
    sslDll.LoadSymbol("OPENSSL_add_all_algorithms_noconf", OPENSSL_add_all_algorithms_noconf);
    sslDll.LoadSymbol("RAND_load_file", RAND_load_file);
    sslDll.LoadSymbol("BIO_new_socket", BIO_new_socket);
    sslDll.LoadSymbol("BIO_new_ssl", BIO_new_ssl);
    sslDll.LoadSymbol("BIO_free_all", BIO_free_all);
    sslDll.LoadSymbol("BIO_push", BIO_push);
    sslDll.LoadSymbol("BIO_read", BIO_read);
    sslDll.LoadSymbol("BIO_write", BIO_write);*/


        SSL_load_error_strings();
        SSL_library_init();
        OPENSSL_add_all_algorithms_noconf();
        version(Posix)
            RAND_load_file(toStringz("/dev/urandom"), 2048);
        super(af, type, protocol);
        ctx = new SSLCtx;
        bio = ConvertSocketToSslSocket(false);
    }

    private BIO* ConvertSocketToSslSocket(bool close)
    {
        BIO *rtn = null;

        BIO *socketBio = BIO_new_socket(handle, close ? BIO_CLOSE : BIO_NOCLOSE);
        if (socketBio)
        {
            rtn = BIO_new_ssl(ctx.ctx, true);
            if (rtn)
                rtn = BIO_push(rtn, socketBio);
            if (!rtn)
                BIO_free_all(socketBio);
        }

        return rtn;
    }

    override long send(const(void)[] src)
    {
        if (src.length is 0)
            return 0;
        if (!isAlive) return 0;
        if (bio is null) return 0;

        int bytes = BIO_write(bio, src.ptr, cast(int) src.length);
        if (bytes <= 0)
            return 0;

        return cast(size_t) bytes;
    }

    override long receive(void[] dst)
    {
        if (!isAlive) return 0;
        if (bio is null) return 0;

        int bytes = BIO_read(bio, dst.ptr, cast(uint)dst.length);
        if (bytes <= 0)
            return 0;
        return cast(size_t) bytes;
    }
}
/*
static DynamicLib sslDll;

static this()
{
    sslDll = DynamicLib("libssl");
    sslDll.LoadSymbol("SSL_CTX_new", SSL_CTX_new);
    sslDll.LoadSymbol("SSLv23_method", SSLv23_method);
    sslDll.LoadSymbol("ERR_peek_error", ERR_peek_error);
    sslDll.LoadSymbol("ERR_get_error_line_data", ERR_get_error_line_data);
    sslDll.LoadSymbol("SSL_load_error_strings", SSL_load_error_strings);
    sslDll.LoadSymbol("SSL_library_init", SSL_library_init);
    sslDll.LoadSymbol("OPENSSL_add_all_algorithms_noconf", OPENSSL_add_all_algorithms_noconf);
    sslDll.LoadSymbol("RAND_load_file", RAND_load_file);
    sslDll.LoadSymbol("BIO_new_socket", BIO_new_socket);
    sslDll.LoadSymbol("BIO_new_ssl", BIO_new_ssl);
    sslDll.LoadSymbol("BIO_free_all", BIO_free_all);
    sslDll.LoadSymbol("BIO_push", BIO_push);
    sslDll.LoadSymbol("BIO_read", BIO_read);
    sslDll.LoadSymbol("BIO_write", BIO_write);


        SSL_load_error_strings();
        SSL_library_init();
        OPENSSL_add_all_algorithms_noconf();
        version(Posix)
            RAND_load_file(toStringz("/dev/urandom"), 2048);
}
*/
class SSLCtx
{
    SSL_CTX* ctx;
    DynamicLib sslDll;

    this()
    {

        ctx = SSL_CTX_new(SSLv23_method());

        if (ctx is null)
        {
        }
    }
}

/++
 + SSL
 +/
struct SSL_CTX;
struct SSL_METHOD;
/*
extern (C)
{
    SSL_CTX* function(SSL_METHOD*) SSL_CTX_new;
    SSL_METHOD* function() SSLv23_method;
    int function() ERR_peek_error;
    uint function(const(char)**, int*, const(char)**, int*) ERR_get_error_line_data;
    void function() SSL_load_error_strings;
    void function() SSL_library_init;
    void function() OPENSSL_add_all_algorithms_noconf;
    int function(const(char)*, int) RAND_load_file;
}*/
extern (C)
{
    SSL_CTX* SSL_CTX_new(SSL_METHOD*) ;
    SSL_METHOD* SSLv23_method();
    int ERR_peek_error();
    uint ERR_get_error_line_data(const(char)**, int*, const(char)**, int*);
    void SSL_load_error_strings();
    void SSL_library_init();
    void OPENSSL_add_all_algorithms_noconf();
    int RAND_load_file(const(char)*, int) ;
}
/++
 + Bio
 +/
struct BIO_METHOD;

struct BIO
{
    BIO_METHOD *method;
    int function(BIO *b, int a, char *c, int d, int e, int f) callback;
    char *cb_arg;
    int init;
    int shutdown;
    int flags;
}
/*
extern (C)
{
    BIO* function(int, int) BIO_new_socket;
    BIO* function(SSL_CTX*, int) BIO_new_ssl;
    void function(BIO *bio) BIO_free_all;
    BIO* function(BIO *b, BIO *append) BIO_push;
    int function(BIO *b, const(void)* data, int len) BIO_write;
    int function(BIO *b, void *data, int len) BIO_read;

    enum int BIO_CLOSE = 0x00;
    enum int BIO_NOCLOSE = 0x01;
}
*/
extern (C)
{
    BIO* BIO_new_socket(int, int);
    BIO*  BIO_new_ssl(SSL_CTX*, int);
    void BIO_free_all(BIO *bio);
    BIO* BIO_push(BIO *b, BIO *append);
    int BIO_write(BIO *b, const(void)* data, int len);
    int BIO_read(BIO *b, void *data, int len);

    enum int BIO_CLOSE = 0x00;
    enum int BIO_NOCLOSE = 0x01;
}
void throwOpenSSLError()
{
    if (ERR_peek_error())
    {
        char[] exceptionString;

        int flags;
        int line;
        const(char)* data;
        const(char)* file;
        uint code;

        code = ERR_get_error_line_data(&file, &line, &data, &flags);
        while (code != 0)
        {
            if (data && (flags & 0x02))
                exceptionString ~= text("ssl error code: %d %s:%d - %s\r\n", code, to!string(file), line, to!string(data));
            else
                exceptionString ~= format("ssl error code: %d %s:%d\r\n", code, to!string(file), line);

            code = ERR_get_error_line_data(&file, &line, &data, &flags);
        }
        throw new Exception(exceptionString.idup);
    }
}