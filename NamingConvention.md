Naming Convention: Overview
===========================
We would like to stick to .NET naming convention, which involes:

Classes and Structs
-------------------------
Classes and Structs are PascalCase.
Example:

```D
class HttpClient
{
 	
}

struct HttpHeader
{
 
}
```
 
Enums
-------------------------
Enumerations are PascalCase, same goes for their members
Example:

```D
enum HttpVersion
{
    OnePointZero,
    OnePointOne,
}
```
 
Methods and functions
-------------------------
Methods and functions, public or private all are cascalCase.
Example:

```D
class HttpClient
{
    public void connect()
	{
	
	}
	
	private bool isConnectionAlive()
	{
		return true;
	}
}
 
HttpClient simpleHttpConstructor()
{
 	return new HttpClient;
}
```
 
Methods and functions parameters
-------------------------
Methods and functions paremeters are camelCase.
Example:

```D
class HttpClient
{
 	public void post(const(char)[] postContentVariable)
 	{
 	
 	}
}
 
void simplePost(const(char)[] againVariable)
{
 
}
```
 
Public class/structs members and public @property
-------------------------
Above are cascalCase. 
Example:

```D
class HttpClient
{
 	public HttpHeaders responseHeaders;
 	
 	public HttpHeaders getResponseHeaders() @property
 	{
 		return responseHeaders;
 	}
}
```
 
Private class/structs members and private @property
-------------------------
Are camelCase.
Example:

```D
class HttpClient
{
 	private bool isConneted;
 	
 	private bool checkIfConnected() @property
 	{
 		return isConnected;
 	}
}
```
 
Local scope variables
-------------------------
Are camelCase.
Example:

```D
void foo()
{
 	string myLocalScopeVariable;
}
```
 
Hungarian Notations
-------------------------
Are not allowed.
Also try to make variables and functions names verbose
Example:

__Correct:__
```D
obj.OnOkButtonClicked = void delegate() {};
```

__Bad:__
```D
obj.OnOkBtnClkd = void delegate() {};
```


Indendt Style: Overview
===========================
We stick to __Allman__ style aka ANSI Style. No exceptions to this rule.
Tab width: __4 spaces__, we use spaces instead of tabs.