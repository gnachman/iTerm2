#!/usr/local/bin/python

from random import randint

def f(n):
  a = [0] * 64
  for i in xrange(n):
    a[randint(0, 63)] = 1
  return sum(a)

N = 100
for i in xrange(1024):
  s = 0
  smallest = None
  for j in xrange(N):
    x = f(i)
    s += x
    if smallest is None or x < smallest:
      smallest = x
  print "With %d unique values, num bits averages %d; min is %d" % (i, s / N, x)

