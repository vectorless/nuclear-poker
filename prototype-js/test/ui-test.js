// Real-browser smoke test: plays full games as the human through DOM clicks in every WAR mode.
const { chromium } = require('playwright');
const path = require('path');
const FILE = 'file://' + path.resolve(__dirname, '../nuclear-poker.html');
const OUT = process.env.OUT || '/tmp/shots';
require('fs').mkdirSync(OUT, { recursive: true });

async function playGame(browser, mode, bio, shotTag) {
  const ctx = await browser.newContext({ viewport: { width: 1360, height: 860 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/fonts\.g|ERR_|Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
  page.on('dialog', d => d.accept());
  await page.goto(FILE);
  if (shotTag === 'first') await page.screenshot({ path: `${OUT}/menu.png` });
  await page.check(`input[name=mode][value="${mode}"]`);
  await page.check(`input[name=bio][value="${bio}"]`);
  await page.click('[data-act=start]');
  await page.waitForSelector('#board .me');
  let iter = 0, shots = 0, acts = { research: 0, test: 0, attack: 0, give: 0, ret: 0, stand: 0, fog: 0, counter: 0 };
  const t0 = Date.now();
  while (iter++ < 600 && Date.now() - t0 < 150000) {
   try {
    // game over?
    if (await page.$('.modal h2') && /standing|annihilation|Deterrence|Stand-down/i.test(await page.textContent('.modal h2'))) break;
    // counter-strike prompt
    const ctr = await page.$('[data-act=counter]');
    if (ctr) { await ctr.click(); acts.counter++; continue; }
    // fog modal
    const fogAtk = await page.$('.modal [data-act=launch]');
    const fogTest = await page.$('.modal [data-act=fogsubmit][data-kind=test]');
    if (await page.$('.modal [data-act=fogsubmit]')) {
      if (fogAtk && Math.random() < 0.7) { await fogAtk.click(); }
      else if (fogTest) { await fogTest.click(); }
      else { await page.click('.modal [data-act=fogsubmit][data-kind=pass]'); }
      acts.fog++; continue;
    }
    // non-pausing attack picker left open? close it
    const research = await page.$('[data-act=research]:not([disabled])');
    const stand = await page.$('[data-act=stand]');
    if (stand) {
      const test = await page.$('.actionbar [data-act=test]:not([disabled])');
      const atk = await page.$('.actionbar [data-act=attack]:not([disabled])');
      if (atk) {
        await atk.click();
        const l = await page.$('.modal [data-act=launch]');
        if (l) { await l.click(); acts.attack++; continue; }
      }
      if (test) { await test.click(); acts.test++; continue; }
      await stand.click(); acts.stand++; continue;
    }
    if (research) {
      if (shots < 1 && iter > 6) { await page.screenshot({ path: `${OUT}/${mode}-${bio}-board.png` }); shots++; }
      // occasionally give or return a card via the card popup
      const r = Math.random();
      if (r < 0.2) {
        const card = await page.$('.hcard');
        if (card) {
          await card.click();
          const g = await page.$('.pop [data-act=give]'); const rt = await page.$('.pop [data-act=ret]');
          if (g && r < 0.1) { await g.click(); acts.give++; continue; }
          if (rt) { await rt.click(); acts.ret++; continue; }
        }
      }
      await research.click(); acts.research++; continue;
    }
    await page.waitForTimeout(120);
   } catch (e) { if (/closed|Target/.test(e.message)) throw e; await page.waitForTimeout(80); /* DOM re-rendered under us (Fast mode): retry */ }
  }
  const over = await page.$('.modal h2');
  const title = over ? await page.textContent('.modal h2') : '(no end modal)';
  await page.screenshot({ path: `${OUT}/${mode}-${bio}-end.png` });
  const logTail = (await page.$$eval('#log div', els => els.slice(-6).map(e => e.textContent))).join(' | ');
  await ctx.close();
  return { mode, bio, iter, acts, title: title.trim(), errors, logTail: logTail.slice(0, 260) };
}

(async () => {
  const browser = await chromium.launch();
  let bad = 0;
  const runs = [['slow', 'off'], ['fog', 'off'], ['fast', 'off'], ['slow', '2035'], ['fog', '2000']];
  for (let i = 0; i < runs.length; i++) {
    const [m, b] = runs[i];
    const r = await playGame(browser, m, b, i === 0 ? 'first' : '');
    console.log(JSON.stringify(r));
    if (r.errors.length || r.title === '(no end modal)') bad++;
  }
  await browser.close();
  console.log(bad ? `PROBLEMS: ${bad}` : 'UI SMOKE OK');
  process.exit(bad ? 1 : 0);
})();
