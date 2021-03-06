//Copyright (C) 2013 Potix Corporation. All Rights Reserved.
//History: Mon, Jan 14, 2013  4:56:56 PM
// Author: tomyeh
part of stream_rspc;

/**
 * The RSP compiler
 */
class Compiler {
  final String source;
  final String? sourceName;
  final IOSink destination;
  final String? destinationName;
  final Encoding encoding;
  final bool verbose;
  final bool lineNumber;
  //the closure's partOf, import, name, args...
  String? _partOf, _parts, _import, _name, _args, _desc, _contentType, _dart;
  final List<String>? _defImports;
  final List<_TagContext> _tagCtxs = [];
  late _TagContext _current;
  //The position, length and _line of the source
  int _pos = 0;
  int _len = 1;
  int _line = 1;
  //Look-ahead tokens
  final List _lookAhead = [];
  final List<_QuedTag> _headers = []; //the queued headers
  String? _lastModified, _etag;
  int _nextVar = 0; //used to implement TagContext.nextVar()

  Compiler(String source, this.destination, {
      this.sourceName, this.destinationName, this.encoding: utf8,
      this.verbose: false, this.lineNumber: false, List<String>? imports}):
      this.source = source.replaceAll("\r\n", "\n"),
      this._defImports = imports {
        //to Unix format since _write assumes it
    _tagCtxs.add(_current = new _TagContext.root(this, destination));
    _len = this.source.length;
  }

