#!/bin/python

import collections
import queue
import sys

data = sys.stdin.read()
chcount = len(data)
huffmanPq = queue.PriorityQueue()
parent = dict()
children = dict()
counter = collections.Counter(data)
for ch, count in counter.items():
	name = 'c' + str(ord(ch))
	huffmanPq.put((count, name))
internal = 0
codes = dict()
while True:
	first = huffmanPq.get()
	if first[0] == chcount:
		top = first[1]
		break
	second = huffmanPq.get()
	name = 'i' + str(internal)
	parent[first[1]] = name
	parent[second[1]] = name
	children[name] = (first[1], second[1])
	huffmanPq.put((first[0] + second[0], name))
	internal = internal + 1
for ch, count in counter.items():
	name = 'c' + str(ord(ch))
	code = []
	ptr = name
	while ptr in parent:
		new_ptr = parent[ptr]
		code.append(children[new_ptr][0] == ptr and '0' or '1')
		ptr = new_ptr
	code.reverse()
	codes[name] = ''.join(code)

codeQ = queue.LifoQueue()
codeQ.put(top)
print('huffman_decode:')
while not codeQ.empty():
	item = codeQ.get()
	if item in children:
		if item == top:
			print(f'\ttest r1, r1')
		else:
			print(f'.{item}:')
			print(f'\tshl r1, 1')
		print(f'\tjs .{children[item][1]}')
		codeQ.put(children[item][1])
		codeQ.put(children[item][0])
	else:
		print(f'.{item}:')
		length = len(codes[item])
		assert(length <= 15)
		ch = item[1 : ]
		print(f'\tmov r2, {{ {length} 8 << {ch} | }}')
		print(f'\tret')

encoded = ''.join([ codes['c' + str(ord(ch))] for ch in data ])
values = []
bits = 32
for i in range(0, len(encoded), bits):
	block = encoded[i : i + bits]
	block = block + ''.join([ '1' ] * (bits - len(block)))
	value = int(block, 2)
	assert(value & 0x3FFFFFFF != 0)
	values.append(value)
row_size = 4
values.append(0xFFFFFFFF)
print()
print('data:')
for i in range(0, len(values), row_size):
	row = [ f'0x{value:08X}' for value in values[i : i + row_size] ]
	print(f'\tdw {', '.join(row)}')
print('.length:')
print(f'\tdw {chcount}')
