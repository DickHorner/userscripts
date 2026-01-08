// ==UserScript==
// @name         ChatGPT Condense and New
// @namespace    https://github.com/DickHorner
// @version      1.0
// @description  If a chat becomes too long and complex, it goes all snail mode. This script builds a compact extractive summary locally and optionally pastes it into a new chat. No external APIs or keys. Configurable and privacy-preserving.
// @author       Jasper Luetkens
// @match        https://chatgpt.com/*
// @grant        GM_setClipboard
// @grant        GM_notification
// @run-at       document-idle
// ==/UserScript==

/*
  Summary:
    - Monitors the chat message container.
    - When message count reaches threshold, it produces an extractive summary (top N sentences).
    - Provides a floating control panel with manual/auto trigger, copy-to-clipboard, and optional "open new chat & paste summary" behavior.
    - All work is done locally in the browser (no network calls).
    - Auto-creating new chats is opt-in. Leaving that off is safest regarding accidental actions.

*/

/* ===========================
   Configuration (edit here)
   =========================== */
const CONFIG = {
    // How many messages (approx) before auto-summarize triggers
    MESSAGE_THRESHOLD: 100,

    // How many sentences to include in the summary
    SUMMARY_SENTENCES: 6,

    // How many of the most recent messages to include in the summarization window
    MESSAGE_WINDOW: 400,

    // Auto-create a new chat and paste the summary into the input? (false = only copy to clipboard + show)
    AUTO_CREATE_NEW_CHAT: false,

    // If AUTO_CREATE_NEW_CHAT = true, delay (ms) to wait for new chat UI to appear
    NEW_CHAT_PASTE_DELAY_MS: 1200,

    // Candidate selectors for message elements (tries sequentially)
    MESSAGE_SELECTORS: [
        'div[data-testid="message-blob"]',         // past/future proof
        'div[data-testid^="chat-message"]',
        'div[class*="message"]',
        'div[class*="group"]'
    ],

    // Candidate selectors for "new chat" button
    NEW_CHAT_SELECTORS: [
        "a[href='/chat']",
        "button[aria-label='New chat']",
        "a[data-testid='new-chat-button']",
        "a[role='link'][href='/chat']"
    ],

    // Candidate selectors for chat input / textarea
    TEXTAREA_SELECTORS: [
        "textarea",
        "div[contenteditable='true']"
    ]
};
/* ===========================
   End configuration
   =========================== */

/* Minimal set of English+German stopwords (keeps summary focused). Add more if desired. */
const STOPWORDS = new Set((
    "the,and,for,are,not,that,this,with,you,was,have,from,they,will,what,when,which,there,were,been,has,but,all,any,can,if,or,as,at,by,on,it,is,a,an,of,in,to,be,do,so,its,also," +
    "der,das,die,und,ist,im,den,ein,eine,als,zu,mit,auf,für,nicht,dem,aus,sich,ist,wie,sind,haben,hat,wurde,war,noch,bei,sie,er,es,wir,auch"
).split(",").map(s => s.trim().toLowerCase()));

/* Utility: find a working DOM selector from an array of candidates */
function findWorkingSelector(candidates) {
    for (const sel of candidates) {
        try {
            const el = document.querySelector(sel);
            if (el) return sel;
        } catch (e) { /* ignore invalid selectors */ }
    }
    return null;
}

/* Try to get message elements using known candidate selectors */
function getMessageElements() {
    const sel = findWorkingSelector(CONFIG.MESSAGE_SELECTORS);
    if (!sel) return [];
    return Array.from(document.querySelectorAll(sel)).filter(el => el && el.innerText && el.innerText.trim().length > 0);
}

/* Heuristic to get plain text content of a message element */
function extractMessageText(el) {
    // Prefer visible text only
    const txt = el.innerText || el.textContent || "";
    return txt.trim();
}

