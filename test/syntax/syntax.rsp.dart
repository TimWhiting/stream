//Auto-generated by RSP Compiler
//Source: syntax.rsp.html
library syntax_rsp;

import 'dart:async';
import 'dart:io';
import 'package:stream/stream.dart';
import 'dart:collection' show LinkedHashMap;

var someExternal = 123;

/** Template, syntax, for rendering the view. */
Future syntax(HttpConnect connect, {foo, bool c:false}) async {
  HttpResponse response = connect.response;

  response.headers..add("age", "129")
    ..add("accept-ranges", foo.acceptRanges);

  response.headers..add("Cache-Control", "no-cache");

  if (!Rsp.init(connect, foo.contentType as String))
    return null;

  response.write("""<!DOCTYPE html>
<html>
  <head>
    <title>""");

  response.write(Rsp.nnx("$foo.name [${foo.title}]"));


  response.write("""</title>
  </head>
  <body>
    <p>This is a test with ""\" and \\ and ""\\".
    <p>Another expresion: \"""");

  response.write(Rsp.nnx(foo.description));


  response.write(""""
    <p>An empty expression: """);

  response.write("""

    <p>This is not a tag: [:foo ], [:another and [/none].
    <ul>
""");

  for (var user in foo.friends) {

    response.write("""      <li>""");

    response.write(Rsp.nnx(user.name));


    response.write("""

""");

    if (user.isCustomer as bool) {

      response.write("""      <i>!important!</i>
""");
    } //if

    while (user.hasMore() as bool) {

      response.write("""        """);

      response.write(Rsp.nnx(user.showMore()));


      response.write("""

""");
    } //while

    response.write("""      </li>
""");
  } //for

  response.write("""    </ul>

""");

  for (var fruit in ["apple", "orange"]) {

    response.write("""      """);

    response.write(Rsp.nnx(fruit));


    response.write("""

""");
  } //for

  response.write("""

""");

  if (foo.isCustomer as bool) {

    response.write("""      *Custmer*
""");

    await connect.include("/in-if");

  } else if (c) {

    return connect.forward("/x/y/z");

  } else if (foo.isEmployee as bool) {

    response.write("""      *Employee*
""");

    return syntax(connect, c: true, foo: "abc");

  } else {

    response.write("""      *Unknown* [/if] 
""");
  } //if

  response.write("""

""");

  final _whatever_ = new StringBuffer(), _0 = connect;
  connect = new HttpConnect.stringBuffer(connect, _whatever_); response = connect.response;

  response.write("""    define a variable
""");

  for (var fruit in ["apple", "orange"]) {

    response.write("""        """);

    response.write(Rsp.nnx(fruit));


    response.write("""

""");
  } //for

  connect = _0; response = connect.response;
  final whatever = _whatever_.toString();

  response.write("""

""");

  await connect.include("/abc");

  final _1 = new StringBuffer(), _2 = connect;
  connect = new HttpConnect.stringBuffer(connect, _1); response = connect.response;

  response.write("""      The content for foo
""");

  connect = _2; response = connect.response;

  await syntax(new HttpConnect.chain(connect), c: true, foo: _1.toString());

  response.write("""

""");

  if (foo.isMeaningful as bool) {

    response.write("""      something is meaningful: """);

    response.write(Rsp.nnx(whatever));


    response.write("""

""");

    return connect.forward(Rsp.cat("/foo?abc", {'first': "1st", 'second': foo}));
  } //if

  response.write("""    <script>
    \$("#j\\q");
    </script>
  </body>
</html>
""");

  response..write("<script>")..write("foo1")..write("=")
   ..write(Rsp.json(foo.name.length ~/ 2))..writeln('</script>');
  response..write('<script type="text/plain" id="')
   ..write("foo2")..write('">')
   ..write(Rsp.json(foo.name.length ~/ 2 * "/]".length))..writeln('</script>');

  response.write("""

""");

  response.write("""

""");
new LinkedHashMap();

  response.write("""

""");

  return null;
}
