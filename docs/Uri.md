# Uri

Uri stands for Uniform Resource Identifer which is used to define resource on the Internet(mostly).
Std.net comes with Uri class made for parsing those. Here I'll try to explain how to use it.

Let's start from beggining - URI scheme, which is, how URI is built. Let's take this Uri as example:

    http://example.com:80/path/to/somewhere?blog=true&show=true#SomeHeader

We can split it into some parts:
 
         Authdata     Domain
            v           v          v Path                                v Fragment
    http://user:pass@example.com:80/path/to/somewhere?blog=true#SomeHeader 
    ^                            ^                   ^
    Scheme                      Port               Query

After parsing we will get something like:

 - __Scheme__: `http`  
 
 - __User__: `user`
 
 - __Pass__: `pass`
 
 - __Domain__: `example.com`
 
 - __Port__: `80`
 
 - __Path__: `path/to/somewhere`
 
 - __Query__: 
 
    - __QueryParam__: 
    
        - __Name__: `blog`
        - __Value__: `true`
 
 - __Fragment__: `SomeHeader`
 

As you may see, URI can be used almost to every resource, not only for web pages, but for example, for IRC:

    irc://irc.freeenode.net:6667/channelName

URI is even used for e-mails:

    username@example.com
    
Now, when you know a bit about URI, we can continue to class usage. 
First you have to import `netd.uri`, then you just have to create `new Uri` class. Here's example:

```D
import netd.uri;

void main()
{
    auto uri = new Uri("http://google.com");
    // Or
    auto uri = Uri.parseUri("http://google.com");
}
```

That's it! When constructor is  called, passed URI is automaticly being parsed.
Also `Uri.parseUri` calls Uri constructor. Now we have parsed Uri, 
we can get it's components easy. For example, to get Uri scheme use `uri.scheme`:

```D
import netd.uri;
import std.stdio;

void main()
{
    auto uri = new Uri("ftp://me:secretfoo@myhosting.com");
    
    // Try to conenct to ftp using imagined FTP class
    if(uri.scheme == uri.Ftp)
    {
        ftp_connect(uri.host, uri.port);
        ftp_auth(uri.user, uri.pass);    
    }
}
```
You can notice that there's no port in uri, but we connect with it and it works. Why? 
Because this class defines some basic default ports for several common protocols. Isn't it cool? :D
