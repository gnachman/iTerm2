#!/usr/bin/python2.4
# Converts a file containing a list of hex values into C code representing the
# ranges compactly.
l1 = ""
l2 = ""

# length of the shortest allowed range
threshold=7
def p(a, b):
    global l1
    global l2
    if abs(a-b) < threshold:
      l = min(a,b)
      for i in range(abs(a-b)+1):
        l1 += "%s,\n" % hex(l + i)
    else:
      #      l2 += "{ %s, %s },\n" % (hex(a), hex(b))
      l2 += "(unicode >= %s && unicode <= %s) ||\n" % (hex(a), hex(b))

values = []

# put your filename here:
f = open("ambiguous.txt", "r")
linenum=0
for line in f:
  linenum += 1
  line = line.strip()
  parts = line.split("..")
  if len(parts) > 1:
    p1 = int(parts[0],16)
    p2 = int(parts[1],16)
    for i in range(p2-p1+1):
      n = p1 + i
      assert n >= p1 and n <= p2
      values.append(n)
  else:
    n = int(line, 16)
    values.append(n)

values = list(set(values))
values.sort()

prev = -1
first = None
for i in values:
  if first is None:
    first = i
    prev = i
    continue

  if i != prev + 1:
    p(first, prev)
    first = i
  prev = i

p(first, prev)
# prints single values first
print l1
# then prints ranges
print l2
