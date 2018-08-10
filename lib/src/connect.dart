//Copyright (C) 2013 Potix Corporation. All Rights Reserved.
//History: Tue, Jan 08, 2013 12:04:43 PM
// Author: tomyeh
part of stream;

/** A HTTP channel.
 * A channel represents the Internet address and port that [StreamServer]
 * is bound to.
 *
 * A channel can serve multiple HTTP connection ([HttpConnect]). A HTTP
 * connection is actually a pair of [HttpRequest] and [HttpResponse].
 */
abstract class HttpChannel {
  ///The connection information summarizing the number of current connections
  //handled in this channel.
  HttpConnectionsInfo get connectionsInfo;
  /** When the server started. It is null if never started.
   * 
   * > Note: we use [startedSince] to set LAST_MODIFIED if
   * > `lastModified="start"`.
   */
  DateTime get startedSince;

  /** Closes the channel.
   *
   * To start all channels, please use [StreamServer.stop] instead.
   */
  Future close();
  /** Indicates whether the channel is closed.
   */
  bool get isClosed;

  ///The Stream server for serving this channel.
  StreamServer get server;

  /** The internal HTTP server for serving this channel.
   * 
   * Note: [server] starts one or multiple [HttpServer] instances to serve
   * one or multiple channels. Each channel is served by one [HttpServer] instance.
   */
  HttpServer get httpServer;

  ///The socket that this channel is bound to.
  ///It is available only if the channel is started by [StreamServer.startOn].
  ServerSocket get socket;

  /** The address. It can be either a [String] or an [InternetAddress].
   * It is null if the channel is started by [StreamServer.startOn].
   */
  get address;
  ///The port.
  int get port;
  ///Whether it is a HTTPS channel
  bool get isSecure;
}

/** The request filter. It is used with the `filterMapping` parameter of [StreamServer].
 *
 * * [chain] - the callback to *resume* the request handling. If there is another filter
 * (including the default handling, such as URI mapping and resource loading),
 * it will be invoked when you call back [chain].
 * If you'd like to skip the handling (e.g., redirect to another page),
 * you don't have to call back [chain].
 *
 * Before calling back [chain], you can proxy the request and/or response, such as writing the
 * the response to a string buffer.
 */
typedef Future RequestFilter(HttpConnect connect, Future chain(HttpConnect conn));
/** The request handler.
 *
 * If a request handler finishes immediately, it doesn't have to return anything.
 * For example,
 *
 *     void serverInfo(HttpConnect connect) {
 *       final info = {"name": "Rikulo Stream", "version": connect.server.version};
 *       connect.response
 *         ..headers.contentType = getContentType("json")
 *         ..write(JSON.encode(info));
 *     }
 *
 * On the other hand, if a request is handled asynchronously, it *must* return
 * an instance of [Future] for indicating if the handling is completed. For example,
 *
 *     Future loadFile(HttpConnect connect) {
 *       final completer = new Completer();
 *       final res = connect.response;
 *       new File("some_file").openRead().listen((data) {res.writeBytes(data);},
 *         onDone: () => completer.complete(),
 *         onError: (err, stackTrace) => completer.completeError(err, stackTrace));
 *       return completer.future;
 *     }
 *
 * As shown above, the error has to be *wired* to the Future object being returned.
 *
 * > The returned `Future` object can carry any type of objects. It is applications
 * specific. Stream server simply ignores it.
 *
 * > Though not specified, the handler can have any number of named arguments.
 * They are application specific. Stream server won't pass anything but the default
 * values.
 */
typedef Future RequestHandler(HttpConnect connect);

/** A HTTP request connection.
 */
abstract class HttpConnect {
  /** Instantiates a connection by redirecting the output to the given buffer
   * (bytes).
   */
  factory HttpConnect.buffer(HttpConnect origin, List<int> buffer)
  => new _BufferedConnect(origin, buffer);
  /** Instantiates a connection by redirecting the output to the given
   * string buffer.
   */
  factory HttpConnect.stringBuffer(HttpConnect origin, StringBuffer buffer)
  => new _StringBufferedConnect(origin, buffer);
  /** Instantiates a connection that will be used to include or forward to
   * another request handler.
   *
   * * [uri] - the URI to chain with. If omitted, it is the same as [connect]'s.
   * It can contain the query string too.
   * * [inclusion] - whether it is used for inclusion. If true,
   * any modification to `connect.response.headers` is ignored.
   */
  factory HttpConnect.chain(HttpConnect connect, {bool inclusion: true,
      String uri, HttpRequest request, HttpResponse response}) {
    return inclusion ?
      new _IncludedConnect(connect, request, response, uri):
      new _ForwardedConnect(connect, request, response, uri);
  }

