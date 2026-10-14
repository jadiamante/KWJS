#!/usr/bin/env python3
# KDE KWJS - proxy local para el navegador Falkon.
# Uso:  python3 kwjs-proxy.py [puerto] [--allow-private]
# Descarga las paginas por vos, quita las cabeceras que impiden mostrarlas dentro de otra pagina
# (X-Frame-Options / Content-Security-Policy) y reescribe los enlaces para que sigas navegando.
# Escucha solo en 127.0.0.1. No guarda cookies. Por defecto no accede a direcciones privadas.
import sys, re, ipaddress, socket, gzip, zlib, urllib.request, urllib.parse, urllib.error, http.server, socketserver

ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
PORT = int(ARGS[0]) if ARGS else 8787
ALLOW_PRIVATE = '--allow-private' in sys.argv
UA = 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0 KDE-KWJS-Falkon'
DROP = {'connection', 'keep-alive', 'transfer-encoding', 'content-encoding', 'content-length', 'content-security-policy',
        'content-security-policy-report-only', 'x-frame-options', 'strict-transport-security', 'report-to', 'nel',
        'cross-origin-opener-policy', 'cross-origin-embedder-policy', 'cross-origin-resource-policy', 'permissions-policy',
        'set-cookie', 'access-control-allow-origin', 'access-control-allow-credentials'}

INJECT = r"""<script>(function(){
var P=location.origin+'/?url=',REAL=%REAL%;
function abs(u){try{return new URL(u,document.baseURI).href}catch(e){return u}}
function prox(u){u=abs(u);return /^https?:/i.test(u)?P+encodeURIComponent(u):u}
function tell(){try{parent.postMessage({kwjs:1,url:REAL,title:document.title},'*')}catch(e){}}
document.addEventListener('click',function(e){var a=e.target.closest&&e.target.closest('a[href]');if(!a||e.defaultPrevented)return;var h=a.getAttribute('href');if(!h||h.charAt(0)==='#'||/^(javascript|mailto|tel|data|blob):/i.test(h))return;e.preventDefault();location.href=prox(h)},true);
document.addEventListener('submit',function(e){var f=e.target;if(!f||f.tagName!=='FORM')return;var m=(f.getAttribute('method')||'get').toLowerCase(),act=abs(f.getAttribute('action')||REAL);
 if(m==='get'){e.preventDefault();var q=new URLSearchParams(new FormData(f)).toString();var u=act.split('#')[0].split('?')[0]+(q?'?'+q:'');location.href=prox(u)}else{f.setAttribute('action',prox(act))}},true);
var of=window.fetch;if(of)window.fetch=function(i,o){try{var u=typeof i==='string'?i:(i&&i.url);if(u&&/^(https?:|\/|\.)/i.test(u)){var p=prox(u);i=typeof i==='string'?p:new Request(p,i)}}catch(e){}return of.call(this,i,o)};
var ox=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){try{if(u&&!/^(data|blob):/i.test(u))arguments[1]=prox(u)}catch(e){}return ox.apply(this,arguments)};
window.open=function(u){if(u)location.href=prox(u);return window};
window.addEventListener('load',tell);new MutationObserver(tell).observe(document.querySelector('title')||document.documentElement,{subtree:true,childList:true,characterData:true});tell();
})();</script>"""

def is_private(host):
    try:
        for fam, _, _, _, sa in socket.getaddrinfo(host, None):
            ip = ipaddress.ip_address(sa[0])
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
                return True
    except Exception:
        return False
    return False

def decode(data, enc):
    enc = (enc or '').lower()
    try:
        if enc == 'gzip': return gzip.decompress(data)
        if enc == 'deflate':
            try: return zlib.decompress(data)
            except zlib.error: return zlib.decompress(data, -zlib.MAX_WBITS)
    except Exception:
        pass
    return data