  ///Compiles the given source into Dart code. Notice: it can be called only once.
  ///To compile the second time, you have to instantiate another [Compiler].
  void compile() {
    _writeln("//Auto-generated by RSP Compiler");
    if (sourceName != null)
      _writeln("//Source: ${_shorten(sourceName!, destinationName)}");

    bool pgFound = false, started = false, written = false;
    int prevln = 1;
    for (var token; (token = _nextToken()) != null; prevln = _line) {
      if (_current.args != null && token is! VarTag && token is! _Closing
      && (token is! String || !token.trim().isEmpty))
        _error("Only the var tag is allowed inside the ${_current.tag!.name} tag, not $token");

      if (token is PageTag) {
        if (pgFound)
          _error("Only one page tag is allowed", _line);
        if (started)
          _error("The page tag must be in front of any non-whitespace content and tags", _line);
        pgFound = true;

        push(token);
        token.begin(_current, _tagData());
        token.end(_current);
        pop();
      } else if (token is String) {
        String text = token;
        if (!written) {
          if (text.trim().isEmpty)
            continue; //skip it
          written = true;
        }
        if (!started) {
          started = true;
          _start(prevln); //use previous line number since it could be multiple lines
        }
        outText(_current, text, prevln);
      } else {
        if (!started) {
          if (token is Tag && token.name == "header") {
            assert(!token.hasClosing);
            final int line = _line;
            _headers.add(new _QuedTag(token, _tagData(tag: token), line));
            continue;
          }

          started = true;
          _start();
        }

        if (token is _Expr) {
          written = true;
          _outExpr();
        } else if (token is DartTag) {
          push(token);
          token.begin(_current, _dartData());
          token.end(_current);
          pop();
        } else if (token is Tag) {
          if (!written)
            written = token.hasContent;

          push(token);
          token.begin(_current, _tagData(tag: token));
          if (!token.hasClosing) {
            token.end(_current);
            pop();
          }
        } else if (token is _Closing) {
          final _Closing closing = token;
          String? tagnm;
          if (_current.tag == null || (tagnm = _current.tag?.name) != closing.name) {
            String msg = "Unexpected [/${closing.name}]";
            if (tagnm != null)
              msg += "; expect [/$tagnm]";
            _error(msg, _line);
          }
          _current.tag?.end(_current);
          pop();
        } else {
          _error("Unknown token, $token", _line);
        }
      }
    }

    if (started) {
      if (_tagCtxs.length > 1) {
        final sb = new StringBuffer();
        for (int i = _tagCtxs.length; --i >= 1;) {
          if (!sb.isEmpty) sb.write(', ');
          sb..write(_tagCtxs[i].tag)..write(' at line ')..write(_tagCtxs[i].line);
        }
        _error("Unclosed tag(s): $sb");
      }
      _writeln("\n  return null;\n}");
    }
  }
  void _start([int? line]) {
    if (line == null) line = _line;
    if (_name == null) {
      final sourceName = this.sourceName;
      if (sourceName == null || sourceName.isEmpty)
        _error("The page tag with the name attribute is required", line);

      var name = Path.basename(sourceName!);
      int i = name.indexOf('.');
      name = StringUtil.camelize(i < 0 ? name: name.substring(0, i));
      _name = name;

        //don't use basenameWithoutExtension since there might be multiple '.'
      for (i = name.length; --i >= 0;) { //check if _name is legal
        final cc = name.codeUnitAt(i);
        if (!isValidVarCharCode(cc, i == 0))
          _error("Unable to generate a legal function name from $sourceName. "
            "Please specify the name with the page tag.", line);
      }
    }

    if (verbose) _info("Generate $_name from line $line");

    if (_desc == null)
      _desc = "Template, $_name, for rendering the view.";

    if (_contentType == null && sourceName != null) {
      final i = sourceName!.lastIndexOf('.');
      if (i >= 0) {
        final ctype = getContentType(sourceName!.substring(i + 1));
        if (ctype != null)
          _contentType = ctype.toString();
      }
    }

    final imports = new LinkedHashSet<String>.from(
      const ["dart:async", "dart:io", "package:stream/stream.dart"]);
    if (_defImports != null)
      imports.addAll(_defImports!);
    if (_import != null)
      for (String imp in _import!.split(',')) {
        imp = imp.trim();
        if (!imp.isEmpty)
          imports.add(imp);
      }

    if (_partOf == null || _partOf!.isEmpty) { //independent library
      String lib = Path.basename(sourceName!);
      int i = lib.lastIndexOf('.'); //remove only one extension
      if (i >= 0) lib = lib.substring(0, i);

      final sb = new StringBuffer();
      final len = lib.length;
      for (i = 0; i < len; ++i) {
        final cc = lib.codeUnitAt(i);
        if (isValidVarCharCode(cc, i == 0)) sb.writeCharCode(cc);
        else sb.write('_');
      }
      _writeln("library $sb;\n");

      for (final impt in imports)
        _writeln("import ${_toImport(impt)};");
    } else if (_partOf!.endsWith(".dart")) { //needs to maintain the given dart file
      _writeln("part of ${_mergePartOf(imports)};");
    } else {
      if (_import != null && !_import!.isEmpty)
        _warning("The import attribute is ignored since the part-of attribute is given");
      _writeln("part of $_partOf;");
    }

    if (_parts != null && !_parts!.isEmpty) {
      _writeln();
      for (String pt in _parts!.split(","))
        if (!(pt = pt.trim()).isEmpty)
          _writeln("part '$pt';");
    }

    if (_dart != null && !_dart!.isEmpty) {
      _writeln();
      _write(_dart);
      if (!_dart!.endsWith("\n"))
        _writeln();
    }

    _current.indent();
    _write("\n/** $_desc */\nFuture $_name(HttpConnect connect");
    if (_args != null)
      _write(", {$_args}");
    _write(") async {${_getLineNumberComment(line)}\n"
      "  HttpResponse response = connect.response;\n");

    if (!_headers.isEmpty) {
      for (final _QuedTag qt in _headers) {
        push(qt.tag, qt.line);
        qt.tag
          ..begin(_current, qt.data)
          ..end(_current);
        pop();
      }
      _writeln();
    }

    _write("  if (!Rsp.init(connect, ${toEL(_contentType)}");
    if (_lastModified != null) {
      _write(',\n  lastModified: ');
      if (_lastModified == "compile")
        _write("new DateTime.fromMillisecondsSinceEpoch(${new DateTime.now().millisecondsSinceEpoch})");
      else if (_lastModified == "start")
        _write("connect.channel.startedSince");
      else
        _write("${toEL(_lastModified)}");
    }
    if (_etag != null) {
      _write(',\n  etag: ');
      if (_etag == "true")
        _write('"${_random.nextInt(1000000)}"');
      else
        _write("${toEL(_etag)}");
    }

    _writeln('))\n    return null;'); //end of if(!Rsp.init)
  }

  ///Sets the page information.
  void setPage(String? partOf, String? parts, String? imports,
      String? name, String? description, String? args,
      String? contentType, String? dart, String? lastModified, String? etag,
      [int? line]) {
    _partOf = partOf;
    _noEL(partOf, "the partOf attribute", line);
    _parts = parts;
    _noEL(parts, "the part attribute", line);
    _import = imports;
    _noEL(_import, "the import attribute", line);
    _name = name;
    _noEL(name, "the name attribute", line);
    _desc = description;
    _noEL(description, "the description attribute", line);
    _args = args;
    _noEL(args, "the args attribute", line);
    _dart = dart;
    _noEL(dart, "the dart attribute", line);
    _contentType = contentType;

    _etag = etag;
    if (_etag != null) {
      if (_etag!.isEmpty)
        _etag = null;
    }

    _lastModified = lastModified;
    if (_lastModified != null)
      if (_lastModified!.isEmpty)
        _lastModified = null;
      else if (_lastModified != "compile" && _lastModified != "start"
      && !isEL(_lastModified))
        _error("Unknown lastModified attribute: $lastModified");
  }