  ///The Stream server
  StreamServer get server;
  ///The channel that this connection is on.
  HttpChannel get channel;
  ///The HTTP request.
  HttpRequest get request;
  /** The HTTP response.
   *
   * Notice that you shall *NOT* invoke `response.close()`, since it was
   * called automatically when the serving of a request is finished.
   */
  HttpResponse get response;
  ///The source connection that forwards to this connection, or null if not forwarded.
  HttpConnect get forwarder;
  ///The source connection that includes this connection, or null if not included.
  HttpConnect get includer;
  /** Whether this connection is caused by inclusion.
   * Note: it is true if [includer] is not null or [forwarder] is included.
   */
  bool get isIncluded;
  /** Whether this connection is caused by forwarding.
   * Note: it is true if [forwarder] is not null or [includer] is forwarded.
   */
  bool get isForwarded;

  /** Send a temporary redirect to the specified redirect URL.
   *
   * * [url] - the location to redirect to. It can be an URI or URL, such as
   * `/login?whatever` and `http://rikulo.org/project/stream`.
   *
   * > Notice: you shall invoke this method instead of `HttpResponse.redirect()`,
   * since `HttpResponse.redirect()` will close the connection (which
   * will be called automatically under Rikulo Stream).
   */
  void redirect(String url, {int status: HttpStatus.movedTemporarily});

  /** Forward this connection to the given [uri].
   *
   * If [request] and/or [response] is ignored, the request and/or response
   * of this connection is assumed.
   * If [uri] is null, `connect.uri` is assumed, i.e., forwarded to the same handler.
   *
   * After calling this method, the caller shall write the output stream in `then`, since
   * the request handler for the given URI might handle it asynchronously. For example,
   *
   *     await connect.forward(connect, "another");
   *     connect.response.write("<p>More content</p>");
   *     ...
   *
   * * [uri] - the URI to chain. If omitted, it is the same as this connection.
   * It can contain the query string too.
   *
   * ##Difference between [forward] and [include]
   *
   * [forward] and [include] are almost the same, except
   *
   * * The included request handler won't be able to generate any HTTP headers
   * (it is the job of the caller). Any updates to HTTP headers in the included
   * request handler are simply ignored.
   *
   * Notice the default implementation is `connect.forward(connect, uri...)`.
   */
  Future forward(String uri, {HttpRequest request, HttpResponse response});
  /** Includes the given [uri].
   *
   * If [request] or [response] is ignored, this connect's request or response is assumed.
   * If [uri] is null, `connect.uri` is assumed, i.e., includes the same handler.
   *
   * After calling this method, the caller shall write the output stream in `then`, since
   * the request handler for the given URI might handle it asynchronously. For example,
   *
   *     await connect.include(connect, "another");
   *     connect.response.write("<p>More content</p>");
   *     ...
   *
   * * [uri] - the URI to chain. If omitted, it is the same as this connection.
   * It can contain the query string too.
   *
   * ##Difference between [forward] and [include]
   *
   * [forward] and [include] are almost the same, except
   *
   * * The included request handler won't be able to generate any HTTP headers
   * (it is the job of the caller). Any updates to HTTP headers in the included
   * request handler are simply ignored.
   *
   * Notice the default implementation is `connect.include(connect, uri...)`.
   */
  Future include(String uri, {HttpRequest request, HttpResponse response});

  /** The browser information.
   *
   * * See also [Browser](http://api.rikulo.org/commons/latest/rikulo_browser/Browser.html).
   */
  Browser get browser;

  /** The preferred Locale that the client will accept content in,
   * based on the Accept-Language header.
   */
  String get locale;
  /** A readonly list of Locales indicating, in decreasing order starting with
  * the preferred locale, the locales that are acceptable to the client based
  * on the Accept-Language header
  */
  List<String> get locales;

  /** The error detailed information, or null if no error occurs.
   */
  ErrorDetail errorDetail;

  /** A map of application-specific data.
   *
   * Note: the name of the keys can't start with "stream.", which is reserved
   * for internal use.
   */
  Map<String, dynamic> get dataset;
}

///The HTTP connection wrapper. It simplifies the overriding of a connection.
class HttpConnectWrapper implements HttpConnect {
  ///The original HTTP request
  final HttpConnect origin;
 
  HttpConnectWrapper(this.origin);

  @override
  StreamServer get server => origin.server;
  @override
  HttpChannel get channel => origin.channel;
  @override
  HttpRequest get request => origin.request;
  @override
  HttpResponse get response => origin.response;
  @override
  HttpConnect get forwarder => origin.forwarder;
  @override
  HttpConnect get includer => origin.includer;
  @override
  bool get isIncluded => origin.isIncluded;
  @override
  bool get isForwarded => origin.isForwarded;

