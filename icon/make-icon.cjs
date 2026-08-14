// Regenerate icon/icon-1024.png + icon/AppIcon.iconset from icon/favicon.svg.
// Then produce the macOS icon:  iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns
// Needs `sharp`. Run with a node whose ABI matches sharp, e.g.:
//   '/Users/sunkey/Library/Application Support/DeepSeek Harness/runtime/node/bin/node' icon/make-icon.cjs
const fs = require('fs');

const sharpCandidates = [
  '/Users/sunkey/Library/Application Support/DeepSeek Harness/runtime/node_modules/sharp',
  '/Users/sunkey/.dsh/profiles/node_modules/sharp',
];
let sharp = null;
for (const c of sharpCandidates) {
  try { sharp = require(c); if (sharp) break; } catch (_) { /* try next */ }
}
if (!sharp) {
  console.error('sharp not found. Update sharpCandidates or npm install sharp.');
  process.exit(1);
}

const faviconPath = __dirname + '/favicon.svg';
const favicon = fs.readFileSync(faviconPath, 'utf8');
const m = favicon.match(/<path[^>]*\bd="([^"]+)"/);
if (!m) { console.error('no path found in favicon.svg'); process.exit(1); }
const whaleD = m[1];

const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">' +
  '  <defs>' +
  '    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">' +
  '      <stop offset="0" stop-color="#6B8AFF"/>' +
  '      <stop offset="1" stop-color="#4D6BFE"/>' +
  '    </linearGradient>' +
  '  </defs>' +
  '  <rect x="0" y="0" width="1024" height="1024" rx="230" ry="230" fill="url(#bg)"/>' +
  '  <g transform="translate(187,187) scale(13)" fill="#ffffff">' +
  '    <path d="' + whaleD + '"/>' +
  '  </g>' +
  '</svg>';

const out = __dirname + '/icon-1024.png';
const iconset = __dirname + '/AppIcon.iconset';

(async () => {
  await sharp(Buffer.from(svg)).png().toFile(out);
  fs.mkdirSync(iconset, { recursive: true });
  const sizes = [
    ['icon_16x16.png', 16],
    ['icon_16x16@2x.png', 32],
    ['icon_32x32.png', 32],
    ['icon_32x32@2x.png', 64],
    ['icon_128x128.png', 128],
    ['icon_128x128@2x.png', 256],
    ['icon_256x256.png', 256],
    ['icon_256x256@2x.png', 512],
    ['icon_512x512.png', 512],
    ['icon_512x512@2x.png', 1024],
  ];
  for (const s of sizes) {
    await sharp(out).resize(s[1], s[1]).png().toFile(iconset + '/' + s[0]);
  }
  console.log('iconset written to', iconset);
  console.log('next: iconutil -c icns ' + iconset + ' -o ' + __dirname + '/AppIcon.icns');
})().catch((e) => { console.error(e); process.exit(1); });
