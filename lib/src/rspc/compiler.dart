//Copyright (C) 2013 Potix Corporation. All Rights Reserved.
//History: Mon, Jan 14, 2013  4:56:56 PM
// Author: tomyeh
part of stream_rspc;

/**
 * The RSP compiler
 */
class Compiler {
  final String sourceName;
  final String source;
  final OutputStream destination;
  final Encoding encoding;
  final bool verbose;
  //the closure's name, args
  String _name, _args, _desc, _contentType;
  final List<_TagContext> _tags = [];
  _TagContext _current;
  //The position of the source
  int _pos, _len;
  //Look-ahead tokens
  final List _lookAhead = [];

  Compiler(String this.source, OutputStream this.destination, {
    String this.sourceName,
    Encoding this.encoding:Encoding.UTF_8,
    bool this.verbose: false});

  void compile() {
    destination.writeString("//Auto-generated by RSP Compiler\n");
    if (sourceName != null)
      destination.writeString("//Source: ${sourceName}\n");

    _init();

    bool pgFound = false, started = false;
    int prevln = 1;
    for (var token; (token = _nextToken()) != null; prevln = _current.line) {
      if (token is String) {
        String text = token;
        if (!started) {
          if (text.trim().isEmpty)
            continue; //skip it
          started = true;
          _start(prevln); //use previous line number since it could be multiple lines
        }
        _writeText(text, prevln);
      } else if (token is _Expr) {
        if (!started) {
          started = true;
          _start();
        }
        _writeExpr();
      } else if (token is PageTag) {
        if (pgFound)
          error("Only one page tag is allowed");
        if (started)
          error("The page tag must be in front of any non-empty content");
        pgFound = true;

        push(token);
        token.begin(_current, _tagData());
        token.end(_current);
        pop();
      } else if (token is DartTag) {
        push(token);
        token.begin(_current, _dartData());
        token.end(_current);
        pop();
      } else if (token is Tag) {
        if (!started) {
          started = true;
          _start();
        }
        push(token);
        token.begin(_current, _tagData());
        if (!token.hasClosing) {
          token.end(_current);
          pop();
        }
      } else if (token is _Ending) {
        final _Ending ending = token;
        if (_current.tag.name != ending.name)
          error("Unexpected [/${ending.name}] (no beginning tag found)");
        _current.tag.end(_current);
        pop();
      } else {
        error("Unknown token, $token");
      }
    }

    if (started)
      _writeln("}");
  }
  void _init() {
    _lookAhead.clear();
    _tags.clear();
    _tags.add(_current = new _TagContext(null, 1, null, destination, "", this));
    _name = _args = _desc = _contentType = null;
    _pos = 0;
    _len = source.length;
  }
  void _start([int line]) {
    if (line == null) line = _current.line;
    if (_name == null) {
      if (sourceName == null || sourceName.isEmpty)
        error("The page tag with the name attribute is required", line);

      final i = sourceName.lastIndexOf('/') + 1,
        j = sourceName.indexOf('.', i);
      _name = StringUtil.camelize(
        j >= 0 ? sourceName.substring(i, j): sourceName.substring(i));
    }

    if (_desc == null)
      _desc = "Template, $_name, for rendering the view.";

    if (_contentType == null && sourceName != null) {
      final i = sourceName.lastIndexOf('.');
      if (i >= 0) {
        final ct = contentTypes[sourceName.substring(i + 1)];
        if (ct != null)
          _contentType = ct.toString();
      }
    }

    final pre = _current.indent();
    _write("\n/** $_desc */\nvoid $_name(HttpConnect connect");
    if (_args != null)
      _write(", {$_args}");
    _writeln(") { //$line\n"
      "${pre}final request = connect.request, response = connect.response,\n"
      "${pre}  output = response.outputStream;\n"
      "${pre}var _ep_;");

    if (_contentType != null)
      _writeln('${pre}response.headers.contentType = new ContentType.fromString("${_contentType}");');
  }

