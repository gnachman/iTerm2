#!/usr/bin/python
# Converts a file containing a list of hex values into C code representing the
# ranges compactly.
print """
struct {
    UTF32Char minVal;
    UTF32Char maxVal;
} ranges[] = {"""

# length of the shortest allowed range
def p(a, b):
  return "{ %s, %s }, " % (hex(a), hex(b))

values = []

# put your filename here:
f = open("CombiningMarks.txt", "r")
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
line = "    "
limit = 92
for i in values:
  if first is None:
    first = i
    prev = i
    continue

  if i != prev + 1:
    s = p(first, prev)
    if len(line + s) > limit:
      print line
      line = "    "
    line += s
    first = i
  prev = i

s = p(first, prev)
if len(line + s) > limit:
  print line
  line = "    "
line += s

print line
print '};'