  ///Include the given URI.
  void includeUri(String? uri, [Map<String, String?>? args, int? line]) {
    if (verbose) _info("Include $uri", line);

    _write("\n${_current.pre}await connect.include(");
    final emptyArgs = args == null || args.isEmpty;
    if (!emptyArgs)
      _write("Rsp.cat(");
    _write("${toEL(uri, direct: false)}");
    if (!emptyArgs) {
      _catArgs(args);
      _write(')');
    }
    _writeln(");${_getLineNumberComment(line)}");
  }
  ///Include the output of the given renderer
  void include(String? method, [Map<String, String?>? args, int? line]) {
    if (verbose) _info("Include $method", line);

    _write("\n${_current.pre}await $method(new HttpConnect.chain(connect)");
    _outArgs(args);
    _writeln(");${_getLineNumberComment(line)}");
  }

  ///Forward to the given URI.
  void forwardUri(String? uri, [Map<String, String?>? args, int? line]) {
    if (verbose) _info("Forward $uri", line);

    _write("\n${_current.pre}return connect.forward(");
    final emptyArgs = args == null || args.isEmpty;
    if (!emptyArgs)
      _write("Rsp.cat(");
    _write("${toEL(uri, direct: false)}");
    if (!emptyArgs) {
      _catArgs(args);
      _write(')');
    }
    _writeln(");${_getLineNumberComment(line)}");
  }
  //Forward to the given renderer
  void forward(String? method, [Map<String, String?>? args, int? line]) {
    if (verbose) _info("Forward $method", line);

    _write("\n${_current.pre}return ${method}(connect");
    _outArgs(args);
    _writeln(");${_getLineNumberComment(line)}");
  }
  //Concatenates arguments
  void _catArgs(Map<String, String?>? args) {
    if (args != null && !args.isEmpty) {
      _write(", ");
      outMap(_current, args);
    }
  }
  void _outArgs(Map<String, String?>? args) {
    if (args != null)
      for (final arg in args.keys) {
        _write(", ");
        _write(arg);
        _write(": ");
        _write(toEL(args[arg]));
      }
  }

