const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

async function createOgImage() {
  const width = 1200;
  const height = 630;

  const screenshotPath = path.join(__dirname, 'public', 'hero-screenshot.png');
  
  // Create rounded mask for screenshot
  const phoneWidth = 330;
  const phoneHeight = 492;
  const maskSvg = Buffer.from(
    `<svg width="${phoneWidth}" height="${phoneHeight}"><rect width="${phoneWidth}" height="${phoneHeight}" rx="36" ry="36" fill="#fff"/></svg>`
  );

  const screenshotBuffer = await sharp(screenshotPath)
    .resize(phoneWidth, phoneHeight, { fit: 'cover' })
    .composite([{ input: maskSvg, blend: 'dest-in' }])
    .toBuffer();

  const svgBanner = `
  <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#060C1E" />
        <stop offset="50%" stop-color="#0F172A" />
        <stop offset="100%" stop-color="#0B132B" />
      </linearGradient>
      <linearGradient id="blueGrad" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#38BDF8" />
        <stop offset="100%" stop-color="#818CF8" />
      </linearGradient>
      <filter id="softGlow" x="-20%" y="-20%" width="140%" height="140%">
        <feGaussianBlur stdDeviation="70" result="blur" />
      </filter>
      <filter id="cardShadow" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="24" stdDeviation="30" flood-color="#000" flood-opacity="0.6" />
      </filter>
    </defs>

    <!-- Background -->
    <rect width="${width}" height="${height}" fill="url(#bgGrad)" />

    <!-- Ambient Glow Circles -->
    <circle cx="220" cy="180" r="260" fill="#2457D6" opacity="0.22" filter="url(#softGlow)" />
    <circle cx="950" cy="350" r="280" fill="#0E8A7E" opacity="0.18" filter="url(#softGlow)" />

    <!-- Left Content Box -->
    <g transform="translate(80, 75)">
      <!-- Trust Eyebrow -->
      <rect x="0" y="0" width="375" height="36" rx="18" fill="rgba(36, 87, 214, 0.22)" stroke="#3B82F6" stroke-width="1.2" />
      <circle cx="18" cy="18" r="5" fill="#10B981" />
      <text x="32" y="23" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-size="12" font-weight="700" fill="#93C5FD" letter-spacing="0.6">100% OFFLINE · HARDWARE KEYSTORE</text>

      <!-- Main Headline -->
      <text x="0" y="98" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-size="56" font-weight="800" fill="#FFFFFF" letter-spacing="-1">
        IDSnap
      </text>
      <text x="0" y="150" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-size="32" font-weight="700" fill="url(#blueGrad)">
        The Private Identity &amp; Document Studio
      </text>

      <!-- Subheadline -->
      <text x="0" y="202" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-size="18" font-weight="400" fill="#94A3B8">
        Clean ID Card Merging · Official Passport Photos
      </text>
      <text x="0" y="230" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-size="18" font-weight="400" fill="#94A3B8">
        Target-Size PDF Compressor (≤ 200 KB) · Offline 2FA
      </text>

      <!-- Key Value Badges -->
      <g transform="translate(0, 275)">
        <!-- Card 1 -->
        <rect x="0" y="0" width="230" height="64" rx="12" fill="rgba(255, 255, 255, 0.05)" stroke="rgba(255, 255, 255, 0.1)" />
        <text x="16" y="28" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="700" fill="#38BDF8">ID CARD 1-SHEET</text>
        <text x="16" y="48" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="13" font-weight="500" fill="#E2E8F0">Front &amp; Back on 1 A4</text>

        <!-- Card 2 -->
        <rect x="245" y="0" width="230" height="64" rx="12" fill="rgba(255, 255, 255, 0.05)" stroke="rgba(255, 255, 255, 0.1)" />
        <text x="261" y="28" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="700" fill="#34D399">PORTAL COMPRESSOR</text>
        <text x="261" y="48" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="13" font-weight="500" fill="#E2E8F0">Strictly Under 200 KB</text>

        <!-- Card 3 -->
        <rect x="0" y="78" width="230" height="64" rx="12" fill="rgba(255, 255, 255, 0.05)" stroke="rgba(255, 255, 255, 0.1)" />
        <text x="16" y="106" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="700" fill="#F472B6">OFFLINE 2FA VAULT</text>
        <text x="16" y="126" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="13" font-weight="500" fill="#E2E8F0">KeyStore Hardware TOTP</text>

        <!-- Card 4 -->
        <rect x="245" y="78" width="230" height="64" rx="12" fill="rgba(255, 255, 255, 0.05)" stroke="rgba(255, 255, 255, 0.1)" />
        <text x="261" y="106" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="700" fill="#FBBF24">PASSPORT STUDIO</text>
        <text x="261" y="126" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="13" font-weight="500" fill="#E2E8F0">35x45 mm &amp; 2x2 in Visa</text>
      </g>

      <!-- Bottom Platform Tag -->
      <g transform="translate(0, 450)">
        <text x="0" y="18" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="14" font-weight="600" fill="#64748B">
          Available on Google Play · Free · Zero Server Uploads · ids-nap-bi3.pages.dev
        </text>
      </g>
    </g>

    <!-- Phone Bezel Shadow Backing -->
    <rect x="765" y="64" width="340" height="502" rx="40" fill="#000" opacity="0.35" filter="url(#cardShadow)" />
  </svg>
  `;

  const svgBuffer = Buffer.from(svgBanner);
  const outputPath = path.join(__dirname, 'public', 'og-image.png');

  await sharp(svgBuffer)
    .composite([
      {
        input: screenshotBuffer,
        top: 69,
        left: 770,
      }
    ])
    .png({ quality: 90, compressionLevel: 8 })
    .toFile(outputPath);

  console.log('Successfully created refined og-image.png at:', outputPath);
}

createOgImage().catch(console.error);
