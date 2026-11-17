#!/usr/bin/env python3
"""Generate a testbench comparing an RTL top module against the netlist
recovered from its bitstream by icebox_vlog (scalar, escaped port names).
usage: roundtrip_tb.py <recovered.v> <recovered_module> <rtl_top> <clk1,clk2,...> <n_steps> > tb.v
Inputs and bidirectional pins are taken from the recovered module header."""
import re, sys
rec, recmod, rtltop, clks, steps = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(','), int(sys.argv[5])
src = open(rec).read()
hdr = src[src.index('module ' + recmod):]
hdr = hdr[:hdr.index(';')]
ports = re.findall(r'(input|output)\s+(\\\S+ |\w+)', hdr)
ins = [n.strip() for d, n in ports if d == 'input']
outs = [n.strip() for d, n in ports if d == 'output']
def base(n): return n.lstrip('\\')
def vec(n):
    m = re.match(r'\\?(\w+)\[(\d+)\]', n)
    return (m.group(1), int(m.group(2))) if m else (n, None)
buses = {}
for n in ins + outs:
    b, i = vec(n)
    buses.setdefault(b, []).append(i)
print('`timescale 1ns/1ps\nmodule tb;')
for b, idx in buses.items():
    isin = any(vec(n)[0] == b for n in ins)
    w = '' if idx == [None] else '[%d:0] ' % max(idx)
    if isin:
        print('  reg %s%s = 0;' % (w, b))
    else:
        print('  wire %s%s_a, %s_b;' % (w, b, b))
def conn(n, suffix):
    b, i = vec(n)
    isin = n in ins
    sig = b if isin else b + suffix
    return '.%s (%s%s)' % (n if not n.startswith('\\') else n + ' ', sig, '' if i is None else '[%d]' % i)
rtl_conns = []
for b in buses:
    isin = any(vec(n)[0] == b for n in ins)
    rtl_conns.append('.%s(%s)' % (b, b if isin else b + '_a'))
print('  %s rtl (%s);' % (rtltop, ', '.join(rtl_conns)))
print('  %s rec (%s);' % (recmod, ', '.join(conn(n, '_b') for n in ins + outs)))
data_ins = [(b, idx) for b, idx in buses.items() if any(vec(n)[0] == b for n in ins) and b not in clks]
print('  integer i, errors = 0, checked = 0, seed = 1;')
print('  task check; begin')
for b, idx in buses.items():
    if any(vec(n)[0] == b for n in ins): continue
    w = 1 if idx == [None] else max(idx) + 1
    for k in range(w):
        s = '' if idx == [None] else '[%d]' % k
        if idx != [None] and k not in idx: continue
        print("    if (%s_a%s !== 1'bx) begin checked = checked + 1; if (%s_a%s !== %s_b%s) begin errors = errors + 1; if (errors < 20) $display(\"MISMATCH t=%%0t %s%s rtl=%%b rec=%%b\", $time, %s_a%s, %s_b%s); end end" % (b, s, b, s, b, s, b, s, b, s, b, s))
print('  end endtask')
print('  initial begin')
print('    #5;')
print('    for (i = 0; i < %d; i = i + 1) begin' % steps)
for b, idx in data_ins:
    print('      if (($random(seed) & 7) == 0) %s = $random(seed);' % b)
print('      #2;')
for c in clks:
    print('      if (($random(seed) & %d) == 0) begin %s = ~%s; #2; check; end' % (0 if c == clks[0] else 3, c, c))
print('      #1; check;')
print('    end')
print('    $display("checked=%0d errors=%0d", checked, errors);')
print('    $finish;')
print('  end\nendmodule')
