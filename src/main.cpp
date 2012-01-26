#include <iostream>
#include <stdio.h>
#include <string>
#include <sstream>
#include <cstring>

// microhttpd
#include <microhttpd.h>

// Lua
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

#include "LuaFuncs.h"
#include "HandelConnection.h"

using namespace std;

CConnectionHandler ch;

int Port;

int Connection(void *cls, struct MHD_Connection *connection, const char *url, const char *method, const char *version, const char *upload_data, size_t *upload_data_size, void **con_cls)
{
	connection_t con;
	con.method = method;
	con.url = url;
	con.version = version;
	
	con.response = "";
	con.errcode = MHD_HTTP_OK;
	
	todo_t todo;
	todo.FileDataInstead = 0;
	// Now we setup our struct, we can pass it to the handeler
	ch.Handel(&con, connection, todo);
	
	const char *page  = con.response.c_str();
	
	struct MHD_Response* response;
	
	if(todo.FileDataInstead)
	{
		response = MHD_create_response_from_buffer (todo.FileDataLength, (void*)todo.FileDataInstead, MHD_RESPMEM_MUST_COPY);
		delete [] todo.FileDataInstead; // How does this know the size of the array?
	}
	else
		response = MHD_create_response_from_buffer (strlen (page), (void*)page, MHD_RESPMEM_MUST_COPY);
	
	for(auto it = todo.response_headers.begin(); it != todo.response_headers.end(); it++)
		MHD_add_response_header(response, it->first.c_str(), it->second.c_str());
	
	for(auto it = todo.set_cookies.begin(); it != todo.set_cookies.end(); it++)
	{
		string cookie = it->first + "=" + it->second;
		MHD_add_response_header(response, "Set-Cookie", cookie.c_str());
	}
	
	int ret = MHD_queue_response (connection, con.errcode, response);
	MHD_destroy_response (response);

	return ret;
}


int main (int argc, char* argv[])
{
	printf("Loading luaserver... ");
	
	if(argc > 3 || argc < 2)
	{
		printf("\t [Fail]\nNo port\n!");
		return 1;
	}
	
	string sport = argv[1];
	istringstream ( sport ) >> Port;
	
	//MHD_USE_SELECT_INTERNALLY
	struct MHD_Daemon *daemon = MHD_start_daemon(MHD_USE_SELECT_INTERNALLY | MHD_USE_THREAD_PER_CONNECTION, Port, NULL, NULL, &Connection, NULL, 
		MHD_OPTION_PER_IP_CONNECTION_LIMIT, 	(unsigned int)4,
		MHD_OPTION_CONNECTION_LIMIT, 			(unsigned int)30,
		MHD_OPTION_CONNECTION_TIMEOUT, 			(unsigned int)10,
	MHD_OPTION_END);
		
	if(!daemon)
	{
		printf("\t [Fail]\nPlease check nothing else is using the same port!\n");
		return 1;
	}
	
	printf("\t [OK]\n");
	
	while(true)
	{
		getchar();
	}

	MHD_stop_daemon (daemon);
	return 0;
}

	
	
	
