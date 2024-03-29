set echo on

begin
dbms_java.grant_permission(
grantee => 'TKYTE',
permission_type => 'java.net.SocketPermission',
permission_name => '*',
permission_action => 'connect,resolve' );
end;
/


create or replace type CorrelationType as object
(    name    varchar2(50),
    value    varchar2(8192)
)
/

create or replace type CorrelationArrayType
as varray(255) of CorrelationType
/

create or replace type CorrelatedArray as object
(
    -- These are an array of our name value pairs
    -- our methods below operate on this array
    vals    CorrelationArrayType,

    -- Given a name -- this searches the above varray
    -- for its value, returning NULL if no value is found
    member function valueof( p_name in varchar2 ) return varchar2,

    -- Adds a name/value pair to the end of the array
    -- does NOT check to see if that name already exists!
    -- use with caution, if that name already exists, this
    -- will not overwrite it (and if you call valueof, you'll
    -- get the OLD value at the front of the array)
    member procedure addpair(p_name in varchar2, p_value in varchar2),

    -- Add header line parses a string in the format:
    -- NAME: value
    -- which is the typical internet style header
    -- this uses addpair above
    member procedure addHeaderline( p_line in varchar2 ),

    -- updates an existing entry or if none exists, calls
    -- addpair to add it to the end
    member procedure updateValue( p_name in varchar2,
                                  p_value in varchar2 )
)
/

create or replace type body CorrelatedArray as

  member procedure
  addpair( p_name in varchar2, p_value in varchar2 )
  is
  begin
    vals.extend;
    vals( vals.count ) := CorrelationType( upper(p_name), p_value );
  end addpair;

  member procedure
  updateValue( p_name in varchar2, p_value in varchar2 )
  is
    l_found boolean := FALSE;
  begin
    for i in 1 .. vals.count loop
      if vals(i).name = p_name then
        vals(i).value := p_value;
        l_found := TRUE;
        exit;
      end if;
    end loop;
    if not l_found then
      addpair( p_name, p_value );
    end if;
  end updateValue;

  member function
  valueof( p_name in varchar2 )  return varchar2
  is
    l_name    varchar2(50) default upper(p_name);
    l_idx    number default 1;
  begin
    for i in 1 .. vals.count loop
      exit when ( vals(i).name = l_name );
      l_idx := l_idx+1;
    end loop;

    if ( l_idx <= vals.count ) then
      return vals(l_idx).value;
    else
      return NULL;
    end if;
  end valueof;

  member procedure
  addHeaderLine( p_line in varchar2 )
  is
    l_n number default instr(p_line,':');
  begin
    addpair( trim(substr( p_line, 1, l_n-1 )),
             trim(substr(p_line,l_n+1)) );
  end addHeaderLine;

end;
/

