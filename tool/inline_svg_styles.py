import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
block = re.search(r'<style[^>]*>(.*?)</style>', s, re.S)
rules = {m.group(1): dict(d.split(':', 1) for d in m.group(2).strip(';').split(';'))
         for m in re.finditer(r'\.(\w+)\{([^}]*)\}', block.group(1))}
s = s[:block.start()] + s[block.end():]
def repl(m):
    tag, attrs = m.group(1), m.group(2)
    cls = re.search(r'\sclass="([^"]+)"', attrs)
    if not cls: return m.group(0)
    decls = {}
    for c in cls.group(1).split(): decls.update(rules[c])
    attrs = attrs.replace(cls.group(0), '')
    extra = ''.join(f' {k.strip()}="{v.strip()}"' for k, v in decls.items()
                    if not re.search(rf'\s{re.escape(k.strip())}=', attrs))
    return f'<{tag}{extra}{attrs}'
s = re.sub(r'<(\w+)((?:\s[^<>]*?)?)(?=/?>)', repl, s)
assert 'class=' not in s
open(dst, 'w').write(s)
