const { chromium } = require('playwright');
const path = require('path');
const FILE = 'file://' + path.resolve(__dirname, '../nuclear-poker.html');
(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1360, height: 900 } })).newPage();
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.goto(FILE);
  await page.check('input[name=mode][value="fast"]'); await page.check('input[name=bio][value="off"]');
  await page.selectOption('#p1', 'dove'); await page.selectOption('#p2', 'dove');
  await page.click('[data-act=start]'); await page.waitForSelector('.hcard');
  // Give the human a tested Superpower position; make AIs inert-ish by clearing their hands of attack cards.
  await page.evaluate(() => {
    const D = window.__NP_DEBUG, G = D.G, ME = D.ME;
    const take = key => { const all = [G.deck, ...G.players.map(p => p.hand)]; for (const arr of all) { const i = arr.findIndex(c => c.key === key); if (i >= 0) return arr.splice(i, 1)[0]; } };
    ['short', 'long', 'counter', 'super'].forEach(k => { const c = take(k); if (c) ME.hand.push(c); });
    ['uranium', 'refinement', 'warhead', 'testing'].forEach(k => { const c = take(k); if (c) ME.hand.push(c); });
    G.turn = 0; G.phase = 'play'; G.intChecked = true; D.pump();
  });
  const results = {};
  results.fastbar = !!(await page.$('.fastbar'));
  results.testEnabled = !!(await page.$('.fastbar [data-act=test]:not([disabled])'));
  results.peekHiddenBeforeTest = !(await page.$('.fastbar [data-act=peek]'));
  // Out-of-turn instant Nuclear Test (Fast: allowed at any time, even though it's already my play phase)
  await page.click('.fastbar [data-act=test]');
  await page.waitForTimeout(300);
  results.tested = await page.evaluate(() => window.__NP_DEBUG.ME.tested);
  results.peekVisible = !!(await page.$('.fastbar [data-act=peek]'));
  await page.click('.fastbar [data-act=peek]');
  await page.waitForSelector('.modal .peek');
  results.peekShowsTwoHands = (await page.$$('.modal .peek .box')).length === 2;
  const pausedDuring = await page.evaluate(() => window.__NP_DEBUG.ui.paused);
  results.pausedDuringPeek = pausedDuring > 0;
  await page.screenshot({ path: '/tmp/shots2/8-peek.png' });
  await page.click('.modal [data-act=closeModal]');
  results.resumed = (await page.evaluate(() => window.__NP_DEBUG.ui.paused)) === 0;
  // Instant attack out of turn
  await page.click('.fastbar [data-act=attack]');
  await page.waitForSelector('.modal [data-act=launch]');
  await page.click('.modal [data-act=launch][data-type=short]');   // short-range on a neighbor
  await page.waitForTimeout(400);
  results.someoneDied = await page.evaluate(() => window.__NP_DEBUG.G.players.some(p => !p.alive));
  console.log(JSON.stringify(results), errs.length ? 'ERRORS ' + errs.join('|') : 'no page errors');
  await browser.close();
})();
