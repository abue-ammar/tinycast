const http = require('node:http');
const base = 'http://127.0.0.1:4963';
let refreshes = 0;
let calls = 0;
let redirects = 0;
const server = http.createServer(async (req, res) => {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  const send = (status, body, headers = {}) => {
    res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
    res.end(JSON.stringify(body));
  };
  const metadata = {
    issuer: base, authorization_endpoint: base + '/authorize', token_endpoint: base + '/token',
    registration_endpoint: base + '/register', code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'], authorization_response_iss_parameter_supported: true,
  };
  if (req.url === '/.well-known/oauth-protected-resource/mcp') {
    return send(200, { resource: base + '/mcp', authorization_servers: [base], scopes_supported: ['read'] });
  }
  if (req.url === '/.well-known/oauth-authorization-server') return send(200, metadata);
  if (req.url === '/register') {
    const body = JSON.parse(raw);
    if (body.application_type !== 'native' || body.token_endpoint_auth_method !== 'none' ||
        !body.grant_types.includes('refresh_token') || body.redirect_uris[0] !== 'http://127.0.0.1:4962/callback') {
      return send(400, {});
    }
    return send(201, { client_id: 'fixture-client', token_endpoint_auth_method: 'none', redirect_uris: body.redirect_uris });
  }
  if (req.url === '/token') {
    const fields = new URLSearchParams(raw);
    if (fields.get('resource') !== base + '/mcp' || fields.get('client_id') !== 'fixture-client') return send(400, {});
    if (fields.get('grant_type') === 'refresh_token') {
      if (fields.get('refresh_token') === 'fixture-unavailable') return send(503, {});
      if (fields.get('refresh_token') === 'fixture-dropped') return req.socket.destroy();
      refreshes++;
      if (fields.get('refresh_token') !== 'fixture-refresh') return send(400, {error: 'invalid_grant'});
    } else if (fields.get('code') !== 'fixture-code' || !fields.get('code_verifier')) return send(400, {});
    return send(200, { access_token: 'fixture-access', token_type: 'Bearer', refresh_token: 'rotated-refresh', expires_in: 3600 });
  }
  if (req.url === '/redirect') {
    res.writeHead(307, { Location: base + '/unexpected' });
    return res.end();
  }
  if (req.url === '/mcp-moved') {
    res.writeHead(307, { Location: base + '/mcp' });
    return res.end();
  }
  if (req.url === '/mcp-away') {
    res.writeHead(307, { Location: 'http://localhost:4963/unexpected' });
    return res.end();
  }
  if (req.url === '/unexpected') { redirects++; return send(200, {}); }
  if (req.url === '/counts') return send(200, { refreshes, calls, redirects });
  if (req.url === '/always-401') { calls++; return send(401, {}); }
  if (req.url === '/mcp') {
    calls++;
    if (req.headers.authorization !== 'Bearer fixture-access') {
      return send(401, {}, { 'WWW-Authenticate': `Bearer resource_metadata="${base}/.well-known/oauth-protected-resource/mcp", scope="read"` });
    }
    const request = JSON.parse(raw);
    if (!request.id) { res.writeHead(202); return res.end(); }
    const result = request.method === 'initialize' ? {
      protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'oauth-fixture', version: '1' }
    } : request.method === 'tools/list' ? {
      tools: [{name: 'greet', description: 'Say hello', inputSchema: {type: 'object', properties: {}}}]
    } : { content: [{type: 'text', text: 'Hello from OAuth'}] };
    return send(200, { jsonrpc: '2.0', id: request.id, result });
  }
  send(404, {});
});
server.on('error', error => { console.error(error.code); process.exit(1); });
server.listen(4963, '127.0.0.1', () => console.log('ready'));
