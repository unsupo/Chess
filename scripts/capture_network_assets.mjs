#!/usr/bin/env node
/**
 * Playwright Interactive Network + DevTools Sources Harvester
 *
 * Captures EVERYTHING from both:
 *   1. DevTools Network Tab (all HTTP/HTTPS responses: JS, CSS, JSON, WASM, SVG, media, XHR/fetch)
 *   2. DevTools Sources Tab via Chrome DevTools Protocol (CDP):
 *      - Page Resource Tree (`Page.getResourceTree` + `Page.getResourceContent`)
 *      - All V8 Parsed Scripts (`Debugger.scriptParsed` + `Debugger.getScriptSource`),
 *        including Web Workers, `blob:` scripts, inline `<script>` blocks, and dynamic scripts
 *      - All CSS Stylesheets (`CSS.styleSheetAdded` + `CSS.getStyleSheetText`),
 *        including constructed `CSSStyleSheet` / CSS-in-JS sheets
 *      - Source Maps (`sourceMapURL`): automatically fetches `.map` files and unpacks
 *        embedded `sourcesContent` into original `.ts` / `.vue` / `.js` source files!
 *
 * Usage:
 *   npx playwright install chromium
 *   node scripts/capture_network_assets.mjs https://www.chess.com/play/computer
 */

import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';
import readline from 'node:readline';
import crypto from 'node:crypto';

const START_URL = process.argv[2] || 'https://www.chess.com/play/computer';
const OUTPUT_ROOT = path.resolve(process.cwd(), 'captured_network');

/**
 * 1. Network tab responses: Map<url, { url, status, resourceType, contentType, body, timestamp }>
 */
const capturedNetwork = new Map();

/**
 * 2. Sources tab V8 scripts: Map<key, { scriptId, url, source, sourceMapURL, isWorker }>
 */
const capturedScripts = new Map();

/**
 * 3. Sources tab CSS stylesheets: Map<styleSheetId, { styleSheetId, sourceURL, text }>
 */
const capturedStyleSheets = new Map();

/**
 * 4. Active CDP sessions for pages so we can snapshot `Page.getResourceTree` on demand
 * @type {Set<import('playwright').CDPSession>}
 */
const activeCdpSessions = new Set();

function shortHash(input) {
  return crypto.createHash('md5').update(String(input)).digest('hex').slice(0, 8);
}

/**
 * Converts a URL and Content-Type into a safe local file path inside baseDir.
 */