create or replace package http_pkg
as

    -- functions request and request_pieces are functionally
    -- equivalent to functions found in the utl_http package
    -- from version 7.3.x, 8.0.x, and 8.1.5.

    function request( url in varchar2,
                      proxy in varchar2 default NULL )
    return varchar2;

    type html_pieces is table of varchar2(2000)
       index by binary_integer;

    function request_pieces(url in varchar2,
                            max_pieces natural default 32767,
                            proxy in varchar2 default NULL)
    return html_pieces;

    init_failed exception;
    request_failed exception;


    -- procedure GET_URL.  Invokes the standard  HTTP GET
    -- syntax on a webserver.  The inputs are:

    --   p_url is the URL to retrieve,

    --   p_proxy is the name:<port> of the proxy server to use.
    --           NULL indicates you need not use a proxy server.
    --           Examples: p_proxy => 'www-proxy'
    --                     p_proxy => 'www-proxy:80'

    --  p_status is returned to you.  it will be the
    --           HTTP status code returned by the webserver.
    --           200 indicates normal, successful completion.
    --           401 indicates unauthorized, and so on

    -- p_status_txt is returned to you.  It contains the full
    --              text of the HTTP status record.  For
    --              example it might contain:
    --                  "HTTP/1.0 200 OK"

    -- p_httpHeaders may be set by you and upon return will
    --               contain the http headers from the
    --               requested URL.  On input, any values
    --               you have set will be transmitted to the
    --               webserver as part of the request.
    --               On output, the headers generated by the
    --               webserver will be returned to
    --               you.  You can use this to set and
    --               send cookies or basic authentication
    --               or any other http header record you wish

    -- p_content is a TEMPORARY clob that will be allocated
    --           for you in this package (you need not
    --           allocate it).  it is a session temporary lob.
    --           You may use dbms_lob.freetemporary to
    --           deallocate it whenever you want, or just
    --           let it disappear when you log out.

    procedure get_url( p_url        in varchar2,
                       p_proxy      in varchar2 default NULL,
                       p_status           out number,
                       p_status_txt       out varchar2,
                       p_httpHeaders   in out CorrelatedArray,
                       p_content    in out clob );


    -- This overloaded version of get_url works as
    -- above however it returns its data in a BLOB,
    -- not a CLOB.  That makes this appropriate
    -- to retrieve documents such as pdf files, gifs, etc.


    procedure get_url( p_url        in     varchar2,
                       p_proxy      in     varchar2 default NULL,
                       p_status           out number,
                       p_status_txt       out varchar2,
                       p_httpHeaders   in out CorrelatedArray,
                       p_content    in out blob );

    -- procedure HEAD_URL.  Invokes the standard  HTTP
    -- HEAD syntax on a webserver.  The inputs and outputs
    -- are identical to get_url above (except NO content
    -- is retrieved)


    procedure head_url( p_url        in varchar2,
                        p_proxy      in varchar2 default NULL,
                        p_status        out number,
                        p_status_txt       out varchar2,
                        p_httpHeaders   out CorrelatedArray );

    -- function URL encode is used when building GET parameter
    -- lists or building POST clobs.  It is used to escape
    -- special characters in urls (eg: a URL may not contain
    -- a BLANK, a URL may not contain a % sign, and so on).
    -- given input such as:  'Hello World', urlencode will
    -- return 'Hello%20World'

    function urlencode( p_str in varchar2 ) return varchar2;


    -- procedure Add_A_Cookie allows you to easily set a
    -- cookie value to be sent to a webserver.
    -- you need only know the name and value
    -- of the cookie.  the formatting of the HTTP header
    -- record is performed by this routine.  The p_httpHeaders
    -- variable you send in/out of this
    -- routine would be sent in/out of the
    -- <Get|Head|Post>_url routines

    procedure add_a_cookie
             ( p_name in varchar2,
               p_value in varchar2,
               p_httpHeaders in out CorrelatedArray );


    -- procedure Set_Basic_Auth allows you to enter a
    -- username/password to access a protected page.
    -- you need only know the name and password
    -- to be used.  the formatting of the HTTP header
    -- record is performed by this routine.  The
    -- p_httpHeaders variable you send in/out of this
    -- routine would be sent in/out of the
    -- <Get|Head|Post>_url routines

    procedure set_basic_auth
              ( p_username in varchar2,
                p_password in varchar2,
                p_httpHeaders in out CorrelatedArray );


    -- procedure set_post_parameter is used when retrieving
    -- a URL that needs a large (>2000 or so bytes)
    -- set of inputs.  It is recommened
    -- that the POST method be used for large requests.
    -- This routine allows you to add parameter after
    -- parameter to a POST request.  This post
    -- request is built into a clob you supply

    -- parameters:
    -- p_name  is the name of the variable to add to
    --         the post data

    -- p_value is the value of that parameter

    -- p_post_data is the clob to append this data to, clob
    --             will be initialized for you if need be.

    -- p_urlencode is a booelean instructing us to urlencode the
    --             P_VALUE variable or not.  by default, it is
    --             FALSE -- we do NOT encode

    procedure set_post_parameter
              ( p_name in varchar2,
                p_value in varchar2,
                p_post_data in out clob,
                p_urlencode in boolean default FALSE );


    -- identical to GET_URL above with the addition
    -- of the p_post_data input p_post_data is a clob
    -- built by repeated calls to set_post_parameter
    -- above.

    procedure post_url
              (p_url        in     varchar2,
               p_post_data  in     clob,
               p_proxy      in     varchar2 default NULL,
               p_status           out number,
               p_status_txt       out varchar2,
               p_httpHeaders   in out CorrelatedArray,
               p_content    in out clob );

    procedure post_url
              (p_url        in     varchar2,
               p_post_data  in     clob,
               p_proxy      in     varchar2 default NULL,
               p_status           out number,
               p_status_txt       out varchar2,
               p_httpHeaders   in out CorrelatedArray,
               p_content    in out blob );


end;
/


create or replace package body http_pkg
as

-- A global socket used by all of these routines.
-- on any call this socket will be OPENED and CLOSED
-- before we return.

Socket       SocketType := SocketType(null);


-- In support of the 7.3, 8.0 Original UTL_HTTP implementation
-- Request and Request_Pieces are functionally equivalent
-- to these previous versions
-- request and request_pieces simple call the GET_URL
-- functions and convert their return types into the old
-- style return types.
-- Request pieces has to do a moderate amount of very simple
-- parsing but overall these functions are very straightforward.

