import re
from pathlib import Path
p = Path(r"E:/Odyssey_proj/temp_uart_hex.txt")
lines = p.read_text(encoding='utf-8').strip().splitlines()
# decode each hex line to ASCII and extract fields
out = []
pattern = re.compile(r"AC(\d{3})|F:\s*(\d{2})|S(\d{2})|AC(\d{2})")
for l in lines:
    parts = l.strip().split()
    try:
        s = ''.join(chr(int(x,16)) for x in parts)
    except Exception as e:
        s = '<decode error>'
    # extract AC, F, S and any numbers
    ac = None; f = None; s_addr = None
    m_ac = re.search(r'AC(\d+)', s)
    if m_ac: ac = m_ac.group(1)
    m_f = re.search(r'F:\s*(\d+)', s)
    if m_f: f = m_f.group(1)
    m_s = re.search(r'S(\d+)', s)
    if m_s: s_addr = m_s.group(1)
    out.append((s, ac, f, s_addr))
# print decoded
for s,ac,f,s_addr in out:
    print(s)
    print('  -> AC=',ac,' F=',f,' S=',s_addr)

# summary stats
print('\nSummary: total lines=',len(out))
acs = [int(x[1]) for x in out if x[1] is not None]
fs = [int(x[2]) for x in out if x[2] is not None]
ss = [int(x[3]) for x in out if x[3] is not None]
if acs:
    print('AC min/max=',min(acs),max(acs))
if fs:
    print('F min/max=',min(fs),max(fs))
if ss:
    print('S min/max=',min(ss),max(ss))
