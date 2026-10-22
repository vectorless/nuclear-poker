// Visual check: stage interesting game states via the debug hook and screenshot them.
const { chromium } = require('playwright');
const path = require('path');
const FILE = 'file://' + path.resolve(__dirname, '../nuclear-poker.html');
const OUT = '/tmp/shots2'; require('fs').mkdirSync(OUT, { recursive: true });

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1360, height: 900 } })).newPage();
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.goto(FILE);
  await page.check('input[name=mode][value="slow"]');
  await page.check('input[name=bio][value="2035"]');
  await page.selectOption('#p1', 'hawk'); await page.selectOption('#p2', 'dove');
  await page.click('[data-act=start]');
  await page.waitForSelector('.hcard');
  // Stage: give the human a rich position and make it their war step; give AIs public info
  await page.evaluate(() => {
    const D = window.__NP_DEBUG, G = D.G, ME = D.ME;
    const take = key => { const all = [G.deck, ...G.players.map(p => p.hand)]; for (const arr of all) { const i = arr.findIndex(c => c.key === key); if (i >= 0) return arr.splice(i, 1)[0]; } };
    ['uranium', 'refinement', 'warhead', 'testing', 'short', 'long', 'labs', 'plague'].forEach(k => { const c = take(k); if (c) ME.hand.push(c); });
    const a = G.players[1], b = G.players[2];
    ['uranium', 'refinement', 'warhead', 'testing'].forEach(k => { const c = take(k); if (c) { c.pub = true; a.table.push(c); } }); a.tested = true;
    const s = take('short'); if (s) { s.pub = true; a.hand.push(s); }
    G.turn = 0; G.phase = 'play'; G.intChecked = true;
    D.pump();
  });
  await page.waitForTimeout(400);
  await page.screenshot({ path: OUT + '/1-board.png' });
  // card popup
  await page.click('.hcard:nth-child(5)');
  await page.waitForTimeout(200);
  await page.screenshot({ path: OUT + '/2-popup.png' });
  await page.mouse.click(700, 840);
  // move to war step and open attack picker
  await page.evaluate(() => { const D = window.__NP_DEBUG, G = D.G; G.phase = 'war'; D.pump(); });
  await page.waitForTimeout(300);
  await page.click('.actionbar [data-act=test]');   // perform test
  await page.waitForTimeout(1800);
  await page.evaluate(() => { const D = window.__NP_DEBUG, G = D.G; G.turn = 0; G.phase = 'war'; G.intChecked = true; D.pump(); });
  await page.waitForTimeout(300);
  await page.click('.actionbar [data-act=attack]');
  await page.waitForTimeout(300);
  await page.screenshot({ path: OUT + '/3-attack-picker.png' });
  await page.keyboard.press('Escape');
  console.log(errs.length ? 'ERRORS ' + errs.join(' | ') : 'no page errors');
  await browser.close();
})();

// ---- second pass: fog modal, fast-mode superpower bar + peek, end modal, rules ----
(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1360, height: 900 } })).newPage();
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.goto(FILE);
  await page.check('input[name=mode][value="fog"]'); await page.check('input[name=bio][value="off"]');
  await page.selectOption('#p1', 'hawk'); await page.selectOption('#p2', 'wild');
  await page.click('[data-act=start]');
  await page.waitForSelector('.hcard');
  await page.evaluate(() => {
    const D = window.__NP_DEBUG, G = D.G, ME = D.ME;
    const take = key => { const all = [G.deck, ...G.players.map(p => p.hand)]; for (const arr of all) { const i = arr.findIndex(c => c.key === key); if (i >= 0) return arr.splice(i, 1)[0]; } };
    ['uranium', 'refinement', 'warhead', 'testing', 'short'].forEach(k => { const c = take(k); if (c) ME.hand.push(c); });
    G.turn = 0; G.phase = 'play'; G.intChecked = true; D.pump();
  });
  await page.click('[data-act=research]');                 // play action -> fog begins -> modal opens for the human
  await page.waitForSelector('.modal [data-act=fogsubmit]', { timeout: 8000 });
  await page.screenshot({ path: OUT + '/4-fog-modal.png' });
  await page.click('.modal [data-act=fogsubmit][data-kind=test]');
  await page.waitForTimeout(2500);
  await page.screenshot({ path: OUT + '/5-after-fog.png' });
  for (let k = 0; k < 6; k++) { // Fog re-prompts after every turn; hold until we can open Rules
    const hold = await page.$('.modal [data-act=fogsubmit][data-kind=pass]');
    if (!hold) break;
    await hold.click(); await page.waitForTimeout(1800);
  }
  await page.click('#topbar [data-act=rules]'); await page.waitForTimeout(250);
  await page.screenshot({ path: OUT + '/6-rules.png' });
  await page.keyboard.press('Escape');
  // end modal
  await page.evaluate(() => { const D = window.__NP_DEBUG, G = D.G; window.NP.proposeCeasefire(G, D.ME); if (!G.over) window.NP.endGame(G, 'ceasefire'); D.pump(); });
  await page.waitForSelector('.modal h2', { timeout: 5000 }); await page.waitForTimeout(300);
  await page.screenshot({ path: OUT + '/7-end.png' });
  console.log(errs.length ? 'ERRORS2 ' + errs.join(' | ') : 'no page errors (pass 2)');
  await browser.close();
})();
