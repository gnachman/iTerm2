#!/usr/bin/python
from __future__ import print_function

def PrintTableHeader(fg):
  for num, name in fg:
    print("%-7s " % name, end="")

def Clear():
    print("%c[39;49m " % 27, end="")

def PrintRowLabel(index, bg):
  print("%9s " % bg[index][1], end="")

def PrintCell(fi, bi, fg, bg):
  print("%c[%d;%dm%-9s " % (27, bg[bi][0], fg[fi][0], u"Abc\u2605".encode('utf-8')), end="")

def PrintMargin():
  print("    ", end="")

dfg = [(30, "black"),
       (31, "red"),
       (32, "green"),
       (33, "yellow"),
       (34, "blue"),
       (35, "magenta"),
       (36, "cyan"),
       (37, "white")]

lfg = [(90, "black"),
       (91, "red"),
       (92, "green"),
       (93, "yellow"),
       (94, "blue"),
       (95, "magenta"),
       (96, "cyan"),
       (97, "white") ]

dbg = [(40, "black"),
       (41, "red"),
       (42, "green"),
       (43, "yellow"),
       (44, "blue"),
       (45, "magenta"),
       (46, "cyan"),
       (47, "white") ]

lbg = [(100, "black"),
       (101, "red"),
       (102, "green"),
       (103, "yellow"),
       (104, "blue"),
       (105, "magenta"),
       (106, "cyan"),
       (107, "white") ]

titles = [ "Dark on Dark", "Light on Dark", "Dark on Light", "Light on Light" ]
t = 0
print()
for bg in (dbg, lbg):
  print("%9s %c[1m" % ("", 27), end="")
  for fg in (dfg, lfg):
    print("%25s%-40s" % ("", titles[t]), end="")
    PrintMargin()
    print(" ", end="")
    t += 1
  print("%9s %c[0m" % ("", 27), end="")

  print()
  print("%9s " % "", end="")
  for fg in (dfg, lfg):
    PrintTableHeader(fg)
    PrintMargin()
    print(" ", end="")
  print()

  for y in xrange(8):
    PrintRowLabel(y, bg)

    for fg in (dfg, lfg):
      for x in xrange(8):
        PrintCell(x, y, fg, bg)
      Clear()
      PrintMargin()

    print("")
  print("")
  print()