  /// Sets the page information.
  void setPage(String name, String description, String args, String contentType) {
    _name = name;
    _desc = description;
    _args = args;
    _contentType = contentType;
  }

  //Tokenizer//
  _nextToken() {
    if (!_lookAhead.isEmpty)
      return _lookAhead.removeLast();

    final sb = new StringBuffer();
    final token = _specialToken(sb);
    if (token is _Ending)
      _skipFollowingSpaces();
    if (sb.isEmpty)
      return token;

    if (token != null)
      _lookAhead.add(token);
    return _rmSpacesBeforeTag(sb.toString(), token);
  }
  _specialToken(StringBuffer sb) {
    while (_pos < _len) {
      final cc = source[_pos];
      if (cc == '[') {
        final j = _pos + 1;
        if (j < _len) {
          final c2 = source[j];
          if (c2 == '*') { //comment
            _pos = _skipUntil("*]", j + 1) + 2;
            continue;
          } else if (c2 == '=') { //exprssion
            _pos = j + 1;
            return new _Expr();
          } else if (c2 == '/') { //ending tag
            int k = j + 1;
            if (k < _len) {
              final c3 = source[k];
              if (StringUtil.isChar(c3, lower:true)) {
                int m = _skipId(k);
                final tagnm = source.substring(k, m);
                final tag = tags[tagnm];
                if (tag != null && m < _len && source[m] == ']') { //tag found
                  if (!tag.hasClosing)
                    error("[/$tagnm] not allowed. It doesn't need the ending tag.");
                  _pos = m + 1;
                  return new _Ending(tagnm);
                }
              }
            }
          } else if (StringUtil.isChar(c2, lower:true)) { //beginning tag
            int k = _skipId(j);
            final tag = tags[source.substring(j, k)];
            if (tag != null) { //tag found
              _pos = k;
              return tag;
            }
            //fall through
          }
        }
      } else if (cc == '\\') {
        final j = _pos + 1;
        if (j < _len && source[j] == '[') {
          sb.add('['); //\[ => [
          _pos += 2;
          continue;
        }
      } else if (cc == '\n') {
        _current.line++;
      }
      sb.add(cc);
      ++_pos;
    } //for each cc
    return null;
  }
  ///(Optional but for better output) Skips the following whitespaces untile linefeed
  void _skipFollowingSpaces() {
    for (int i = _pos; i < _len; ++i) {
      final cc = source[i];
      if (cc == '\n') {
        ++_current.line;
        _pos = i + 1; //skip white spaces until and including linefeed
        return;
      }
      if (cc != ' ' && cc != '\t')
        break; //don't skip anything
    }
  }
  ///(Optional but for better output) Removes the whitspaces before the given token,
  ///if it is a tag. Notice: [text] is in front of [token]
  String _rmSpacesBeforeTag(String text, token) {
    if (token is Tag || token is _Ending) {
      for (int i = text.length; --i >= 0;) {
        final cc = text[i];
        if (cc == '\n')
          return text.substring(0, i + 1); //remove tailing spaces (excluding \n)
        if (cc != ' ' && cc != '\t')
          break; //don't skip anything
      }
    }
    return text;
  }
  int _skipUntil(String until, int from, {bool quotmark: false}) {
    final line = _current.line;
    final nUtil = until.length;
    String sep, first = until[0];
    for (; from < _len; ++from) {
      final cc = source[from];
      if (cc == '\n') {
        _current.line++;
      } else if (sep == null) {
        if (quotmark && (cc == '"' || cc == "'")) {
          sep = cc;
        } else if (cc == first) {
          if (from + nUtil > _len)
            break;
          for (int n = nUtil;;) {
            if (--n < 1) //matched
              return from;

            if (source[from + n] != until[n])
              break;
          }
        }
      } else if (cc == sep) {
        sep = null;
      } else if (cc == '\\' && from + 1 < _len) {
        if (source[++from] == '\n')
          _current.line++;
      }
    }
    error("Expect '$until'", line);
  }
  int _skipId(int from) {
    for (; from < _len; ++from) {
      final cc = source[from];
      if (!StringUtil.isChar(cc, lower:true, upper:true))
        break;
    }
    return from;
  }
  String _tagData({skipFollowingSpaces: true}) {
    int k = _skipUntil("]", _pos, quotmark: true);
    final data = source.substring(_pos, k).trim();
    _pos = k + 1;
    if (skipFollowingSpaces)
      _skipFollowingSpaces();
    return data;
  }
  String _dartData() {
    String data = _tagData();
    if (!data.isEmpty)
      warning("The dart tag has no attribute");
    int k = _skipUntil("[/dart]", _pos);
    data = source.substring(_pos, k).trim();
    _pos = k + 7;
    return data;
  }