function request( url      in varchar2,
                  proxy in varchar2 default NULL )
return varchar2
is
    l_content       clob;
    l_status        number;
    l_status_txt    varchar2(255);
    l_httpHeaders   CorrelatedArray;
    l_return        varchar2(2000);
begin
    get_url( url, proxy, l_status, l_status_txt,
             l_httpHeaders, l_content );

    l_return := dbms_lob.substr( l_content, 2000, 1 );
    dbms_lob.freetemporary( l_content );

    return l_return;
end;



function request_pieces
         (url in varchar2,
          max_pieces natural default 32767,
          proxy in varchar2 default NULL)
return html_pieces
is
    l_content       clob;
    l_status        number;
    l_status_txt    varchar2(255);
    l_httpHeaders   CorrelatedArray;
    l_return        html_pieces;
    l_offset        number default 1;
    l_length        number;
begin
    get_url( url, proxy, l_status, l_status_txt,
             l_httpHeaders, l_content );

    l_length := dbms_lob.getlength(l_content);
    loop
        exit when (l_offset > l_length OR
                           l_return.count >= max_pieces );
        l_return( l_return.count+1 ) :=
            dbms_lob.substr(l_content,2000,l_offset );
        l_offset := l_offset + 2000;
    end loop;

    dbms_lob.freetemporary( l_content );

    return l_return;
end;


-- A convenience routine to format and send the
-- request to the HTTP server.     We build the headers
-- into a single string to be transmitted.  The first
-- line of the request is a GET or HEAD or POST follwed
-- by a URL and the protocol (we support only HTTP/1.0)
--
-- then we add to this string every other header record
-- you asked us to send.  this will contain cookies,
-- authentication and so on.
--
-- if you are doing a POST, we add in the content length
-- of the data we will post.  The webserver needs that
-- so it knows where your request STOPS.
--
-- lastly, we send the headers and if POST is the
-- request type -- the POST data itself.

procedure send_headers( p_url in varchar2,
                        p_httpHeaders in CorrelatedArray,
                        p_request in varchar2,
                        p_post_data in clob )
is
    l_headers long;
begin
    l_headers := p_request || ' ' ||
                 p_url || ' HTTP/1.0' ||
                 SocketType.crlf;

    if ( p_httpHeaders is NOT null )
    then
        for i in 1 .. p_httpHeaders.vals.count
        loop
            l_headers := l_headers ||
                         initcap(p_httpHeaders.vals(i).name) ||
                         ': ' ||
                         p_httpHeaders.vals(i).value ||
                         SocketType.crlf;
        end loop;
    end if;
    if ( p_request = 'POST' ) then
        l_headers := l_headers || 'Content-length: ' ||
                        dbms_lob.getlength(p_post_data) ||
                        SocketType.crlf;
        l_headers := l_headers ||
           'Content-Type: application/x-www-form-urlencoded' ||
            SocketType.crlf;
    end if;
    l_headers := l_headers || SocketType.crlf;
    Socket.send( l_headers );

    if ( p_request = 'POST' ) then
        Socket.send( p_post_data );
    end if;
end;



-- another convenience routine.  This takes the URL
-- you sent to us and figures out what server we need
-- to connect to, on what port and with what request...

procedure parse_server_port_url( p_url in varchar2,
                                 p_proxy in varchar2,
                                 p_server in out varchar2,
                                 p_port    in out number,
                                 p_url_out in out varchar2 )
is
    l_colon number default instr( p_proxy, ':' );
    l_url   long;
    l_slash number;
begin
    if ( p_proxy is NOT NULL )
    then
        if ( l_colon = 0 ) then
            p_server := p_proxy;
            p_port   := 80;
        else
            p_server := substr( p_proxy, 1, l_colon-1 );
            p_port   := substr( p_proxy, l_colon+1 );
        end if;
        p_url_out :=  p_url;
    else
        if ( p_url not like 'http://%' ) then
            raise init_failed;
        end if;
        l_url := substr( p_url, 8 );
        l_slash := instr( l_url, '/' );
        l_colon := instr( l_url, ':' );
        if ( l_colon > 0 AND l_colon < l_slash )
        then
            p_server := substr( l_url, 1, l_colon-1 );
            p_port   := substr( l_url, l_colon+1,
                                        l_slash-(l_colon+1));
            p_url_out:= substr( l_url, l_slash );
        else
            p_server := substr( l_url, 1, l_slash-1 );
            p_port   := 80;
            p_url_out:= substr( l_url, l_slash );
        end if;
    end if;
