"""Route protected Preview APIs to production without sharing database files."""
from pathlib import Path
import sys

BEGIN = '    # BEGIN Synca Preview production API\n'
END = '    # END Synca Preview production API\n'
BLOCK = '''    # BEGIN Synca Preview production API
    location = /__preview/production-gate {
        internal;
        proxy_pass http://127.0.0.1:3004/health;
        proxy_method GET;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Host $host;
        proxy_set_header X-Preview-Authenticated "";
        proxy_set_header Authorization "";
        proxy_set_header Accept "application/json";
    }
    location ~ ^/(auth|messages|message-categories|me|sync|scratchpad|app-updates|feedback|api|oauth|mcp)(/|$) {
        auth_request /__preview/production-gate;
        proxy_pass http://127.0.0.1:3002;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 900s;
        proxy_send_timeout 900s;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Preview-Authenticated "";
    }
    # END Synca Preview production API
'''


def transform(source: str) -> str:
    if source.count('server_name synca-preview.haerth.cn;') != 2:
        raise ValueError('Expected existing Preview HTTP and HTTPS servers')
    if 'server_name synca.haerth.cn;' in source:
        raise ValueError('Refusing production site configuration')
    if BEGIN in source:
        if source.count(BEGIN) != 1 or source.count(END) != 1:
            raise ValueError('Ambiguous managed configuration')
        before, tail = source.split(BEGIN)
        _, after = tail.split(END)
        source = before + after
    anchor = '    location = /__preview/unlock {'
    if source.count(anchor) != 1 or 'auth_basic_user_file /opt/synca-preview/access.htpasswd;' not in source:
        raise ValueError('Existing Preview access gate is required')
    return source.replace(anchor, BLOCK + anchor)


if __name__ == '__main__':
    Path(sys.argv[2]).write_text(transform(Path(sys.argv[1]).read_text()))