  //Utilities//
  void _writeText(String text, [int line]) {
    if (line == null) line = _current.line;
    final pre = _current.pre;
    int i = 0, j;
    while ((j = text.indexOf('"""', i)) >= 0) {
      if (line != null) {
        _writeln("\n$pre//#$line");
        line = null;
      }
      _writeln('$pre${_outTripleQuot(text.substring(i, j))}\n'
        '${pre}output.writeString(\'"""\');');
      i = j + 3;
    }
    if (i == 0) {
      _write('\n$pre${_outTripleQuot(text)}');
      if (line != null) _writeln(" //#$line");
    } else {
      _writeln('$pre${_outTripleQuot(text.substring(i))}');
    }
  }
  String _outTripleQuot(String text) {
    final cc = text.indexOf('\n') >= 0 ? '\n': '';
      //Optional but for more compact output
    return 'output.writeString("""$cc$text""");';
  }

  void _writeExpr() {
    final line = _current.line; //_tagData might have multiple lines
    final expr = _tagData(skipFollowingSpaces: false); //no skip space for expression
    if (!expr.isEmpty) {
      final pre = _current.pre;
      _writeln('\n${pre}_ep_ = $expr; //#${line}\n'
        '${pre}if (_ep_ != null) output.writeString(_ep_);');
    }
  }

  void _write(String str) {
    _current.write(str);
  }
  void _writeln([String str]) {
    if (?str) _current.writeln(str);
    else _current.writeln();
  }

  String _toComment(String text) {
    text = text.replaceAll("\n", "\\n");
    return text.length > 30 ? "${text.substring(0, 27)}...": text;
  }
  ///Throws an enexception (and stops execution).
  void error(String message, [int line]) {
    throw new SyntaxException(sourceName, line != null ? line: _current.line, message);
  }
  ///Display an warning.
  void warning(String message, [int line]) {
    print("$sourceName:${line != null ? line: _current.line}: Warning! $message");
  }

  void push(Tag tag) {
    _tags.add(
      _current = new _TagContext.child(_current, tag, _current.line));
  }
  void pop() {
    final prev = _tags.removeLast();
    _current = _tags.last;
    _current.line = prev.line;
  }
}

///Syntax error.
class SyntaxException implements Exception {
  String _msg;
  ///The source name
  final String sourceName;
  ///The line number
  final int line;
  SyntaxException(String this.sourceName, int this.line, String message) {
    _msg = "$sourceName:$line: $message";
  }
  String get message => _msg;
}

class _TagContext extends TagContext {
  ///The tag
  Tag tag;
  ///The line number
  int line;

  _TagContext(Tag this.tag, int this.line, Tag parent, OutputStream output, String pre,
    Compiler compiler)
    : super(parent, output, pre, compiler);
  _TagContext.child(_TagContext prev, Tag this.tag, int this.line)
    : super(prev.tag, prev.output, prev.pre, prev.compiler);
}
class _Expr {
}
class _Ending {
  final String name;
  _Ending(this.name);
}