/* Basic sentence splitter (keeps punctuation). Works reasonably for English/German. */
function splitIntoSentences(text) {
    // First normalize some whitespace
    const t = text.replace(/\s+/g, " ").trim();
    // Split on punctuation followed by space and capital (approx), but fallback to period-based splitting
    let sentences = t.split(/(?<=[.!?])\s+/g);
    // If only 1 chunk, try line breaks
    if (sentences.length === 1) sentences = t.split(/\n+/).map(s => s.trim()).filter(Boolean);
    // Final fallback: return the whole text as single sentence
    if (sentences.length === 0) return [t];
    return sentences.map(s => s.trim()).filter(Boolean);
}

/* Tokenize a sentence into lowercased words, removing short tokens. */
function tokenize(s) {
    return (s.toLowerCase().match(/\b[a-zäöüßáàéèíìóòúù0-9]+\b/gi) || [])
        .map(w => w.trim())
        .filter(w => w.length >= 3 && !STOPWORDS.has(w));
}

/* Build TF (term frequency) map for entire text */
function buildTermFrequencies(sentences) {
    const freq = Object.create(null);
    for (const s of sentences) {
        for (const w of tokenize(s)) freq[w] = (freq[w] || 0) + 1;
    }
    return freq;
}

/* Score sentences by sum of token frequencies; shorter sentences get slight boost; earlier sentences get slight boost. */
function rankSentences(sentences, freqMap) {
    return sentences.map((s, idx) => {
        const tokens = tokenize(s);
        const tokenScore = tokens.reduce((sum, w) => sum + (freqMap[w] || 0), 0);
        const lengthPenalty = Math.sqrt(Math.max(1, tokens.length)); // avoid favoring extremely long sentences
        const positionBonus = 1 / (1 + Math.floor(idx / 8)); // earlier sentences slightly favored
        const score = (tokenScore / lengthPenalty) * positionBonus;
        return { text: s, score, index: idx };
    }).sort((a, b) => b.score - a.score);
}

/* Build extractive summary: pick top N sentences then sort by original order */
function buildSummaryFromText(text, maxSentences = CONFIG.SUMMARY_SENTENCES) {
    const sentences = splitIntoSentences(text);
    if (sentences.length <= maxSentences) return sentences.join(" ");
    const freq = buildTermFrequencies(sentences);
    const ranked = rankSentences(sentences, freq);
    const top = ranked.slice(0, maxSentences).sort((a, b) => a.index - b.index);
    return top.map(x => x.text).join(" ");
}

/* Collect the most recent messages (window) into a single large text blob */
function collectRecentText() {
    const els = getMessageElements();
    const chosen = els.slice(-CONFIG.MESSAGE_WINDOW);
    const texts = chosen.map(extractMessageText).filter(Boolean);
    // join with double newline to preserve some sentence boundaries
    return texts.join("\n\n");
}

/* Try to click "New Chat" using candidate selectors */
function tryOpenNewChat() {
    for (const sel of CONFIG.NEW_CHAT_SELECTORS) {
        const btn = document.querySelector(sel);
        if (btn) {
            btn.click();
            return true;
        }
    }
    // If not found, try matching link text
    const anchors = Array.from(document.querySelectorAll('a, button'));
    for (const a of anchors) {
        if (/new chat/i.test(a.innerText || "") || /start new/i.test(a.innerText || "")) { a.click(); return true; }
    }
    return false;
}

/* Try to find an input area and paste summary text (do not submit). Works with textarea or contenteditable. */
function tryPasteIntoInput(summaryText) {
    for (const sel of CONFIG.TEXTAREA_SELECTORS) {
        const ta = document.querySelector(sel);
        if (!ta) continue;
        // If contenteditable div
        if (ta.getAttribute && ta.getAttribute('contenteditable') === 'true') {
            ta.focus();
            // Insert plain text
            document.execCommand('insertText', false, summaryText);
            ta.dispatchEvent(new InputEvent('input', { bubbles: true }));
            return true;
        }
        // If textarea
        if (ta.tagName && ta.tagName.toLowerCase() === 'textarea') {
            ta.focus();
            ta.value = summaryText;
            ta.dispatchEvent(new Event('input', { bubbles: true }));
            return true;
        }
    }
    return false;
}

