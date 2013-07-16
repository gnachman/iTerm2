#!/usr/bin/python
# coding=UTF-8
import random
dwc=u"ｏｌｏｒｅ ｍａｇｎａ ａｌｉｑｕａ. Ｕｔ ｅｎｉｍ ａｄ ｍｉｎｉｍ ｖｅｎｉａｍ, ｑｕｉｓ ｎ"
swc="abcdefghijklmnopqrstuvwxyz"
while True:
    ll = int(random.random() * 2000)
    s = ""
    for i in xrange(ll):
        type = int(random.random() * 2)
        if type:
           c = dwc[int(random.random() * len(dwc))]
        else:
           c = swc[int(random.random() * len(swc))]
        s += c
    print s
