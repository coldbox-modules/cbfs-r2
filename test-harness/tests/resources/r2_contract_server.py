#!/usr/bin/env python3
"""Loopback S3 contract fixture. Validates SigV4 and rejects R2-unsupported ACLs.

This is a protocol test, not proof of a real R2 account's permissions or TLS setup.
Only synthetic credentials and in-memory objects are used.
"""
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import threading
import time
from urllib.parse import parse_qsl, quote, unquote, urlsplit

ACCESS = 'contract-access'
SECRET = 'contract-secret'
OBJECTS = {}
EVENTS = []


def digest(value):
    return hashlib.sha256(value).hexdigest()


def signature(method, target, headers, body):
    parsed = urlsplit(target)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    presigned = 'X-Amz-Signature' in query
    if presigned:
        credential = query['X-Amz-Credential']
        signed = query['X-Amz-SignedHeaders']
        supplied = query.pop('X-Amz-Signature')
        stamp = query['X-Amz-Date']
        payload = 'UNSIGNED-PAYLOAD'
        assert 1 <= int(query['X-Amz-Expires']) <= 900, 'unbounded signed URL'
    else:
        algorithm, auth = headers['authorization'].split(' ', 1)
        assert algorithm == 'AWS4-HMAC-SHA256'
        fields = dict(part.strip().split('=', 1) for part in auth.split(','))
        credential, signed, supplied = fields['Credential'], fields['SignedHeaders'], fields['Signature']
        stamp = headers['x-amz-date']
        payload = headers.get('x-amz-content-sha256', digest(body))
        assert payload == digest(body), 'body hash mismatch'
    access, date, region, service, terminator = credential.split('/')
    assert (access, service, terminator) == (ACCESS, 's3', 'aws4_request')
    assert region in ('auto', '', 'us-east-1'), 'unsupported R2 signing region'
    canonical_uri = quote(unquote(parsed.path), safe='/~')
    canonical_query = '&'.join(f'{quote(k, safe="~")}={quote(v, safe="~")}' for k, v in sorted(query.items()))
    canonical_headers = ''.join(f'{name}:{" ".join(headers[name].strip().split())}\n' for name in signed.split(';'))
    canonical = '\n'.join([method, canonical_uri, canonical_query, canonical_headers, signed, payload])
    scope = '/'.join([date, region, service, terminator])
    text = '\n'.join(['AWS4-HMAC-SHA256', stamp, scope, digest(canonical.encode())])
    signing = ('AWS4' + SECRET).encode()
    for part in (date, region, service, terminator):
        signing = hmac.new(signing, part.encode(), hashlib.sha256).digest()
    expected = hmac.new(signing, text.encode(), hashlib.sha256).hexdigest()
    assert hmac.compare_digest(expected, supplied), 'signature mismatch'
    return unquote(parsed.path)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def respond(self, status, body=b'', headers=None):
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def handle_request(self):
        if self.path == '/__evidence':
            return self.respond(200, json.dumps(EVENTS).encode(), {'Content-Type': 'application/json'})
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        headers = {key.lower(): value for key, value in self.headers.items()}
        event = {'method': self.command, 'path': self.path.split('?')[0], 'valid': False}
        EVENTS.append(event)
        try:
            assert 'x-amz-acl' not in headers and 'acl' not in dict(parse_qsl(urlsplit(self.path).query, keep_blank_values=True)), 'ACL unsupported'
            key = signature(self.command, self.path, headers, body)
            assert key.startswith(('/private-contract/', '/public-contract/')), 'wrong bucket or addressing style'
            event['valid'] = True
        except Exception as error:
            event['error'] = str(error)
            return self.respond(403, ('<Error><Code>AccessDenied</Code><Message>' + str(error) + '</Message></Error>').encode(), {'Content-Type': 'application/xml'})
        if self.command == 'PUT' and 'x-amz-copy-source' in headers:
            if key.endswith('/fail-copy.pdf'):
                return self.respond(403, b'<Error><Code>AccessDenied</Code><Message>copy denied</Message></Error>', {'Content-Type': 'application/xml'})
            source = unquote(headers['x-amz-copy-source'])
            if source not in OBJECTS:
                return self.respond(404)
            OBJECTS[key] = OBJECTS[source]
            return self.respond(200, b'<CopyObjectResult><ETag>"copied"</ETag></CopyObjectResult>', {'Content-Type': 'application/xml'})
        if self.command == 'PUT':
            OBJECTS[key] = (body, headers.get('content-type', 'application/octet-stream'))
            return self.respond(200, headers={'ETag': '"' + hashlib.md5(body).hexdigest() + '"'})
        if self.command == 'DELETE':
            OBJECTS.pop(key, None)
            return self.respond(204)
        if key not in OBJECTS:
            return self.respond(404)
        body, content_type = OBJECTS[key]
        self.respond(200, body, {'Content-Type': content_type, 'ETag': '"' + hashlib.md5(body).hexdigest() + '"',
                                 'Last-Modified': 'Thu, 10 Sep 2026 00:00:00 GMT'})

    do_HEAD = handle_request
    do_GET = handle_request
    do_PUT = handle_request
    do_DELETE = handle_request


def main():
    parent = os.getppid()
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    def watch_parent():
        while os.getppid() == parent:
            time.sleep(1)
        server.shutdown()
    threading.Thread(target=watch_parent, daemon=True).start()
    print(server.server_port, flush=True)
    server.serve_forever(poll_interval=0.2)
    server.server_close()


if __name__ == '__main__':
    main()