/* Copy to clipboard using Tampermonkey helper if available, otherwise navigator.clipboard */
function copyToClipboard(text) {
    if (typeof GM_setClipboard === "function") {
        try { GM_setClipboard(text); return true; } catch (e) { /* fall through */ }
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(() => { }, () => { });
        return true;
    }
    // fallback: create temporary textarea
    const tmp = document.createElement('textarea');
    tmp.value = text;
    tmp.style.position = 'fixed';
    tmp.style.left = '-9999px';
    document.body.appendChild(tmp);
    tmp.select();
    try { document.execCommand('copy'); document.body.removeChild(tmp); return true; } catch (e) { document.body.removeChild(tmp); return false; }
}

/* Simple desktop notification (via GM_notification if available) */
function notify(title, text) {
    if (typeof GM_notification === "function") {
        try { GM_notification({ title, text, timeout: 4000 }); return; } catch (e) { /* fallback */ }
    }
    // regular Notification
    if (window.Notification && Notification.permission === "granted") {
        new Notification(title, { body: text });
    } else if (window.Notification && Notification.permission !== "denied") {
        Notification.requestPermission().then(p => { if (p === "granted") new Notification(title, { body: text }); });
    } else {
        console.log(`[Chat Summarizer] ${title} — ${text}`);
    }
}

/* UI: create a small floating control panel */
function createControlPanel() {
    const panel = document.createElement('div');
    panel.id = 'chat-summarizer-panel';
    Object.assign(panel.style, {
        position: 'fixed',
        right: '14px',
        bottom: '14px',
        width: '260px',
        zIndex: 999999,
        fontFamily: 'system-ui, Arial, sans-serif',
        fontSize: '13px',
        color: '#111',
        background: 'linear-gradient(180deg, #ffffff, #f4f4f4)',
        border: '1px solid #ddd',
        borderRadius: '10px',
        boxShadow: '0 6px 18px rgba(0,0,0,0.08)',
        padding: '10px'
    });

    panel.innerHTML = `
    <div style="font-weight:600;margin-bottom:6px">Chat Summarizer</div>
    <div style="margin-bottom:6px"><span id="cs-count">Messages: 0</span></div>
    <div style="display:flex;gap:6px;margin-bottom:6px">
      <button id="cs-summarize" style="flex:1;padding:6px;border-radius:6px">Summarize now</button>
      <button id="cs-copy" style="flex:1;padding:6px;border-radius:6px">Copy</button>
    </div>
    <div style="display:flex;gap:6px;margin-bottom:6px">
      <label style="flex:1"><input id="cs-auto" type="checkbox"> Auto</label>
      <label style="flex:1"><input id="cs-auto-create" type="checkbox"> Auto new chat</label>
    </div>
    <div style="font-size:12px;color:#444">Last summary: <span id="cs-last">—</span></div>
  `;

    document.body.appendChild(panel);

    // Wire controls
    panel.querySelector('#cs-summarize').addEventListener('click', () => runSummarization({ manualTrigger: true }));
    panel.querySelector('#cs-copy').addEventListener('click', () => {
        if (window.__lastSummary) { copyToClipboard(window.__lastSummary); notify("Summary copied", "Summary copied to clipboard."); }
        else notify("No summary", "There is no summary yet.");
    });

    const autoBox = panel.querySelector('#cs-auto');
    const autoCreateBox = panel.querySelector('#cs-auto-create');

    // initialize with defaults
    autoBox.checked = false;
    autoCreateBox.checked = !!CONFIG.AUTO_CREATE_NEW_CHAT;

    // persist toggle in-memory
    window.__cs_auto = autoBox.checked;
    window.__cs_autoCreate = autoCreateBox.checked;

    autoBox.addEventListener('change', () => { window.__cs_auto = autoBox.checked; });
    autoCreateBox.addEventListener('change', () => { window.__cs_autoCreate = autoCreateBox.checked; });

    return panel;
}