def rewrite_html(raw, final_url, charset):
    try: html = raw.decode(charset or 'utf-8', 'replace')
    except LookupError: html = raw.decode('utf-8', 'replace')
    html = re.sub(r'<meta[^>]+http-equiv=["\']?(content-security-policy|x-frame-options)[^>]*>', '', html, flags=re.I)
    html = re.sub(r'<meta[^>]+http-equiv=["\']?refresh[^>]*>', '', html, flags=re.I)
    html = re.sub(r'\sintegrity=["\'][^"\']*["\']', '', html, flags=re.I)
    html = re.sub(r'\scrossorigin(=["\'][^"\']*["\'])?', '', html, flags=re.I)
    base = '<base href="%s">' % final_url.replace('"', '&quot;')
    inj = INJECT.replace('%REAL%', '"%s"' % final_url.replace('\\', '\\\\').replace('"', '\\"'))
    m = re.search(r'<head[^>]*>', html, flags=re.I)
    if m: html = html[:m.end()] + base + inj + html[m.end():]
    else: html = '<head>' + base + inj + '</head>' + html
    return html.encode('utf-8')

class H(http.server.BaseHTTPRequestHandler):
    server_version = 'KWJSProxy/1.0'
    def log_message(self, fmt, *a): sys.stderr.write('[proxy] ' + fmt % a + '\n')
    def cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    def reply(self, code, body, ctype='text/plain; charset=utf-8'):
        self.send_response(code); self.cors()
        self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(body))); self.end_headers()
        if self.command != 'HEAD': self.wfile.write(body)
    def do_OPTIONS(self): self.reply(204, b'')
    def do_HEAD(self): self.handle_req()
    def do_GET(self): self.handle_req()
    def do_POST(self): self.handle_req()
    def handle_req(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == '/ping': return self.reply(200, b'kwjs-proxy ok')
        q = urllib.parse.parse_qs(u.query)
        target = (q.get('url') or [''])[0]
        if not re.match(r'^https?://', target, flags=re.I):
            return self.reply(200, ('<h3>KDE KWJS - proxy local</h3><p>Uso: /?url=https://sitio.com</p>').encode('utf-8'), 'text/html; charset=utf-8')
        host = urllib.parse.urlparse(target).hostname or ''
        if not ALLOW_PRIVATE and is_private(host):
            return self.reply(403, ('Bloqueado: %s es una direccion privada o local (usa --allow-private para permitirlo).' % host).encode('utf-8'))
        body = None
        if self.command == 'POST':
            n = int(self.headers.get('Content-Length') or 0); body = self.rfile.read(n) if n else b''
        req = urllib.request.Request(target, data=body, method='POST' if body is not None else 'GET')
        req.add_header('User-Agent', UA); req.add_header('Accept', self.headers.get('Accept', '*/*'))
        req.add_header('Accept-Language', self.headers.get('Accept-Language', 'es-AR,es;q=0.9,en;q=0.8')); req.add_header('Accept-Encoding', 'gzip, deflate')
        if body is not None: req.add_header('Content-Type', self.headers.get('Content-Type', 'application/x-www-form-urlencoded'))
        try:
            r = urllib.request.urlopen(req, timeout=25); code = r.status; hdr = r.headers; final = r.geturl(); data = r.read()
        except urllib.error.HTTPError as e:
            code = e.code; hdr = e.headers; final = target; data = e.read()
        except Exception as e:
            return self.reply(502, ('No se pudo cargar %s\n%s' % (target, e)).encode('utf-8'))
        data = decode(data, hdr.get('Content-Encoding'))
        ctype = hdr.get('Content-Type', 'application/octet-stream')
        if 'html' in ctype.lower():
            cs = re.search(r'charset=([\w\-]+)', ctype, flags=re.I)
            data = rewrite_html(data, final, cs.group(1) if cs else None); ctype = 'text/html; charset=utf-8'
        self.send_response(code); self.cors()
        for k, v in hdr.items():
            if k.lower() not in DROP and k.lower() != 'content-type': self.send_header(k, v)
        self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(data))); self.end_headers()
        if self.command != 'HEAD': self.wfile.write(data)

class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

if __name__ == '__main__':
    print('KDE KWJS proxy local escuchando en http://127.0.0.1:%d  (Ctrl+C para salir)' % PORT)
    S(('127.0.0.1', PORT), H).serve_forever()