  //Tokenizer//
  _nextToken() {
    if (!_lookAhead.isEmpty)
      return _lookAhead.removeLast();

    final sb = new StringBuffer();
    final token = _specialToken(sb);
    if (token is _Closing) //if Tag, it is handled by _tagData()
      _skipFollowingSpaces();
    String text = sb.toString();
    if (token is Tag || token is _Closing)
      text = _rmTailingSpaces(text);
    if (text.isEmpty)
      return token;
    if (token != null)
      _lookAhead.add(token);
    return text;
  }
  _specialToken(StringBuffer sb) {
    while (_pos < _len) {
      final cc = source.codeUnitAt(_pos);
      if (cc == $lbracket) {
        final j = _pos + 1;
        if (j < _len) {
          final c2 = source.codeUnitAt(j);
          if (c2 == $equal) { //[=exprssion]
            _pos = j + 1;
            return new _Expr();
          } else if (c2 == $colon || c2 == $slash) { //[:beginning-tag] or [/closing-tag]
            int k = j + 1;
            if (k < _len && StringUtil.isCharCode(source.codeUnitAt(k), lower:true)) {
              int m = _skipTagId(k);
              final tagnm = source.substring(k, m);
              final tag = tags[tagnm];
              if (tag != null) {
                if (c2 == $colon) { //beginning of tag
                  _pos = m;
                  return tag;
                } else if (m < _len && source.codeUnitAt(m) == $rbracket) { //ending of tag found
                  if (!tag.hasClosing)
                    _error("[/$tagnm] not allowed. It doesn't need the closing tag.", _line);
                  _pos = m + 1;
                  return new _Closing(tagnm);
                }
              }
            }
            //fall through
          } else if (c2 == $exclamation) { //[!-- comment --]
            if (j + 2 < _len && source.codeUnitAt(j + 1) == $dash
            && source.codeUnitAt(j + 2) == $dash) {
              _pos = _skipUntil("--]", j + 3)! + 3;
              continue;
            }
          }
        }
      } else if (cc == $backslash) { //escape
        final j = _pos + 1;
        if (j < _len && source.codeUnitAt(j) == $lbracket) {
          sb.write('['); //\[ => [
          _pos += 2;
          continue;
        }
      } else if (cc == $lf) {
        _line++;
      }
      sb.writeCharCode(cc);
      ++_pos;
    } //for each cc
    return null;
  }
  ///(Optional but for better output) Skips the following whitespaces untile linefeed
  void _skipFollowingSpaces() {
    for (int i = _pos; i < _len; ++i) {
      final cc = source.codeUnitAt(i);
      if (cc == $lf) {
        ++_line;
        _pos = i + 1; //skip white spaces until and including linefeed
        return;
      }
      if (cc != $space && cc != $tab)
        break; //don't skip anything
    }
  }
  ///(Optional but for better output) Removes the tailing whitspaces
  static String _rmTailingSpaces(String text) {
    for (int i = text.length; --i >= 0;) {
      final cc = text.codeUnitAt(i);
      if (cc == $lf)
        return text.substring(0, i + 1); //remove tailing spaces (excluding linefeed)
      if (cc != $space && cc != $tab)
        return text; //don't skip anything
    }
    return "";
  }
  int? _skipUntil(String until, int from) {
    final line = _line;
    final nUtil = until.length;
    var first = until.codeUnitAt(0);
    for (; from < _len; ++from) {
      final cc = source.codeUnitAt(from);
      if (cc == $lf) {
        _line++;
      } else if (cc == $backslash && from + 1 < _len) { //escape
        if (source.codeUnitAt(++from) == $lf)
          _line++;
      } else {
        if (cc == first) {
          if (from + nUtil > _len)
            break;
          for (int n = nUtil;;) {
            if (--n < 1) //matched
              return from;

            if (source.codeUnitAt(from + n) != until.codeUnitAt(n))
              break; //continue to next character
          }
        }
      }
    }
    _error("Expect '$until'", line);
    return null;
  }
  int _skipTagId(int from) {
    for (; from < _len; ++from) {
      final cc = source.codeUnitAt(from);
      //dash is allowed in a tag name
      if (!StringUtil.isCharCode(cc, lower:true, upper:true) && cc != $dash)
        break;
    }
    return from;
  }
  ///Skip arguments (of a tag)
  int? _skipTagArgs(int from) {
    final line = _line;
    int? sep;
    int nbkt = 0;
    for (; from < _len; ++from) {
      final cc = source.codeUnitAt(from);
      if (cc == $lf) {
        _line++;
      } else if (cc == $backslash && from + 1 < _len) {
        if (source.codeUnitAt(++from) == $lf)
          _line++;
      } else if (sep == null) {
        if (cc == $double_quote || cc == $single_quote) {
          sep = cc;
        } else if (cc == $slash && from + 1 < _len
        && source.codeUnitAt(from + 1) == $rbracket) {
          return from;
        } else if (nbkt == 0 && cc == $rbracket) {
          return from;
        } else if (cc == $lbracket) {
          ++nbkt;
        } else if (cc == $rbracket) {
          --nbkt;
        }
      } else if (cc == sep) {
        sep = null;
      }
    }
    _error("Expect ']'", line);
    return null;
  }
  ///Note: [tag] is required if `tag.hasClosing` is 
  String _tagData({Tag? tag, bool skipFollowingSpaces: true}) {
    int k = _skipTagArgs(_pos)!;
    final data = source.substring(_pos, k).trim();
    _pos = k + 1;
    if (source.codeUnitAt(k) == $slash) {
      if (tag != null && tag.hasClosing)
        _lookAhead.add(new _Closing(tag.name));
      if (_pos >= _len || source.codeUnitAt(_pos) != $rbracket)
        _error("Expect ']'");
      ++_pos;
    }
    if (skipFollowingSpaces)
      _skipFollowingSpaces();
    return data;
  }
  String _dartData() {
    String data = _tagData(tag: tags["dart"]);
    if (!data.isEmpty)
      _warning("The dart tag has no attribute", _line);

    if (!_lookAhead.isEmpty) { //we have to check if it is [dart/]
      final token = _nextToken();
      if (token is _Closing && token.name == "dart")
        return ""; //[dart/]
      _lookAhead.add(token); //add back
    }

    int k = _skipUntil("[/dart]", _pos)!;
    data = source.substring(_pos, k).trim();
    _pos = k + 7;
    return data;
  }