/* Run summarization pipeline */
async function runSummarization({ manualTrigger = false } = {}) {
    try {
        const msgEls = getMessageElements();
        const count = msgEls.length;
        const statusEl = document.querySelector('#cs-count');
        if (statusEl) statusEl.innerText = `Messages: ${count}`;

        if (!manualTrigger && !window.__cs_auto) return;

        if (!manualTrigger && count < CONFIG.MESSAGE_THRESHOLD) return;

        // collect
        const text = collectRecentText();
        if (!text || text.trim().length === 0) { notify("No text found", "Could not extract text from chat messages."); return; }

        // summarize
        const summary = buildSummaryFromText(text, CONFIG.SUMMARY_SENTENCES);
        window.__lastSummary = summary;

        // update UI
        const lastEl = document.querySelector('#cs-last');
        if (lastEl) lastEl.innerText = summary.length > 120 ? (summary.slice(0, 120) + '…') : summary;

        // copy to clipboard
        copyToClipboard(summary);
        notify("Summary ready", "Summary created and copied to clipboard.");

        // optionally open a new chat and paste into input (if user enabled)
        const shouldAutoCreate = !!window.__cs_autoCreate;
        if (shouldAutoCreate) {
            const opened = tryOpenNewChat();
            // give the new chat UI time to appear
            setTimeout(() => {
                const pasted = tryPasteIntoInput(`System: ${summary}`);
                if (pasted) notify("Pasted into new chat", "Summary inserted into new chat input (not sent).");
                else notify("Paste failed", "Could not paste into input; summary is on clipboard.");
            }, CONFIG.NEW_CHAT_PASTE_DELAY_MS);
        }
    } catch (err) {
        console.error("Chat Summarizer error:", err);
        notify("Summarizer error", String(err));
    }
}

/* MutationObserver to watch for changes and auto-trigger */
function setupObserver() {
    const potentialContainer = document.querySelector('main') || document.body;
    if (!potentialContainer) return;

    const observer = new MutationObserver(() => {
        const els = getMessageElements();
        const count = els.length;
        const statusEl = document.querySelector('#cs-count');
        if (statusEl) statusEl.innerText = `Messages: ${count}`;

        if (window.__cs_auto && count >= CONFIG.MESSAGE_THRESHOLD) {
            // prevent repeated triggers
            if (!window.__cs_recentlyTriggered) {
                window.__cs_recentlyTriggered = true;
                runSummarization({ manualTrigger: false });
                // cooldown
                setTimeout(() => { window.__cs_recentlyTriggered = false; }, 30_000);
            }
        }
    });

    observer.observe(potentialContainer, { childList: true, subtree: true });
    return observer;
}

/* Initialize script: create UI and observer */
(function init() {
    try {
        // attach only once
        if (document.getElementById('chat-summarizer-panel')) return;
        createControlPanel();

        // set default flags from CONFIG
        window.__cs_auto = false;
        window.__cs_autoCreate = !!CONFIG.AUTO_CREATE_NEW_CHAT;

        // initial population of count
        const els = getMessageElements();
        const statusEl = document.querySelector('#cs-count');
        if (statusEl) statusEl.innerText = `Messages: ${els.length}`;

        setupObserver();

        // allow manual immediate run after UI loads
        setTimeout(() => {
            notify("Chat Summarizer ready", "Script loaded. Press 'Summarize now' or enable 'Auto'.");
        }, 500);
    } catch (e) {
        console.error("Failed to initialize Chat Summarizer:", e);
    }
})();
