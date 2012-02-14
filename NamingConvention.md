Naming Convention: Overview
===========================
We would like to stick to .NET naming convention, which involes:

Classes and Structs
-------------------------
Classes and Structs are PascalCase.
Example:
`class HttpClient
 {
 	
 }`
 
`struct HttpHeader
 {
 
 }`
 
Enums
-------------------------
Enumerations are PascalCase, same goes for their members
Example:
`enum HttpVersion
 {
 	OnePointZero,
 	OnePointOne,
 }`
 
Methods and functions
-------------------------
Methods and functions, public or private all are PascalCase.
Example:
`class HttpClient
 {
 	public void Connect()
	{
	
	}
	
	private bool IsConnectionAlive()
	{
		return true;
	}
 }
 
 HttpClient SimpleHttpConstructor()
 {
 	return new HttpClient;
 }
 `
 
Methods and functions parameters
-------------------------
Methods and functions paremeters are camelCase.
Example:
`class HttpClient
 {
 	public void Post(const(char)[] postContentVariable)
 	{
 	
 	}
 }
 
 void SimplePost(const(char)[] againVariable)
 {
 
 }`
 
Public class/structs members and public @propertys
-------------------------
Above are PascalCase. 
Example:
`class HttpClient
 {
 	public HttpHeaders ResponseHeaders;
 	
 	public HttpHeaders GetResponseHeaders() @property
 	{
 		return ResponseHeaders;
 	}
 }
 
 
Private class/structs members and private @property
-------------------------
Are camelCase.
Example:
`class HttpClient
 {
 	private bool isConneted;
 	
 	private bool checkIfConnected() @property
 	{
 		return isConnected;
 	}
 }`
 
Local scope variables
-------------------------
Are camelCase.
Example:
`void Foo()
 {
 	string myLocalScopeVariable;
 }`
 
Hungarian Notations
-------------------------
Are not allowed.
Also try to make variables and functions names verbose
Example:
Correct: OnOkButtonClicked 
Bad: OnOkBtnClkd


Indendt Style
===========================
We stick to Allman style aka ANSI Style.