end;


-- these two routines are identical except one does a RAW
-- read and the other a TEXT read into a BLOB or CLOB.
-- the respect the content-length as set by the web server
-- if it is present, else they read to end of file
-- (signified by a NULL return from Socket.recv)

procedure get_clob_content( p_httpHeaders in CorrelatedArray,
                            p_content     in out clob )
as
    l_content_length number;
    l_str_data         long;
begin
    l_content_length :=
           p_httpHeaders.valueof( 'Content-Length' );

    dbms_lob.createtemporary( p_content, TRUE );
    loop
        exit when (dbms_lob.getlength(p_content) >=
                                          l_content_length);
        l_str_data := Socket.recv;
        exit when ( l_str_data is NULL ); -- eof
        dbms_lob.writeappend( p_content, length(l_str_data),
                              l_str_data );
    end loop;
end;

procedure get_blob_content( p_httpHeaders in CorrelatedArray,
                            p_content     in out blob )
as
    l_content_length number;
    l_raw_data       long raw;
begin
    l_content_length :=
             p_httpHeaders.valueof( 'Content-Length' );

    dbms_lob.createtemporary( p_content, TRUE );
    loop
        exit when (dbms_lob.getlength(p_content) >=
                                        l_content_length);
        l_raw_data := Socket.recv_raw;
        exit when ( l_raw_data is NULL ); -- eof
        dbms_lob.writeappend( p_content,
                              utl_raw.length(l_raw_data),
                              l_raw_data );
    end loop;
end;


-- this internal get_url routine is used to connect to the
-- web server and send the request and parse the HTTP headers
-- that come back.  It does the "real" work.  The only
-- thing left after this runs is to read the actual content
-- of the web page.

procedure get_url_i( p_url         in      varchar2,
                     p_proxy       in      varchar2,
                     p_request     in      varchar2,
                     p_status             out number,
                     p_status_txt      out varchar2,
                     p_httpHeaders in  out CorrelatedArray,
                     p_post_data   in      clob default NULL )
is
    l_server    varchar2(255);
    l_port        number;
    l_url        long;
    l_str_data            long;
begin
    parse_server_port_url( p_url, p_proxy, l_server,
                           l_port, l_url );

    Socket.initiate_connection( l_server, l_port );

    send_headers( l_url, p_httpHeaders,
                  p_request, p_post_data );

    l_str_data := Socket.getline;
    p_status := substr(l_str_data, instr(l_str_data,' ')+1, 3);
    p_status_txt := l_str_data;

    p_httpHeaders := CorrelatedArray(CorrelationArrayType());
    loop
        l_str_data := Socket.getline(true);
        exit when l_str_data  is null or length(l_str_data) < 4;
        p_httpHeaders.addHeaderline( l_str_data );
    end loop;

end get_url_i;


-- the actual externalized procedures.     These are what
-- we call from outside of this package.  They simply
-- "get" the URL and then get the content and close the
-- connection...
procedure get_url( p_url         in      varchar2,
                   p_proxy       in      varchar2 default NULL,
                   p_status             out number,
                   p_status_txt      out varchar2,
                   p_httpHeaders in  out CorrelatedArray,
                   p_content     in  out clob )
is
begin
    get_url_i( p_url, p_proxy, 'GET', p_status,
               p_status_txt, p_httpHeaders );

    get_clob_content( p_httpHeaders, p_content );
    Socket.close_connection;
end get_url;


procedure get_url( p_url         in      varchar2,
                   p_proxy       in      varchar2 default NULL,
                   p_status          out number,
                   p_status_txt      out varchar2,
                   p_httpHeaders in  out CorrelatedArray,
                   p_content     in  out blob )
is
begin
    get_url_i( p_url, p_proxy, 'GET', p_status,
               p_status_txt, p_httpHeaders );

    get_blob_content( p_httpHeaders, p_content );
    Socket.close_connection;
end get_url;


-- head is even more simple then get above -- no content
-- to retrieve.

procedure head_url( p_url        in     varchar2,
                    p_proxy      in     varchar2 default null,
                    p_status        out number,
                    p_status_txt    out varchar2,
                    p_httpHeaders   out CorrelatedArray )
is
begin
    get_url_i( p_url, p_proxy, 'HEAD', p_status,
               p_status_txt, p_httpHeaders );
    Socket.close_connection;
end;


