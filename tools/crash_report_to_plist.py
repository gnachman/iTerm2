# Convert a UKCrashReport into a usable plist file.
# Uses the rather spiffy Python Lex-Yacc tool available here:
# http://www.dabeaz.com/ply/
# and checked in under ply/

import ply.lex as lex
import ply.yacc as yacc
import datetime
import time

tokens = (
    'QUOTED_WORD', 'WORD','EQUALS', 'BEGIN_BLOCK','END_BLOCK', 'REAL', 'SEMI', "BEGIN_ARRAY", "END_ARRAY", "COMMA", "BEGIN_TUPLE", "END_TUPLE", "DATE", "TIME"
    )

# Tokens

t_WORD    = r'[a-zA-Z0-9_.\-+]+'
t_QUOTED_WORD = r'"[^"]*"'
t_EQUALS  = r'='
t_BEGIN_BLOCK = r'{'
t_END_BLOCK  = r'}'
t_REAL = r'[0-9]*\.[0-9][0-9]*(e[+\-][0-9]+)'
t_SEMI = r';'
t_BEGIN_ARRAY = r'\('
t_END_ARRAY = r'\)'
t_COMMA = r','
t_BEGIN_TUPLE = "<"
t_END_TUPLE = ">"
t_DATE = r'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
t_TIME = r'[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'

# Ignored characters
t_ignore = " \t"

def t_newline(t):
    r'\n+'
    t.lexer.lineno += t.value.count("\n")

def t_error(t):
    print("Illegal character '%s'" % t.value[0])
    t.lexer.skip(1)

# Build the lexer
import ply.lex as lex
lex.lex()

# Parsing rules

precedence = (
    )

# dictionary of names
names = { }

def p_plist(t):
    'plist : block_value'
    t[0] = t[1]
    print t[0]

def p_dict_value(t):
    '''dict_value : dict_value key EQUALS value SEMI
                  |'''
    if len(t) == 1:
      t[0] = ""
    else:
      t[0] = "%s<key>%s</key>\n%s\n" % (t[1], t[2], t[4])

def p_key(t):
    '''key : WORD
           | quoted_phrase'''
    t[0] = t[1]

def p_quoted_phrase(t):
    'quoted_phrase : QUOTED_WORD'
    t[0] = t[1][1:-1]

def p_value(t):
    '''value : block_value
             | array_value
             | tuple_value
             | real_value
             | ambiguous_value
             | date_value
             | string_value'''
    t[0] = t[1]

def p_tuple_value(t):
   'tuple_value : BEGIN_TUPLE tuple_entries END_TUPLE'
   t[0] = "<array>%s</array>" % t[2]

def p_tuple_entries(t):
   '''tuple_entries : value tuple_entries
                    | value'''
   if len(t) == 2:
     t[0] = t[1]
   else:
     t[0] = "%s\n%s" % (t[1], t[2])

def p_array_value(t):
   'array_value : BEGIN_ARRAY array_entries END_ARRAY'
   t[0] = "<array>%s</array>" % t[2]

def p_array_entries(t):
   '''array_entries : value COMMA array_entries
                    | value
                    |'''
   if len(t) == 1:
     t[0] = ""
   elif len(t) == 2:
     t[0] = t[1]
   else:
     t[0] = "%s\n%s" % (t[1], t[3])

def p_ambiguous_value(t):
   'ambiguous_value : WORD'
   try:
     i = int(t[1])
     t[0] = "<integer>%s</integer>" % i
   except ValueError:
     t[0] = "<string>%s</string>" % t[1]

def RejiggerDate(d):
  parts = d.split(" ")
  tz = parts[-1]
  nozonedate = " ".join(parts[:-1])
  st = time.strptime(nozonedate, "%Y-%m-%d %H:%M:%S")
  dt = datetime.datetime(*st[:6])
  i = int(tz)
  hdiff = i / 100
  mdiff = abs(i) % 100
  if i < 0:
     mdiff *= -1
  sdiff = hdiff * 3600 + mdiff * 60
  dt -= datetime.timedelta(0, sdiff)
  return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def p_date_value(t):
    'date_value : DATE TIME WORD'
    t[0] = "<date>%s</date>" % RejiggerDate("%s %s %s" % (t[1], t[2], t[3]))

def p_string_value(t):
    'string_value : quoted_phrase'
    t[0] = "<string>%s</string>" % t[1]

def p_real_value(t):
   'real_value : REAL'
   t[0] = "<real>%s</real>" % t[1]

def p_block_value(t):
    'block_value : BEGIN_BLOCK dict_value END_BLOCK'
    t[0] = "<dict>\n%s</dict>" % t[2]

def p_error(t):
    print("Syntax error at ", t)

import ply.yacc as yacc
yacc.yacc()

s = None
while 1:
    try:
        line = raw_input()
        if s is None:
          line.strip()
          if line == "Preferences:":
            s = ""
        else:
          s += line
    except EOFError:
        break
print '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">'''

yacc.parse(s)
print "</plist>"