function urlToFilePath(baseDir, rawUrl, contentType = '', fallbackExt = '.bin') {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return path.join(baseDir, '_inline_or_virtual', `item_${shortHash(rawUrl)}${fallbackExt}`);
  }

  if (parsed.protocol === 'blob:' || parsed.protocol === 'data:') {
    return path.join(baseDir, '_blob_and_data', `blob_${shortHash(rawUrl)}${fallbackExt}`);
  }

  const hostname = (parsed.hostname || '_local').replace(/[^a-zA-Z0-9._-]/g, '_');
  let pathname = decodeURIComponent(parsed.pathname || '/');
  if (pathname.endsWith('/')) {
    pathname += 'index';
  }

  const segments = pathname
    .split('/')
    .filter(Boolean)
    .map((seg) => seg.replace(/[<>:"|?*\x00-\x1F]/g, '_').slice(0, 120));

  let fileName = segments.pop() || 'index';
  const subDirs = segments;

  if (parsed.search) {
    const queryHash = shortHash(parsed.search);
    const ext = path.extname(fileName);
    const base = ext ? fileName.slice(0, -ext.length) : fileName;
    fileName = `${base}_q_${queryHash}${ext}`;
  }

  if (!path.extname(fileName)) {
    fileName += inferExtension(contentType, fallbackExt);
  }

  return path.join(baseDir, hostname, ...subDirs, fileName);
}

function inferExtension(contentType = '', fallback = '.bin') {
  const mime = contentType.split(';')[0].trim().toLowerCase();
  const map = {
    'application/javascript': '.js',
    'text/javascript': '.js',
    'application/x-javascript': '.js',
    'text/css': '.css',
    'text/html': '.html',
    'application/json': '.json',
    'application/wasm': '.wasm',
    'image/svg+xml': '.svg',
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'audio/mpeg': '.mp3',
    'audio/ogg': '.ogg',
    'audio/wav': '.wav',
    'font/woff2': '.woff2',
    'font/woff': '.woff',
    'text/plain': '.txt',
  };
  return map[mime] || fallback;
}

/**
 * Attaches Chrome DevTools Protocol (CDP) listeners to a Page to harvest the Sources tab:
 *   - Debugger.scriptParsed -> Debugger.getScriptSource
 *   - CSS.styleSheetAdded   -> CSS.getStyleSheetText
 *   - Page.getResourceTree  -> Page.getResourceContent (snapshotted on dump)
 */
async function attachCdpSourcesHarvester(page) {
  try {
    const client = await page.context().newCDPSession(page);
    activeCdpSessions.add(client);

    page.on('close', () => activeCdpSessions.delete(client));

    await client.send('Page.enable');
    await client.send('DOM.enable');
    await client.send('CSS.enable');
    await client.send('Debugger.enable');

    // Capture every parsed JS script in V8 (Sources -> Page / Content scripts / Workers / Dynamic eval)
    client.on('Debugger.scriptParsed', async (params) => {
      const { scriptId, url, sourceMapURL, executionContextAuxData } = params;
      if (url && url.startsWith('chrome-extension://')) return;
      // Ignore our own injected Playwright helper evaluations without URLs if tiny
      try {
        const { scriptSource } = await client.send('Debugger.getScriptSource', { scriptId });
        if (!scriptSource || scriptSource.includes('__pw-net-harvester-hud')) return;

        const key = url && url.length > 0 ? `${url}#${shortHash(scriptSource)}` : `inline_${scriptId}_${shortHash(scriptSource)}`;
        capturedScripts.set(key, {
          scriptId,
          url: url || `inline://script_${scriptId}.js`,
          source: scriptSource,
          sourceMapURL: sourceMapURL || null,
          isDefault: executionContextAuxData?.isDefault ?? true,
          timestamp: new Date().toISOString(),
        });
      } catch {
        // Script may have been garbage-collected before getScriptSource resolved
      }
    });

    // Capture every CSS stylesheet (including dynamic/constructed stylesheets in Sources)
    client.on('CSS.styleSheetAdded', async (params) => {
      const header = params.header;
      if (!header || !header.styleSheetId) return;
      if (header.sourceURL && header.sourceURL.startsWith('chrome-extension://')) return;

      try {
        const { text } = await client.send('CSS.getStyleSheetText', {
          styleSheetId: header.styleSheetId,
        });
        if (!text || text.trim().length === 0) return;

        const key = header.sourceURL
          ? `${header.sourceURL}#${shortHash(text)}`
          : `constructed_css_${header.styleSheetId}_${shortHash(text)}`;

        capturedStyleSheets.set(key, {
          styleSheetId: header.styleSheetId,
          sourceURL: header.sourceURL || `inline://stylesheet_${header.styleSheetId}.css`,
          text,
          timestamp: new Date().toISOString(),
        });
      } catch {}
    });
  } catch (err) {
    console.warn('⚠️ Could not attach CDP session to page:', err.message);
  }
}

/**
 * Collects the exact DevTools "Sources -> Page" frame resource tree using CDP
 * `Page.getResourceTree` and `Page.getResourceContent`.
 */
async function dumpCdpPageResourceTrees(sourcesTreeDir, manifest) {
  let treeCount = 0;

  for (const client of activeCdpSessions) {
    try {
      const { frameTree } = await client.send('Page.getResourceTree');
      const frames = [];
      const collectFrames = (node) => {
        frames.push({ frameId: node.frame.id, resources: node.resources || [] });
        for (const child of node.childFrames || []) {
          collectFrames(child);
        }
      };
      collectFrames(frameTree);

      for (const { frameId, resources } of frames) {
        for (const res of resources) {
          if (!res.url || res.url.startsWith('chrome-extension://') || res.url.startsWith('data:')) {
            continue;
          }
          try {
            const { content, base64Encoded } = await client.send('Page.getResourceContent', {
              frameId,
              url: res.url,
            });
            if (!content) continue;

            const buf = base64Encoded ? Buffer.from(content, 'base64') : Buffer.from(content, 'utf8');
            const targetPath = urlToFilePath(sourcesTreeDir, res.url, res.mimeType || '', '.txt');
            await fs.mkdir(path.dirname(targetPath), { recursive: true });
            await fs.writeFile(targetPath, buf);

            treeCount++;
            manifest.sourcesPageTree.push({
              url: res.url,
              type: res.type,
              mimeType: res.mimeType,
              sizeBytes: buf.length,
              savedAs: path.relative(path.dirname(sourcesTreeDir), targetPath),
            });
          } catch {
            // Resource content may not be cached by Blink if streamed
          }
        }
      }
    } catch {}
  }

  return treeCount;
}

/**
 * Unpacks any `.map` source maps found in network responses into original source files!
 */
async function unpackSourceMaps(sourceMapsDir, manifest) {
  let unpackedFiles = 0;

  for (const item of capturedNetwork.values()) {
    if (!item.url.endsWith('.map') && !item.contentType.includes('sourcemap')) {
      continue;
    }
    try {
      const mapJson = JSON.parse(item.body.toString('utf8'));
      const sources = mapJson.sources || [];
      const sourcesContent = mapJson.sourcesContent || [];

      for (let i = 0; i < sources.length; i++) {
        const srcPath = sources[i];
        const srcCode = sourcesContent[i];
        if (!srcPath || !srcCode) continue;

        const cleanRel = srcPath
          .replace(/^webpack:\/\/\/?/, '')
          .replace(/^vite:\/\/\/?/, '')
          .replace(/^\.\.\//g, '_parent_/')
          .replace(/[<>:"|?*\x00-\x1F]/g, '_');

        const targetPath = path.join(sourceMapsDir, cleanRel);
        await fs.mkdir(path.dirname(targetPath), { recursive: true });
        await fs.writeFile(targetPath, srcCode, 'utf8');

        unpackedFiles++;
        manifest.unpackedSourceMapFiles.push({
          mapUrl: item.url,
          originalSource: srcPath,
          savedAs: path.relative(path.dirname(sourceMapsDir), targetPath),
        });
      }
    } catch {}
  }

  return unpackedFiles;
}

/**
 * Writes all captured Network + Sources files to disk.
 */
async function dumpAllCapturedFiles() {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dumpDir = path.join(OUTPUT_ROOT, `dump_${stamp}`);

  const networkDir = path.join(dumpDir, 'network');
  const sourcesTreeDir = path.join(dumpDir, 'sources_page_tree');
  const v8ScriptsDir = path.join(dumpDir, 'sources_v8_scripts');
  const styleSheetsDir = path.join(dumpDir, 'sources_stylesheets');
  const sourceMapsDir = path.join(dumpDir, 'sources_unpacked_maps');

  await fs.mkdir(networkDir, { recursive: true });
  await fs.mkdir(sourcesTreeDir, { recursive: true });
  await fs.mkdir(v8ScriptsDir, { recursive: true });
  await fs.mkdir(styleSheetsDir, { recursive: true });

  const manifest = {
    capturedAt: new Date().toISOString(),
    network: [],
    sourcesPageTree: [],
    sourcesV8Scripts: [],
    sourcesStyleSheets: [],
    unpackedSourceMapFiles: [],
  };

  let totalBytes = 0;

  // 1. Save Network tab files
  let networkCount = 0;
  for (const item of capturedNetwork.values()) {
    try {
      const targetPath = urlToFilePath(networkDir, item.url, item.contentType);
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      await fs.writeFile(targetPath, item.body);

      networkCount++;
      totalBytes += item.body.length;
      manifest.network.push({
        url: item.url,
        status: item.status,
        resourceType: item.resourceType,
        contentType: item.contentType,
        sizeBytes: item.body.length,
        savedAs: path.relative(dumpDir, targetPath),
      });
    } catch {}
  }

  // 2. Save Sources -> Page Resource Tree (via CDP Page.getResourceTree)
  const treeCount = await dumpCdpPageResourceTrees(sourcesTreeDir, manifest);

  // 3. Save Sources -> V8 Parsed Scripts (inline scripts, blob workers, dynamic scripts)
  let scriptCount = 0;
  for (const item of capturedScripts.values()) {
    try {
      const targetPath = urlToFilePath(v8ScriptsDir, item.url, 'application/javascript', '.js');
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      const buf = Buffer.from(item.source, 'utf8');
      await fs.writeFile(targetPath, buf);

      scriptCount++;
      totalBytes += buf.length;
      manifest.sourcesV8Scripts.push({
        scriptId: item.scriptId,
        url: item.url,
        sourceMapURL: item.sourceMapURL,
        sizeBytes: buf.length,
        savedAs: path.relative(dumpDir, targetPath),
      });
    } catch {}
  }

  // 4. Save Sources -> CSS Stylesheets (including constructed/CSS-in-JS stylesheets)
  let cssCount = 0;
  for (const item of capturedStyleSheets.values()) {
    try {
      const targetPath = urlToFilePath(styleSheetsDir, item.sourceURL, 'text/css', '.css');
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      const buf = Buffer.from(item.text, 'utf8');
      await fs.writeFile(targetPath, buf);

      cssCount++;
      totalBytes += buf.length;
      manifest.sourcesStyleSheets.push({
        styleSheetId: item.styleSheetId,
        sourceURL: item.sourceURL,
        sizeBytes: buf.length,
        savedAs: path.relative(dumpDir, targetPath),
      });
    } catch {}
  }

  // 5. Unpack any Source Maps (.map) into original source files
  const unpackedCount = await unpackSourceMaps(sourceMapsDir, manifest);

  const manifestPath = path.join(dumpDir, 'manifest.json');
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2), 'utf8');

  const totalFiles = networkCount + treeCount + scriptCount + cssCount + unpackedCount;
  const mb = (totalBytes / (1024 * 1024)).toFixed(2);

  console.log(`\n=============================================================`);
  console.log(`✅ DUMP COMPLETE: ${totalFiles} total files (${mb} MB)`);
  console.log(`   • Network responses   : ${networkCount}`);
  console.log(`   • Sources Page Tree   : ${treeCount}`);
  console.log(`   • Sources V8 Scripts  : ${scriptCount} (includes workers, blobs & inline)`);
  console.log(`   • Sources Stylesheets : ${cssCount} (includes dynamic CSSStyleSheets)`);
  console.log(`   • Unpacked SourceMaps : ${unpackedCount}`);
  console.log(`📂 Output Folder:\n   ${dumpDir}`);
  console.log(`=============================================================\n`);

  return {
    dumpDir,
    savedCount: totalFiles,
    networkCount,
    sourcesCount: treeCount + scriptCount + cssCount,
    totalMB: mb,
  };
}

async function main() {
  console.log(`🚀 Launching Chrome with Network + CDP Sources Harvester...`);
  let browser;
  try {
    browser = await chromium.launch({
      channel: 'chrome',
      headless: false,
      args: ['--start-maximized'],
    });
  } catch {
    browser = await chromium.launch({
      headless: false,
      args: ['--start-maximized'],
    });
  }

  const context = await browser.newContext({
    viewport: null,
    ignoreHTTPSErrors: true,
  });

  // Attach CDP Sources harvester to every new page or popup opened
  context.on('page', (newPage) => {
    attachCdpSourcesHarvester(newPage);
    // Also capture Dedicated Web Workers spawned by the page
    newPage.on('worker', async (worker) => {
      const workerUrl = worker.url();
      if (workerUrl.startsWith('chrome-extension://')) return;
      try {
        // Evaluate inside worker to grab global self location if needed
        console.log(`⚙️ Detected Web Worker: ${workerUrl}`);
      } catch {}
    });
  });

  // Listen to every response in the Network tab
  context.on('response', async (response) => {
    try {
      const url = response.url();
      if (url.startsWith('data:') || url.startsWith('chrome-extension://')) {
        return;
      }

      const status = response.status();
      if (status >= 300 && status < 400) return;

      const body = await response.body();
      if (!body || body.length === 0) return;

      const headers = response.headers();
      const contentType = headers['content-type'] || '';
      const resourceType = response.request().resourceType();

      capturedNetwork.set(url, {
        url,
        status,
        resourceType,
        contentType,
        body,
        timestamp: new Date().toISOString(),
      });
    } catch {}
  });

  // Expose stats & trigger functions to the in-page floating HUD
  await context.exposeFunction('__pwGetCapturedStats', () => {
    let bytes = 0;
    for (const item of capturedNetwork.values()) bytes += item.body.length;
    return {
      netCount: capturedNetwork.size,
      srcCount: capturedScripts.size + capturedStyleSheets.size,
      mb: (bytes / (1024 * 1024)).toFixed(1),
    };
  });

  await context.exposeFunction('__pwDownloadAllFiles', async () => {
    return await dumpAllCapturedFiles();
  });

  await context.exposeFunction('__pwClearCapturedFiles', () => {
    capturedNetwork.clear();
    capturedScripts.clear();
    capturedStyleSheets.clear();
    console.log('🧹 Cleared in-memory Network + Sources cache.');
    return { count: 0 };
  });

  // Inject floating HUD overlay into every page
  await context.addInitScript(() => {
    const mountHud = () => {
      if (document.getElementById('__pw-net-harvester-hud')) return;

      const container = document.createElement('div');
      container.id = '__pw-net-harvester-hud';
      Object.assign(container.style, {
        position: 'fixed',
        bottom: '20px',
        right: '20px',
        zIndex: '2147483647',
        display: 'flex',
        gap: '8px',
        alignItems: 'center',
        background: 'rgba(20, 22, 26, 0.95)',
        border: '1px solid #81b64c',
        borderRadius: '10px',
        padding: '10px 14px',
        boxShadow: '0 8px 24px rgba(0,0,0,0.45)',
        fontFamily: 'system-ui, -apple-system, sans-serif',
        fontSize: '13px',
        color: '#ffffff',
        userSelect: 'none',
      });

      const badge = document.createElement('span');
      badge.id = '__pw-net-harvester-count';
      badge.textContent = 'Net: 0 | Sources: 0 (0.0 MB)';
      Object.assign(badge.style, {
        fontWeight: '600',
        color: '#b3e57c',
        marginRight: '4px',
      });

      const downloadBtn = document.createElement('button');
      downloadBtn.textContent = '📥 Download Network + Sources';
      Object.assign(downloadBtn.style, {
        background: '#81b64c',
        color: '#ffffff',
        border: 'none',
        borderRadius: '6px',
        padding: '7px 12px',
        fontWeight: '700',
        cursor: 'pointer',
        fontSize: '13px',
      });

      const clearBtn = document.createElement('button');
      clearBtn.textContent = '🗑️ Clear';
      Object.assign(clearBtn.style, {
        background: '#3b3e45',
        color: '#d1d5db',
        border: 'none',
        borderRadius: '6px',
        padding: '7px 10px',
        fontWeight: '600',
        cursor: 'pointer',
        fontSize: '12px',
      });

      downloadBtn.addEventListener('click', async () => {
        downloadBtn.disabled = true;
        downloadBtn.textContent = '⏳ Dumping Network + Sources...';
        try {
          const res = await window.__pwDownloadAllFiles();
          downloadBtn.textContent = `✅ Saved ${res.savedCount} files (${res.totalMB} MB)!`;
          setTimeout(() => {
            downloadBtn.disabled = false;
            downloadBtn.textContent = '📥 Download Network + Sources';
          }, 3000);
        } catch {
          downloadBtn.textContent = '❌ Error (check terminal)';
          downloadBtn.disabled = false;
        }
      });

      clearBtn.addEventListener('click', async () => {
        await window.__pwClearCapturedFiles();
        badge.textContent = 'Net: 0 | Sources: 0 (0.0 MB)';
      });

      container.append(badge, downloadBtn, clearBtn);
      document.documentElement.appendChild(container);

      setInterval(async () => {
        if (typeof window.__pwGetCapturedStats === 'function') {
          try {
            const stats = await window.__pwGetCapturedStats();
            badge.textContent = `Net: ${stats.netCount} | Src: ${stats.srcCount} (${stats.mb} MB)`;
          } catch {}
        }
      }, 1000);
    };

    if (document.readyState === 'loading') {
      window.addEventListener('DOMContentLoaded', mountHud);
    } else {
      mountHud();
    }
  });

  const page = await context.newPage();
  console.log(`🌐 Navigating to ${START_URL} ...`);
  await page.goto(START_URL, { waitUntil: 'domcontentloaded' });

  console.log(`\n=============================================================`);
  console.log(`🎯 READY! Navigate through the site in the Chromium window.`);
  console.log(`👉 Click "📥 Download Network + Sources" in the bottom-right`);
  console.log(`   corner of the webpage at any time (or press ENTER here).`);
  console.log(`=============================================================\n`);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  rl.on('line', async () => {
    await dumpAllCapturedFiles();
  });

  browser.on('disconnected', () => {
    console.log('👋 Browser closed. Exiting.');
    process.exit(0);
  });
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