-- a very simple routine that escapes all characters
-- found in your string that are in the l_bad string
-- these characters cannot appear in the URL request
-- and cannot appear in posted data.  It is illegal to
-- have a request like: "http://host/foo?x=Hello%"
-- the % must be escaped so the string is:
-- http://host/foo?x=Hello%25

function urlencode( p_str in varchar2 ) return varchar2
as
    l_tmp   varchar2(6000);
    l_bad   varchar2(100) default ' >%}\~];?@&<#{|^[`/:=$+''"';
    l_char  char(1);
begin
    for i in 1 .. nvl(length(p_str),0) loop
        l_char :=  substr(p_str,i,1);
        if ( instr( l_bad, l_char ) > 0 )
        then
            l_tmp := l_tmp || '%' ||
                            to_char( ascii(l_char), 'fmXX' );
        else
            l_tmp := l_tmp || l_char;
        end if;
    end loop;

    return l_tmp;
end;


-- you may send upto 4k of cookie data.  cookies are
-- stashed in the header in the format:
-- name=value;name=value;name=value
--
-- as you can see -- your cookie should not have = and ;
-- in it

procedure add_a_cookie( p_name in varchar2,
                        p_value in varchar2,
                        p_httpHeaders in out CorrelatedArray )
is
    l_cookie_string long;
begin
    if ( p_httpHeaders is null ) then
        p_httpHeaders :=
            CorrelatedArray(CorrelationArrayType());
    end if;

    l_cookie_string := p_httpHeaders.valueof('Cookie') ||
                        ';' || p_name || '=' || p_value;

    p_httpHeaders.updatevalue( 'cookie',
                                ltrim(l_cookie_string,';') );
end;


-- to gain access to a page protected by basic
-- authentication, we must send an authorization header
-- record.  The username/password must be base 64
-- encoded (obscured) before this happens.  this
-- routine does that for us.

procedure set_basic_auth( p_username in varchar2,
                          p_password in varchar2,
                          p_httpHeaders in out CorrelatedArray )
is
    l_b64encoded varchar2(255);
begin
    if ( p_httpHeaders is null ) then
        p_httpHeaders :=
          CorrelatedArray(CorrelationArrayType());
    end if;

    simple_tcp_client.b64encode
    ( utl_raw.cast_to_raw( p_username || ':' || p_password ),
      l_b64encoded );

    p_httpHeaders.updatevalue( 'Authorization',
                               'Basic ' || l_b64encoded );
end;


-- this routine lets you build a POST set of data.  If
-- the amount of data you need to send to the webserver is
-- larger, you should post it.     This expects you to start
-- with an uninitialized CLOB, we'll allocate space for it
-- and fill up the data.  If you set p_urlencode to true,
-- we will escape all invalid characters automatically for
-- you...

procedure set_post_parameter
          ( p_name in varchar2,
            p_value in varchar2,
            p_post_data in out clob,
            p_urlencode in boolean default FALSE )
is
    l_encoded_value        long;
begin
    if ( p_post_data is null ) then
        dbms_lob.createtemporary( p_post_data, TRUE );
    else
        dbms_lob.writeappend( p_post_data, 1, '&' );
    end if;

    dbms_lob.writeappend( p_post_data, length(p_name)+1,
                          p_name||'=' );

    if ( p_urlencode )
    then
        l_encoded_value := urlencode( p_value );
    else
        l_encoded_value := p_value;
    end if;
    dbms_lob.writeappend( p_post_data, length(l_encoded_value),
                          l_encoded_value );
end;

-- The procedures for POSTing are very much the same as
-- for GETting except they take the data to post as well
-- they do the same exact logic otherwise...

procedure post_url(p_url        in     varchar2,
                   p_post_data  in     clob,
                   p_proxy      in     varchar2 default NULL,
                   p_status        out number,
                   p_status_txt    out varchar2,
                   p_httpHeaders   in out CorrelatedArray,
                   p_content    in out clob )
is
begin
    get_url_i( p_url, p_proxy, 'POST', p_status, p_status_txt,
               p_httpHeaders, p_post_data );

    get_clob_content( p_httpHeaders, p_content );
    Socket.close_connection;
end ;

procedure post_url(p_url        in     varchar2,
                   p_post_data  in     clob,
                   p_proxy      in     varchar2 default NULL,
                   p_status        out number,
                   p_status_txt    out varchar2,
                   p_httpHeaders   in out CorrelatedArray,
                   p_content    in out blob )
is
begin
    get_url_i( p_url, p_proxy, 'POST', p_status, p_status_txt,
               p_httpHeaders, p_post_data );

    get_blob_content( p_httpHeaders, p_content );
    Socket.close_connection;
end ;

end http_pkg;
/