  //Utilities//
  void _outExpr() {
    final expr = _tagData(skipFollowingSpaces: false);
      //1) '/' is NOT a terminal, 2) no skip space for expression
    if (!expr.isEmpty)
      _writeln('\n${_current.pre}response.write(Rsp.nnx($expr));${_getLineNumberComment()}\n');
      //it doesn't push, so we have to use _line instead of _current.line
      //_tagData might have multiple lines
  }

  ///merge partOf, and returns the library name
  String? _mergePartOf(Set<String> imports) {
    if (destinationName == null)
      _error("The partOf attribute refers to a dart file is allowed only if destination is specified");

    String libpath = _partOf!;
    var mypath = destinationName!;
    if (!Path.isAbsolute(libpath))
      libpath = Path.join(Path.dirname(mypath), libpath);
    mypath = Path.relative(mypath, from: Path.dirname(libpath));

    File libfile = new File(libpath);
    if (!libfile.existsSync()) {
      String libnm = Path.basename(libpath);
      libnm = libnm.substring(0, libnm.indexOf('.'));
        //filename must end with .dart (but it might have other extension ahead)

      final buf = new StringBuffer()
        ..write("library ")..write(libnm)..writeln(";\n");
      for (final impt in imports)
        buf.writeln("import ${_toImport(impt)};");
      buf..write("\npart '")..write(mypath)..writeln("';");
      libfile.writeAsStringSync(buf.toString(), encoding: encoding);
      return libnm;
    }

    //parse libfile (TODO: use a better algorithm to parse rather than readAsStringSync/writeAsStringSync)
    String? libnm;
    bool comment0 = false, comment1 = false;
    final libimports = new Set<String>(), libparts = new Set<String>();
    final data = libfile.readAsStringSync();
    int len = data.length;
    int? importPos;
    var partPos = len;
    for (int i = 0, j; i < len; ++i) {
      final cc = data.codeUnitAt(i);
      if (comment0) { //look for \n
        if (cc == $lf)
          comment0 = false;
      } else if (comment1) {
        if (cc == $asterisk && i + 1 < len && data.codeUnitAt(i + 1) == $slash) {
          ++i;
          comment1 = false;
        }
      } else if (cc == $slash) {
        if (i + 1 < len) {
          final c2 = data.codeUnitAt(i + 1);
          comment0 = c2 == $slash;
          comment1 = c2 == $asterisk;
          if (comment0 || comment1)
            ++i;
        }
      } else if ((j = _startsWith(data, i, "library")) >= 0) {
        i = _skipWhitespace(data, j);
        j = data.indexOf(';', i);
        if (j < 0)
          _error("Illegal library syntax found in $libfile");
        libnm = data.substring(i, j).trim();
        i = j;
      } else if ((j = _startsWith(data, i, "import")) >= 0) {
        i = _skipWhitespace(data, j);
        j = data.indexOf(';', i);
        if (j < 0)
          _error("Illegal import syntax found in $libfile");
        libimports.add(data.substring(i, j).trim().replaceAll('"', "'").replaceAll('\\', '/'));
        i = j;
      } else if ((j = _startsWith(data, i, "part")) >= 0) {
        if (importPos == null)
          importPos = i;
        i = _skipWhitespace(data, j);
        j = data.indexOf(';', i);
        if (j < 0)
          _error("Illegal part syntax found in $libfile");
        libparts.add(data.substring(i, j).trim().replaceAll('"', "'").replaceAll('\\', '/'));
        i = j;
      } else if (!$whitespaces.contains(cc)) {
        partPos = i;
        break;
      }
    }

    if (libnm == null)
      _error("The library directive not found in $libfile");

    List<String> importToAdd = [];
    for (final impt in imports) {
      final s = _toImport(impt);
      if (!libimports.contains(s))
        importToAdd.add(s);
    }

    String? mynm = "'$mypath'";
    if (libparts.contains(mynm))
      mynm = null; //no need to add

    if (!importToAdd.isEmpty || mynm != null) {
      final srcnmDisplay = _shorten(
        sourceName != null ? sourceName!: mypath.toString(), destinationName);
      final buf = new StringBuffer();

      if (importToAdd.isEmpty) {
        buf.write(data.substring(0, partPos));
      } else {
        if (importPos == null)
          importPos = partPos;
        buf.write(data.substring(0, importPos));
        for (final impt in importToAdd)
          buf..write("import ")..write(impt)..writeln("; //auto-inject from $srcnmDisplay");
        buf..write('\n')..write(data.substring(importPos, partPos));
      }

      if (mynm != null)
        buf..write("part ")..write(mynm)..writeln("; //auto-inject from $srcnmDisplay\n");
      buf.write(data.substring(partPos));

      libfile.writeAsStringSync(buf.toString(), encoding: encoding);
    }
    return libnm;
  }