  @override
  void redirect(String uri, {int status: HttpStatus.movedTemporarily}) {
    origin.redirect(_toCompleteUrl(request, uri), status: status);
  }
  @override
  Future forward(String uri, {HttpRequest request, HttpResponse response})
  => origin.forward(uri, request: request != null ? request: this.request,
    response: response != null ? response: this.response);
  @override
  Future include(String uri, {HttpRequest request, HttpResponse response})
  => origin.include(uri, request: request != null ? request: this.request,
    response: response != null ? response: this.response);

  @override
  Browser get browser => origin.browser;
  @override
  String get locale => origin.locale;
  @override
  List<String> get locales => origin.locales;
  @override
  ErrorDetail get errorDetail => origin.errorDetail;
  @override
  void set errorDetail(ErrorDetail errorDetail) {
    origin.errorDetail = errorDetail;
  }

  @override
  Map<String, dynamic> get dataset => origin.dataset;
}

///The error detailed information.
class ErrorDetail {
  var error;
  var stackTrace;
  ErrorDetail(this.error, this.stackTrace);
}

/** A HTTP status exception.
 */
class HttpStatusException implements HttpException {
  @override
  final String message;
  final int statusCode;
  @override
  final Uri uri;

  HttpStatusException(int this.statusCode, {String message, Uri this.uri})
  : this.message = message ?? "Status $statusCode";

  @override
  String toString() => "HttpStatusException($statusCode: $message)";
}

/// HTTP 400 exception.
class Http400 extends HttpStatusException {
  Http400([String path]): super(400, message: _status2msg(_m400, path));
  Http400.fromUri(Uri uri): super(400, message: _status2msg(_m400, uri.path), uri: uri);
  Http400.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}
/// HTTP 401 exception.
class Http401 extends HttpStatusException {
  Http401([String path]): super(401, message: _status2msg(_m401, path));
  Http401.fromUri(Uri uri): super(401, message: _status2msg(_m401, uri.path), uri: uri);
  Http401.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}
/// HTTP 403 exception.
class Http403 extends HttpStatusException {
  Http403([String path]): super(403, message: _status2msg(_m403, path));
  Http403.fromUri(Uri uri): super(403, message: _status2msg(_m403, uri.path), uri: uri);
  Http403.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}
/// HTTP 404 exception.
class Http404 extends HttpStatusException {
  Http404([String path]): super(404, message: _status2msg(_m404, path));
  Http404.fromUri(Uri uri): super(404, message: _status2msg(_m404, uri.path), uri: uri);
  Http404.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}
/// HTTP 405 exception.
class Http405 extends HttpStatusException {
  Http405([String path]): super(405, message: _status2msg(_m405, path));
  Http405.fromUri(Uri uri): super(405, message: _status2msg(_m405, uri.path), uri: uri);
  Http405.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}
/// HTTP 406 exception.
class Http406 extends HttpStatusException {
  Http406([String path]): super(406, message: _status2msg(_m406, path));
  Http406.fromUri(Uri uri): super(406, message: _status2msg(_m406, uri.path), uri: uri);
  Http406.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}
/// HTTP 408 exception.
class Http408 extends HttpStatusException {
  Http408([String path]): super(408, message: _status2msg(_m408, path));
  Http408.fromUri(Uri uri): super(408, message: _status2msg(_m408, uri.path), uri: uri);
  Http408.fromConnect(HttpConnect connect): this.fromUri(connect.request.uri);
}

/// HTTP 500 exception.
class Http500 extends HttpStatusException {
  Http500([String cause]): super(500, message: _status2msg(_m500, cause));
  Http500.fromUri(Uri uri, [String cause]):
      super(500, message: _status2msg(_m500,
          cause != null ? "${uri.path}: $cause": uri.path), uri: uri);
  Http500.fromConnect(HttpConnect connect, [String cause]):
      this.fromUri(connect.request.uri, cause);
}
/// HTTP 503 exception.
class Http503 extends HttpStatusException {
  Http503([String cause]): super(503, message: _status2msg(_m503, cause));
  Http503.fromUri(Uri uri, [String cause]):
      super(503, message: _status2msg(_m503,
          cause != null ? "${uri.path}: $cause": uri.path), uri: uri);
  Http503.fromConnect(HttpConnect connect, [String cause]):
      this.fromUri(connect.request.uri, cause);
}

const String _m400 = "Bad Request", _m401 = "Unauthorized",
  _m403 = "Forbidden", _m404 = "Not Found",
  _m405 = "Method Not Allowed",
  _m406 = "Not Acceptable", _m408 = "Request Timeout",
  _m500 = "Internal Server Error", _m503 = "Service Unavailable";

String _status2msg(String reason, String cause)
=> cause != null ? "$reason: $cause": reason;
