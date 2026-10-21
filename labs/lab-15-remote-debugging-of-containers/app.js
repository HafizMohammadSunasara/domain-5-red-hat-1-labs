
'use strict';

// Educational sample for Lab 15. Uses only Node.js built-in modules.
const http = require('node:http');

function calculateTotal(price, quantity) {
  // Set a VS Code breakpoint on the line below.
  const total = price * quantity;
  return total;
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('OK\n');
    return;
  }

  const result = calculateTotal(250, 3);
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(`Total: ${result}\n`);
});

server.listen(3000, '0.0.0.0', () => {
  console.log('Lab 15 sample app listening on port 3000');
});