  ///Generate import xxx;
  String _toImport(String impt) {
    impt = impt.trim();
    for (int i = 0, len = impt.length; i < len; ++i)
      if ($whitespaces.contains(impt.codeUnitAt(i)))
        return "'${impt.substring(0, i)}'${impt.substring(i)}";
    return "'$impt'";
  }

  String _getLineNumberComment([int? line])
  => lineNumber ? ' //#${line??this._line}': '';

  void _write(String? str) {
    _current.write(str);
  }
  void _writeln([String? str]) {
    if (str != null) _current.writeln(str);
    else _current.writeln();
  }

  ///Throws an exception if the value is EL
  void _noEL(String? val, String what, [int? line]) {
    if (val != null && isEL(val))
      _error("Expression not allowed in $what", line);
  }
  ///Throws an exception (and stops execution).
  void _error(String message, [int? line]) {
    if (line == null)
      line = _current.line;
    _writeln("\n>>> Failed at #$line: $message"); //for easy detecting error
    throw new SyntaxError(sourceName, line, message);
  }
  ///Display an warning.
  void _warning(String message, [int? line]) {
    print("$sourceName:${line != null ? line: _current.line}: Warning! $message");
  }
  ///Display a message.
  void _info(String message, [int? line]) {
    print("$sourceName:${line != null ? line: _current.line}: $message");
  }

  void push(Tag tag, [int? line]) {
    _tagCtxs.add(_current =
      new _TagContext.child(_current, tag, line != null ? line: _line));
  }
  void pop() {
    _tagCtxs.removeLast();
    _current = _tagCtxs.last;
  }
}

///Syntax error.
class SyntaxError extends Error {
  late String _msg;
  ///The source name
  final String? sourceName;
  ///The line number
  final int line;

  SyntaxError(this.sourceName, this.line, String message) {
    _msg = "$sourceName:$line: $message";
  }
  String get message => _msg;
}

class _TagContext extends TagContext {
  String _pre;

  ///The line number
  @override
  final int line;

  _TagContext.root(Compiler compiler, IOSink output)
    : _pre = "", line = 1, super(null, null, compiler, output);
  _TagContext.child(_TagContext prev, Tag tag, this.line)
    : _pre = prev._pre, super(prev, tag, prev.compiler, prev.output);

  @override
  String nextVar() => "_${compiler._nextVar++}";
  @override
  String get pre => _pre;
  @override
  String indent() => _pre = "$_pre  ";
  @override
  String unindent() => _pre = _pre.isEmpty ? _pre: _pre.substring(2);

  @override
  void push(value) {
    _stack.add(value);
  }
  @override
  pop() => _stack.removeLast();
  final List _stack = [];

  @override
  void error(String message, [int? line]) {
    compiler._error(message, line);
  }
  @override
  void warning(String message, [int? line]) {
    compiler._warning(message, line);
  }
  @override
  String toString() => "($line: $tag)";
}

class _Expr {
}

class _Closing {
  final String name;
  _Closing(this.name);
}

///Queued tag
class _QuedTag {
  final Tag tag;
  final String data;
  final int line;
  _QuedTag(this.tag, this.data, this.line);
}

int _startsWith(String data, int i, String pattern) {
  for (int len = data.length, pl = pattern.length, j = 0;; ++i, ++j) {
    if (j >= pl)
      return i; //found
    if (i >= len || data.codeUnitAt(i) != pattern.codeUnitAt(j))
      return -1;
  }
}
int _skipWhitespace(String data, int i) {
  for (int len = data.length; i < len && $whitespaces.contains(data.codeUnitAt(i)); ++i)
    ;
  return i;
}
///shorten the path to display
String _shorten(String path, String? reference) {
  try {
    if (reference != null && !reference.isEmpty) {
      if (Path.extension(reference) != "")
        reference = Path.dirname(reference);
      return _unipath(Path.relative(path, from: reference));
    }
  } catch (err) {
  }

  final nm = Path.basename(path);
  return _unipath(nm.isEmpty ? path: nm);
}

String _unipath(String path)
=> Path.separator == '\\' ? path.replaceAll('\\', '/'): path;

final Random _random = new Random();
