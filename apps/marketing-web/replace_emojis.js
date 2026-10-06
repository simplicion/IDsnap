import fs from 'node:fs';
import path from 'node:path';

const pagesDir = './src/pages';
const files = fs.readdirSync(pagesDir).filter(f => f.endsWith('.astro'));

const svgIcons = {
  idCard: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="3"></rect><circle cx="9" cy="10" r="2"></circle><line x1="15" y1="8" x2="17" y2="8"></line><line x1="15" y1="12" x2="17" y2="12"></line><line x1="7" y1="16" x2="17" y2="16"></line></svg>`,
  shieldKey: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path><circle cx="12" cy="11" r="2"></circle><path d="M12 13v3"></path></svg>`,
  compress: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 14 10 14 10 20"></polyline><polyline points="20 10 14 10 14 4"></polyline><line x1="14" y1="10" x2="21" y2="3"></line><line x1="3" y1="21" x2="10" y2="14"></line></svg>`,
  camera: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"></path><circle cx="12" cy="13" r="4"></circle></svg>`,
  signature: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"></path><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path></svg>`,
  ocr: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line></svg>`,
  merge: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 2 7 12 12 22 7 12 2"></polygon><polyline points="2 17 12 22 22 17"></polyline><polyline points="2 12 12 17 22 12"></polyline></svg>`,
  convert: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"></path></svg>`,
  home: `<svg class="icon-inline" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path></svg>`,
  tools: `<svg class="icon-inline" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"></path></svg>`,
  lock: `<svg class="icon-inline" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>`,
  mail: `<svg class="icon-inline" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"></path><polyline points="22,6 12,13 2,6"></polyline></svg>`,
  briefcase: `<svg class="icon-inline" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="7" width="20" height="14" rx="2" ry="2"></rect><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"></path></svg>`,
  plane: `<svg class="icon-inline" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"></path></svg>`,
  shieldBig: `<svg class="icon-inline" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path></svg>`,
  folder: `<svg class="icon-inline" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg>`,
  cloud: `<svg class="icon-inline" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z"></path></svg>`,
  git: `<svg class="icon-inline" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="18" r="3"></circle><circle cx="6" cy="6" r="3"></circle><circle cx="18" cy="6" r="3"></circle><path d="M18 9v1a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V9"></path><path d="M12 12v3"></path></svg>`
};

for (const file of files) {
  const filePath = path.join(pagesDir, file);
  let content = fs.readFileSync(filePath, 'utf8');

  // Replace emojis with clean SVGs
  content = content
    .replace(/<span class="mock-tag">🪪 ID Card Mode<\/span>/g, `<span class="mock-tag">${svgIcons.idCard} ID Card Mode</span>`)
    .replace(/<span class="mock-tag">🔐 2FA Authenticator<\/span>/g, `<span class="mock-tag">${svgIcons.shieldKey} 2FA Authenticator</span>`)
    .replace(/<span class="mock-tag">🗜️ Target Compressor<\/span>/g, `<span class="mock-tag">${svgIcons.compress} Target Compressor</span>`)
    .replace(/<div class="nav-item active">🏠 Home<\/div>/g, `<div class="nav-item active">${svgIcons.home} Home</div>`)
    .replace(/<div class="nav-item">🪪 Identity<\/div>/g, `<div class="nav-item">${svgIcons.idCard} Identity</div>`)
    .replace(/<div class="nav-item">🔐 2FA<\/div>/g, `<div class="nav-item">${svgIcons.shieldKey} 2FA</div>`)
    .replace(/<div class="nav-item">🛠️ Tools<\/div>/g, `<div class="nav-item">${svgIcons.tools} Tools</div>`)
    .replace(/<div class="feature-icon-badge">🪪<\/div>/g, `<div class="feature-icon-badge">${svgIcons.idCard}</div>`)
    .replace(/<div class="feature-icon-badge">📸<\/div>/g, `<div class="feature-icon-badge">${svgIcons.camera}</div>`)
    .replace(/<div class="feature-icon-badge">✍️<\/div>/g, `<div class="feature-icon-badge">${svgIcons.signature}</div>`)
    .replace(/<div class="bento-icon">🗜️<\/div>/g, `<div class="bento-icon">${svgIcons.compress}</div>`)
    .replace(/<div class="bento-icon">🔍<\/div>/g, `<div class="bento-icon">${svgIcons.ocr}</div>`)
    .replace(/<div class="bento-icon">📑<\/div>/g, `<div class="bento-icon">${svgIcons.merge}</div>`)
    .replace(/<div class="bento-icon">🔄<\/div>/g, `<div class="bento-icon">${svgIcons.convert}</div>`)
    .replace(/<div class="demo-issuer-icon s-icon">☁️<\/div>/g, `<div class="demo-issuer-icon s-icon">${svgIcons.cloud}</div>`)
    .replace(/<div class="demo-issuer-icon gh-icon">🐙<\/div>/g, `<div class="demo-issuer-icon gh-icon">${svgIcons.git}</div>`)
    .replace(/🔒 Auto-clears/g, `${svgIcons.lock} Auto-clears`)
    .replace(/<h4>📷 Camera/g, `<h4>${svgIcons.camera} Camera`)
    .replace(/<h4>📁 Storage/g, `<h4>${svgIcons.folder} Storage`)
    .replace(/<h4>🔐 Biometrics/g, `<h4>${svgIcons.shieldKey} Biometrics`)
    .replace(/<div class="pillar-icon">🔒<\/div>/g, `<div class="pillar-icon">${svgIcons.lock}</div>`)
    .replace(/<div class="pillar-icon">✈️<\/div>/g, `<div class="pillar-icon">${svgIcons.plane}</div>`)
    .replace(/<div class="pillar-icon">🛡️<\/div>/g, `<div class="pillar-icon">${svgIcons.shieldBig}</div>`)
    .replace(/<div class="card-icon">✉️<\/div>/g, `<div class="card-icon">${svgIcons.mail}</div>`)
    .replace(/<div class="card-icon">🔐<\/div>/g, `<div class="card-icon">${svgIcons.shieldBig}</div>`)
    .replace(/<div class="card-icon">💼<\/div>/g, `<div class="card-icon">${svgIcons.briefcase}</div>`)
    .replace(/🪪/g, '')
    .replace(/🔐/g, '')
    .replace(/🛠️/g, '')
    .replace(/🔒/g, '');

  fs.writeFileSync(filePath, content, 'utf8');
}

console.log('Successfully replaced all emojis with professional SVG icons in all pages!');
