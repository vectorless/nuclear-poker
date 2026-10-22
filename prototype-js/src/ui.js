/* Nuclear Poker — browser UI. Talks to window.NP (engine.js) and window.CARD_IMG (card art). */
(function () {
  'use strict';
  const NPE = window.NP, IMG = window.CARD_IMG || {}, INFO = NPE.INFO;
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  let G = null, ME = null;
  const ui = { paused: 0, pumpT: null, autoT: null, fastT: {}, endShown: false, fogOpen: false, muted: false, ff: false, fresh: new Set(), modal: null };

  /* ------------------------------------------------------------------ settings */
  const DEFAULTS = { name: 'You', mode: 'slow', bio: 'off', p1: 'random', p2: 'random' };
  let cfg = Object.assign({}, DEFAULTS);
  try { cfg = Object.assign(cfg, JSON.parse(localStorage.getItem('nuclearpoker.cfg') || '{}')); } catch (e) { /* ignore */ }
  const saveCfg = () => { try { localStorage.setItem('nuclearpoker.cfg', JSON.stringify(cfg)); } catch (e) { /* ignore */ } };

  /* ------------------------------------------------------------------ sound (tiny, procedural) */
  let ac = null;
  function snd(kind) {
    if (ui.muted) return;
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      const t = ac.currentTime, o = ac.createOscillator(), g = ac.createGain();
      o.connect(g); g.connect(ac.destination);
      const env = (v, d) => { g.gain.setValueAtTime(v, t); g.gain.exponentialRampToValueAtTime(0.001, t + d); o.start(t); o.stop(t + d); };
      if (kind === 'test') { o.type = 'sawtooth'; o.frequency.setValueAtTime(110, t); o.frequency.exponentialRampToValueAtTime(28, t + 1); env(0.22, 1); }
      else if (kind === 'attack') { o.type = 'square'; o.frequency.setValueAtTime(1000, t); o.frequency.exponentialRampToValueAtTime(160, t + 0.7); env(0.12, 0.8); }
      else if (kind === 'death') { o.type = 'sine'; o.frequency.setValueAtTime(160, t); o.frequency.exponentialRampToValueAtTime(40, t + 1.2); env(0.3, 1.3); }
      else { o.type = 'triangle'; o.frequency.setValueAtTime(520, t); env(0.06, 0.12); }
    } catch (e) { /* audio unavailable */ }
  }

  /* ------------------------------------------------------------------ small helpers */
  function toast(msg, ms) {
    const el = document.createElement('div');
    el.className = 'toast'; el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), ms || 2600);
  }
  function fx(text, cls) {
    const el = document.createElement('div');
    el.className = 'fx ' + cls; el.innerHTML = `<span>${esc(text)}</span>`;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 1700);
  }
  function setPause(on) { ui.paused = Math.max(0, ui.paused + (on ? 1 : -1)); }
  function openModal(html, opts) {
    closeModal(true);
    opts = opts || {};
    const back = document.createElement('div');
    back.className = 'scrim'; back.id = 'modal-back';
    back.innerHTML = `<div class="modal" role="dialog">${html}</div>`;
    if (!opts.sticky) back.addEventListener('mousedown', e => { if (e.target === back) closeModal(); });
    $('#overlay').appendChild(back);
    ui.modal = { pause: !!opts.pause, onClose: opts.onClose };
    if (opts.pause) setPause(true);
  }
  function closeModal(silent) {
    const b = $('#modal-back');
    if (b) b.remove();
    if (ui.modal) {
      if (ui.modal.pause) setPause(false);
      const cb = ui.modal.onClose; ui.modal = null;
      if (cb && !silent) cb();
    }
    ui.fogOpen = false;
  }
  function closePop() { const p = $('.pop'); if (p) p.remove(); $$('.hcard.open').forEach(e => e.classList.remove('open')); }

  const img = (key, cls) => `<img class="${cls || 'mini'}" src="${IMG[key] || ''}" alt="${esc(INFO[key].name)}" title="${esc(INFO[key].name)}" draggable="false">`;

  /* ------------------------------------------------------------------ MENU */
  function initMenu() {
    const opts = '<option value="random">Random</option>' + Object.values(NPE.PERSONAS).map(p => `<option value="${p.id}">${esc(p.name)} — ${esc(p.title)}</option>`).join('');
    $('#p1').innerHTML = opts; $('#p2').innerHTML = opts;
    $('#p1').value = cfg.p1; $('#p2').value = cfg.p2; $('#pname').value = cfg.name;
    $$('input[name=mode]').forEach(r => { r.checked = r.value === cfg.mode; });
    $$('input[name=bio]').forEach(r => { r.checked = r.value === cfg.bio; });
    const sync = () => $$('.opt').forEach(o => o.classList.toggle('sel', o.querySelector('input').checked));
    $$('.opt input').forEach(r => r.addEventListener('change', sync));
    sync();
    $('#strip').innerHTML = ['uranium', 'refinement', 'warhead', 'testing', 'short', 'long', 'counter', 'super', 'labs', 'plague'].map(k => `<img src="${IMG[k] || ''}" alt="${esc(INFO[k].name)}" title="${esc(INFO[k].name)}">`).join('');
  }
  function readMenu() {
    cfg.name = ($('#pname').value || 'You').trim().slice(0, 18) || 'You';
    cfg.mode = ($('input[name=mode]:checked') || {}).value || 'slow';
    cfg.bio = ($('input[name=bio]:checked') || {}).value || 'off';
    cfg.p1 = $('#p1').value; cfg.p2 = $('#p2').value;
    saveCfg();
  }

  function rulesHTML() {
    const cards = ['uranium', 'refinement', 'warhead', 'testing', 'short', 'long', 'counter', 'super', 'labs', 'plague'];
    return `
      <button class="btn sm close" data-act="closeModal">Close ✕</button>
      <h2>How to play</h2>
      <p>Nuclear Poker teaches the logic of nuclear deterrence. There is <b>no victory rule</b> — play until someone is the last power standing, or everyone agrees to stop.</p>
      <h3 style="color:var(--amber);margin:12px 0 4px">Your turn</h3>
      <ul>
        <li><b>Research</b> — draw a card. <b>Proliferation</b> — give a card from your hand to another player. <b>Disarmament</b> — return a card to the deck. (Click a card in your hand to give or return it.)</li>
        <li>Then the <b>WAR rules</b> decide what else you can do: <b>Slow</b> — after your play action you may do nothing, a <b>Nuclear Test</b>, or an <b>Attack</b>. <b>Fog</b> — after each turn everyone secretly picks an order and all resolve at once. <b>Fast</b> — anyone may Test or Attack at any time, in real time.</li>
      </ul>
      <h3 style="color:var(--amber);margin:12px 0 4px">Cards</h3>
      <ul>
        <li><b>Technologies</b> (grey): hold all four different — Uranium, Refinement, Warhead, Testing — and put them on the table to perform a <b>Nuclear Test</b>. You must test before any nuclear Attack.</li>
        <li><b>Short-range</b>: after a Test, eliminate a neighboring player. <b>Long-range</b> (needs Short): eliminate any player. <b>Counter-strike</b> (needs Short + Long): when you are eliminated, immediately eliminate one player. <b>Superpower</b> (needs all 4 Capabilities): attack any player <i>at any time</i> — and in Fast mode, pause the game and examine everyone's hands.</li>
        <li>Capabilities stay hidden until you use them; afterwards you keep and display them. You may also <b>reveal</b> a card from your hand as a deterrent — or hold back to bluff.</li>
        <li><b>Biowar</b>: <b>Labs</b> protect you from <b>Plague</b>; a Plague attack eliminates <i>all</i> players without Labs. In <b>2000</b> you need a Nuclear Test and all 4 Capabilities first; in <b>2035</b> you just show Labs and play it.</li>
      </ul>
      <div class="cardstrip">${cards.map(k => `<img src="${IMG[k] || ''}" alt="${esc(INFO[k].name)}">`).join('')}</div>
      <h3 style="color:var(--amber);margin:14px 0 4px">Rules as implemented here</h3>
      <ul>
        <li>A turn is one play action (Research / Proliferation / Disarmament), then the WAR step. 3 players ⇒ 4 sets of 8 cards (plus 4 Labs + 4 Plague with Biowar). Everyone starts with 3 cards.</li>
        <li>Cards on the table (tested Technologies, Capabilities you used in an attack) are locked and public. An attack shows the Capabilities it requires.</li>
        <li>In Fog, a Test and an Attack can't happen in the same round — an attack needs a Test that is already on the table at the start of the round. Simultaneous attacks all land, even from players who die that round.</li>
        <li>An eliminated player's hand is revealed and set aside. Returned cards are shuffled into the draw pile at a random position.</li>
        <li>"Neighbors" are the nearest living players on either side of you.</li>
      </ul>`;
  }

  /* ------------------------------------------------------------------ START */
  function start() {
    readMenu();
    const ids = Object.keys(NPE.PERSONAS);
    const pick = v => v === 'random' ? ids[Math.floor(Math.random() * ids.length)] : v;
    let a = pick(cfg.p1), b = pick(cfg.p2);
    if (a === b && (cfg.p1 === 'random' || cfg.p2 === 'random') && !(cfg.p1 !== 'random' && cfg.p2 !== 'random')) {
      let tries = 0; while (b === a && tries++ < 20) b = ids[Math.floor(Math.random() * ids.length)];
    }
    const nm = (id, dup) => NPE.PERSONAS[id].name + (dup ? ' II' : '');
    G = NPE.makeGame({
      mode: cfg.mode, bio: cfg.bio,
      players: [
        { name: cfg.name, human: true },
        { name: nm(a, false), persona: a },
        { name: nm(b, a === b), persona: b },
      ],
    });
    ME = G.players[0];
    ui.endShown = false; ui.ff = false; ui.fresh.clear(); ui.paused = 0;
    clearTimeout(ui.pumpT); clearTimeout(ui.autoT);
    hook();
    $('#menu').classList.add('hidden'); $('#game').classList.remove('hidden');
    closeModal(true); closePop();
    G.log.length = 0;
    NPE_sys(`Game on — ${G.mode.toUpperCase()} WAR${G.bio !== 'off' ? ' + BIOWAR ' + G.bio : ''}. ${G.players[G.turn].name} goes first.`);
    fastStart();
    pump();
  }
  function NPE_sys(text) { const e = { n: G.turnNo, text, tone: 'sys' }; G.log.push(e); }

  function hook() {
    G.on((t, d) => {
      if (t === 'test') { fx('☢ Nuclear Test', 'test'); snd('test'); fastReact(d.p); }
      else if (t === 'attack') { fx(d.type === 'plague' ? '☣ Plague' : '🚀 Launch Detected', 'attack'); snd('attack'); fastReact(d.attacker); }
      else if (t === 'death') {
        fx(d.p === ME ? 'You are eliminated' : d.p.name + ' eliminated', 'death'); snd('death');
        const b = $('#board'); if (b) { b.classList.remove('shake'); void b.offsetWidth; b.classList.add('shake'); }
      }
      else if (t === 'draw' && d.p === ME) ui.fresh.add(d.c.id);
      else if (t === 'give' && d.to === ME) ui.fresh.add(d.c.id);
    });
  }

  /* ------------------------------------------------------------------ DRIVER */
  const DELAY = { slow: 1050, fog: 950, fast: 1250 };
  function pump() {
    clearTimeout(ui.pumpT); clearTimeout(ui.autoT);
    if (!G) return;
    const st = NPE.status(G);
    render();
    if (st === 'over') { finish(); return; }
    if (st === 'prompt') { counterModal(); return; }
    if (st === 'human') { onHumanTurn(); return; }
    const delay = ME.alive ? DELAY[G.mode] : (ui.ff ? 40 : 260);
    ui.pumpT = setTimeout(() => {
      if (ui.paused) { pump(); return; }
      NPE.step(G); pump();
    }, delay);
  }
  function onHumanTurn() {
    if (G.phase === 'play') {
      const L = NPE.legal(G, ME, {});
      if (!L.canResearch && !ME.hand.length) ui.autoT = setTimeout(() => { if (G && NPE.cur(G) === ME && G.phase === 'play') { NPE.playSkip(G, ME); pump(); } }, 700);
    } else if (G.phase === 'war') {
      const L = NPE.legal(G, ME, {});
      if (!L.canTest && !L.attacks.length) {
        toast('No Test or Attack available — standing down.', 1400);
        ui.autoT = setTimeout(() => { if (G && NPE.cur(G) === ME && G.phase === 'war') { NPE.humanWar(G, { kind: 'pass' }); pump(); } }, 800);
      }
    } else if (G.phase === 'fog') {
      if (!ui.fogOpen && NPE.fogPending(G).includes(ME)) fogModal();
    }
  }

  /* Fast mode: AIs act on their own clocks. */
  function fastStart() {
    fastStop();
    if (G.mode !== 'fast') return;
    G.players.forEach(p => { if (!p.human) scheduleFast(p, 2500 + Math.random() * 3000); });
  }
  function fastStop() { Object.keys(ui.fastT).forEach(k => clearTimeout(ui.fastT[k])); ui.fastT = {}; }
  function scheduleFast(p, ms) { clearTimeout(ui.fastT[p.id]); ui.fastT[p.id] = setTimeout(() => fastTick(p), ms); }
  function fastTick(p) {
    if (!G || G.over || !p.alive || G.mode !== 'fast') return;
    if (ui.paused || G.prompt) { scheduleFast(p, 500); return; }
    const acted = NPE.aiFastTick(G, p);
    const r = p.persona.react;
    scheduleFast(p, (r[0] + Math.random() * (r[1] - r[0])) * 1000 + (acted ? 1200 : 0));
    if (acted) pump(); // only touch the DOM when something actually happened (keeps clicks reliable)
  }
  function fastReact(by) {
    if (!G || G.mode !== 'fast') return;
    G.players.forEach(p => {
      if (p.human || !p.alive || p === by) return;
      const r = p.persona.react;
      scheduleFast(p, (r[0] + Math.random() * (r[1] - r[0])) * 450);
    });
  }

  /* ------------------------------------------------------------------ RENDER */
  function render() {
    if (!G) return;
    renderTop(); renderBoard(); renderSide();
  }
  function renderTop() {
    const modeName = { slow: 'Slow WAR', fog: 'Fog WAR', fast: 'Fast WAR' }[G.mode];
    $('#topbar').innerHTML = `
      <span class="brand">Nuclear <span>Poker</span></span>
      <span class="chip hot">${modeName}</span>
      ${G.bio !== 'off' ? `<span class="chip hot">Biowar ${G.bio}</span>` : ''}
      <span class="chip">Round ${G.round}</span>
      <span class="chip">Deck ${G.deck.length}</span>
      <span class="spacer"></span>
      <button class="btn sm" data-act="ceasefire" ${G.over || !ME.alive ? 'disabled' : ''} title="Propose that everyone stops">Propose stand-down</button>
      <button class="btn sm" data-act="rules">Rules</button>
      <button class="btn sm" data-act="sound">${ui.muted ? '🔇' : '🔊'}</button>
      <button class="btn sm" data-act="menu">Menu</button>`;
  }

  function seatHTML(p) {
    const turn = G.turn === p.id && !G.over && p.alive;
    const unk = p.hand.filter(c => !c.pub), pubs = p.hand.filter(c => c.pub);
    const sealed = G.phase === 'fog' && G.fog && G.fog.choices[p.id] !== undefined && p.alive;
    const shownBacks = Math.min(unk.length, 14);
    const killer = p.eliminatedBy != null ? G.players[p.eliminatedBy].name : null;
    return `<div class="seat ${p.alive ? '' : 'dead'} ${turn ? 'turn' : ''}" data-pid="${p.id}">
      <div class="seat-head">
        <span class="nm">${esc(p.name)}</span>
        <span class="pt" style="color:${p.persona.color}">${esc(p.persona.title)}</span>
        ${p.tested ? '<span class="badge test">☢ TESTED</span>' : ''}
        ${sealed ? '<span class="badge seal">✉ order sealed</span>' : ''}
        ${p.alive ? '' : `<span class="badge">${killer ? 'killed by ' + esc(killer) : 'eliminated'}</span>`}
      </div>
      <div class="zone label" data-l="Hand · ${p.hand.length} card${p.hand.length === 1 ? '' : 's'}">
        ${Array.from({ length: shownBacks }, () => '<div class="mini back"></div>').join('')}
        ${unk.length > shownBacks ? `<span class="more">+${unk.length - shownBacks}</span>` : ''}
        ${pubs.map(c => img(c.key, 'mini pubc')).join('')}
      </div>
      <div class="zone label" data-l="On the table">
        ${p.table.length ? p.table.map(c => img(c.key)).join('') : '<span class="more">nothing yet</span>'}
      </div>
    </div>`;
  }

  function warText() {
    return {
      slow: '<b>Slow WAR</b><br>Each turn: play action, then no action / Test / Attack. Superpower may strike at any time.',
      fog: '<b>Fog WAR</b><br>After each turn all players secretly choose: no action / Test / Attack a named player. Resolved together.',
      fast: '<b>Fast WAR</b><br>Everyone may Test or Attack at any moment, in the order announced. Superpower can pause &amp; peek.',
    }[G.mode];
  }
  function bannerHTML() {
    if (G.over) return '<div class="banner">The game is over.</div>';
    if (!ME.alive) return `<div class="banner dead">You were eliminated. The game continues without you… <button class="btn sm" data-act="ff">Skip to end</button></div>`;
    const p = NPE.cur(G);
    if (G.phase === 'fog') {
      return NPE.fogPending(G).includes(ME)
        ? '<div class="banner you"><b>Fog of war.</b> Write down your order.</div>'
        : '<div class="banner">The fog gathers… orders are being written.</div>';
    }
    if (p === ME) {
      return G.phase === 'play'
        ? '<div class="banner you"><b>Your turn.</b> Research a card — or click a card in your hand to give it away or return it.</div>'
        : '<div class="banner you"><b>War step.</b> Stand down, perform a Nuclear Test, or Attack.</div>';
    }
    return `<div class="banner">${esc(p.name)} is ${G.phase === 'war' ? 'weighing the war step' : 'thinking'}…</div>`;
  }

  const ORDER = NPE.TECH.concat(NPE.CAPS, NPE.BIO);
  function handHTML() {
    return ME.hand.slice().sort((a, b) => ORDER.indexOf(a.key) - ORDER.indexOf(b.key) || a.id - b.id).map(c => `<div class="hcard ${c.pub ? 'pub' : ''} ${ui.fresh.has(c.id) ? 'fresh' : ''}" data-act="card" data-cid="${c.id}">${img(c.key, '')}</div>`).join('');
  }
  function actionBarHTML() {
    if (G.over) return '';
    if (!ME.alive) return '<div class="actionbar"><span class="hint">Spectating.</span></div>';
    const myTurn = NPE.cur(G) === ME;
    const L = NPE.legal(G, ME, {});
    let h = '';
    if (G.phase === 'play' && myTurn) {
      h = `<button class="btn primary" data-act="research" ${L.canResearch ? '' : 'disabled'}>Research — draw a card</button>
           <span class="hint">${L.canResearch ? 'or click a card in your hand to give / return it' : 'The deck is empty — give or return a card.'}</span>
           ${!L.canResearch && !ME.hand.length ? '<button class="btn" data-act="skip">Skip</button>' : ''}`;
    } else if (G.phase === 'war' && myTurn) {
      h = `<button class="btn" data-act="stand">Stand down</button>
           <button class="btn" data-act="test" ${L.canTest ? '' : 'disabled'}>☢ Nuclear Test</button>
           <button class="btn danger" data-act="attack" data-mode="turn" ${L.attacks.length ? '' : 'disabled'}>🚀 Attack…</button>
           <span class="hint">choose one</span>`;
    } else if (G.phase === 'fog' && NPE.fogPending(G).includes(ME)) {
      h = '<button class="btn primary" data-act="fogopen">Write down your order</button>';
    } else {
      h = `<span class="hint">Waiting for ${esc(NPE.cur(G).name)}…</span>`;
    }
    let extra = '';
    if (G.mode === 'fast') {
      const F = NPE.legal(G, ME, { interrupt: true });
      extra = `<div class="fastbar"><span class="lbl">⚡ Fast WAR — act any time</span>
        <button class="btn sm" data-act="test" ${F.canTest ? '' : 'disabled'}>☢ Nuclear Test</button>
        <button class="btn sm danger" data-act="attack" data-mode="interrupt" ${F.attacks.length ? '' : 'disabled'}>🚀 Attack…</button>
        ${F.canPeek ? '<button class="btn sm" data-act="peek">👁 Superpower: examine hands</button>' : ''}</div>`;
    } else {
      const F = NPE.legal(G, ME, { interrupt: true });
      if (F.attacks.length && !(G.phase === 'war' && myTurn)) {
        extra = `<div class="fastbar"><span class="lbl">Superpower</span><span class="hint">You may attack any player at any time.</span>
          <button class="btn sm danger" data-act="attack" data-mode="interrupt">🚀 Attack…</button></div>`;
      }
    }
    return `<div class="actionbar">${h}</div>${extra}`;
  }

  function renderBoard() {
    const board = $('#board');
    const myTurn = !G.over && ME.alive && (NPE.cur(G) === ME || (G.phase === 'fog' && NPE.fogPending(G).includes(ME)));
    board.innerHTML = `
      <div class="opps">${seatHTML(G.players[1])}${seatHTML(G.players[2])}</div>
      <div class="centerband">
        <div class="pile">
          <div class="stack"><div class="mini back"></div><div class="mini back"></div><div class="mini back"></div></div>
          <div class="pilelabel">Draw pile<b>${G.deck.length}</b></div>
          <div class="pilelabel">Set aside<b>${G.out.length}</b></div>
        </div>
        ${bannerHTML()}
        <div class="warcard">${warText()}</div>
      </div>
      <div class="me ${myTurn ? 'turn' : ''}">
        <div class="seat-head">
          <span class="nm">${esc(ME.name)}</span><span class="pt" style="color:var(--green)">You</span>
          ${ME.tested ? '<span class="badge test">☢ TESTED</span>' : ''}
          ${ME.alive ? '' : '<span class="badge">eliminated</span>'}
          <span class="spacer"></span><span class="pt" style="color:var(--mut)">${ME.hand.length} in hand</span>
        </div>
        ${ME.table.length ? `<div class="me-table" title="Cards on your table (locked, public)">${ME.table.map(c => img(c.key, 'tablecard')).join('')}</div>` : ''}
        <div class="hand">${handHTML()}</div>
        ${actionBarHTML()}
      </div>`;
    ui.fresh.clear();
    fitHand();
  }
  function fitHand() {
    const hand = $('.hand');
    if (!hand) return;
    const cards = $$('.hcard', hand), n = cards.length;
    if (n < 2) return;
    const cw = cards[0].offsetWidth, W = hand.clientWidth - 48, base = cw * 0.22;
    let overlap = base;
    if (n * cw - (n - 1) * base > W) overlap = (n * cw - W) / (n - 1);
    overlap = Math.min(overlap, cw * 0.7);
    cards.forEach((c, i) => { c.style.marginLeft = i ? (-overlap) + 'px' : '0'; });
  }

  function arsenalHTML() {
    const tested = ME.tested;
    const t = NPE.TECH.map(k => {
      const have = NPE.holds(ME, k);
      return `<span class="${have ? 'ok' : 'no'}">${have ? '✔' : '✘'} ${INFO[k].name}</span>`;
    }).join('');
    const pre = { short: tested, long: tested && NPE.holds(ME, 'short'), counter: tested && NPE.holds(ME, 'short') && NPE.holds(ME, 'long'), super: tested && NPE.hasAllCaps(ME) };
    const c = NPE.CAPS.map(k => {
      const have = NPE.holds(ME, k);
      const cls = have && pre[k] ? 'ok' : have ? 'part' : 'no';
      const mark = have && pre[k] ? '✔ armed' : have ? '· held' : '✘';
      return `<span class="${cls}">${INFO[k].name}: ${mark}</span>`;
    }).join('');
    const bio = G.bio === 'off' ? '' : `<span class="${NPE.holds(ME, 'labs') ? 'ok' : 'no'}">Labs ${NPE.holds(ME, 'labs') ? '✔' : '✘'}</span><span class="${NPE.holds(ME, 'plague') ? 'ok' : 'no'}">Plague ${NPE.holds(ME, 'plague') ? '✔' : '✘'}</span>`;
    const need = NPE.TECH.filter(k => !NPE.holds(ME, k)).length;
    const foot = tested ? '<span class="full">☢ Nuclear Test done — Capabilities you hold are armed.</span>'
      : NPE.canTest(G, ME) ? '<span class="full ok">You hold all four Technologies — you can perform a Nuclear Test!</span>'
        : `<span class="full">${need} Technolog${need === 1 ? 'y' : 'ies'} short of a Nuclear Test.</span>`;
    return `<h3>Your arsenal</h3><div class="ars">${t}${c}${bio}${foot}</div>`;
  }
  function renderSide() {
    $('#arsenal').innerHTML = arsenalHTML();
    const log = $('#log');
    const stick = log.scrollTop + log.clientHeight >= log.scrollHeight - 40 || !log.childElementCount;
    log.innerHTML = G.log.slice(-140).map(e => `<div class="${e.tone}">${esc(e.text)}</div>`).join('');
    if (stick) log.scrollTop = log.scrollHeight;
  }

  /* ------------------------------------------------------------------ INTERACTION */
  const CARD_DESC = {
    uranium: 'Technology. Hold all four different Technologies to perform a Nuclear Test.',
    refinement: 'Technology. Hold all four different Technologies to perform a Nuclear Test.',
    warhead: 'Technology. Hold all four different Technologies to perform a Nuclear Test.',
    testing: 'Technology. Hold all four different Technologies to perform a Nuclear Test.',
    short: 'Needs a Nuclear Test. Attack: eliminate one neighboring player.',
    long: 'Needs Nuclear Test + Short-range. Attack: eliminate any one player.',
    counter: 'Needs Nuclear Test + Short + Long. When you are eliminated, eliminate one player.',
    super: 'Needs Nuclear Test + all 4 Capabilities. Attack any player at any time.',
    labs: 'Biotech. Enables and protects against Plague attacks.',
    plague: 'Biotech. Requires Labs. Attack: eliminate all players without Labs.',
  };
  function openCardMenu(cid, el) {
    closePop();
    const c = ME.hand.find(x => x.id === +cid);
    if (!c) return;
    const myPlay = G && !G.over && ME.alive && NPE.cur(G) === ME && G.phase === 'play';
    let btns = '';
    if (!c.pub) btns += `<button class="btn" data-act="reveal" data-cid="${c.id}">👁 Reveal to everyone</button>`;
    if (myPlay) {
      NPE.others(G, ME).forEach(o => { btns += `<button class="btn" data-act="give" data-cid="${c.id}" data-tid="${o.id}">→ Give to ${esc(o.name)}</button>`; });
      btns += `<button class="btn" data-act="ret" data-cid="${c.id}">↩ Return to deck</button>`;
    }
    const pop = document.createElement('div');
    pop.className = 'pop';
    pop.innerHTML = `<div class="ti">${esc(INFO[c.key].name)}</div><div class="ds">${esc(CARD_DESC[c.key])}</div>${btns || '<div class="ds">Nothing to do with this card right now.</div>'}`;
    document.body.appendChild(pop);
    const r = el.getBoundingClientRect(), pw = pop.offsetWidth, ph = pop.offsetHeight;
    pop.style.left = Math.max(8, Math.min(window.innerWidth - pw - 8, r.left + r.width / 2 - pw / 2)) + 'px';
    pop.style.top = Math.max(8, r.top - ph - 24) + 'px';
    el.classList.add('open');
  }

  function attackLabel(type) {
    return {
      short: ['Short-range strike', 'Eliminates one neighboring player.'],
      long: ['Long-range strike', 'Eliminates any one player.'],
      super: ['Superpower strike', 'Eliminates any one player — usable at any time.'],
      plague: ['Plague', 'Eliminates ALL players without Labs. You are protected by your own Labs.'],
    }[type];
  }
  function attackListHTML(L, mode) {
    return L.attacks.map(a => {
      const [t, d] = attackLabel(a.type);
      const tg = a.type === 'plague'
        ? `<button class="btn danger" data-act="launch" data-mode="${mode}" data-type="plague">☣ Release Plague</button>`
        : a.targets.map(id => `<button class="btn danger" data-act="launch" data-mode="${mode}" data-type="${a.type}" data-tid="${id}">🎯 ${esc(G.players[id].name)}</button>`).join(' ');
      const cost = a.type === 'plague' ? '' : ' <span class="hint" style="color:var(--mut)">(shows the Capabilities it needs)</span>';
      return `<div class="atk"><div class="t">${t}</div><div class="d">${d}${cost}</div>${tg}</div>`;
    }).join('');
  }
  function attackModal(mode) {
    const L = NPE.legal(G, ME, { interrupt: mode === 'interrupt' });
    if (!L.attacks.length) { toast('No attacks available.'); return; }
    openModal(`<button class="btn sm close" data-act="closeModal">Cancel</button><h2 class="red">Choose your attack</h2>
      <p>This cannot be undone.</p>${attackListHTML(L, mode)}`, { pause: true });
  }
  function fogModal() {
    ui.fogOpen = true;
    const L = NPE.legal(G, ME, {});
    openModal(`<h2>Fog of war — write down your order</h2>
      <p>Everyone (including the AIs) writes one order. When all are in, they are revealed and resolve <b>simultaneously</b>. An attack needs a Nuclear Test that is already on the table.</p>
      <div class="atk"><div class="t">Hold</div><div class="d">No action.</div><button class="btn" data-act="fogsubmit" data-kind="pass">No action</button></div>
      ${L.canTest ? '<div class="atk"><div class="t">Nuclear Test</div><div class="d">Put your four Technologies on the table for all to see. Unlocks your Capabilities — and tells everyone what you are building.</div><button class="btn" data-act="fogsubmit" data-kind="test">☢ Perform Nuclear Test</button></div>' : ''}
      ${attackListHTML(L, 'fog')}`, { sticky: true });
  }
  function counterModal() {
    const pr = G.prompt;
    if (!pr || !pr.player.human || $('#modal-back')) return;
    const opts = pr.options.map(id => `<button class="btn danger" data-act="counter" data-tid="${id}">🎯 ${esc(G.players[id].name)}</button>`).join(' ');
    openModal(`<h2 class="red">Counter-strike!</h2>
      <p>You have been eliminated${pr.by ? ' by <b>' + esc(pr.by.name) + '</b>' : ''} — but your Counter-strike fires. Choose who goes down with you.</p>
      <div class="atk">${opts}</div>`, { sticky: true });
  }
  function peekModal() {
    const rows = NPE.others(G, ME).map(o => `<div class="box"><b>${esc(o.name)}</b> <span class="hint">· ${o.hand.length} in hand</span>
      <div class="zone">${o.hand.map(c => img(c.key)).join('') || '<span class="more">empty hand</span>'}</div></div>`).join('');
    openModal(`<button class="btn sm close" data-act="closeModal">Resume ▶</button><h2>Superpower — game paused</h2>
      <p>You examine every hand. The AIs cannot see yours.</p><div class="peek">${rows}</div>`, { pause: true });
  }

  function afterHuman() { closePop(); pump(); }

  function onAct(el) {
    const a = el.dataset.act;
    if (!a) return;
    if (a !== 'card') closePop();
    switch (a) {
      case 'start': start(); break;
      case 'rules': openModal(rulesHTML(), { pause: !!G }); break;
      case 'closeModal': closeModal(); break;
      case 'sound': ui.muted = !ui.muted; renderTop(); break;
      case 'menu':
        if (!G || G.over || confirm('Abandon this game and return to the menu?')) {
          clearTimeout(ui.pumpT); clearTimeout(ui.autoT); fastStop(); closeModal(true); G = null;
          $('#game').classList.add('hidden'); $('#menu').classList.remove('hidden'); initMenu();
        }
        break;
      case 'ff': ui.ff = true; pump(); break;
      case 'card': openCardMenu(el.dataset.cid, el); break;
      case 'research': if (NPE.playResearch(G, ME)) { snd('click'); afterHuman(); } break;
      case 'skip': NPE.playSkip(G, ME); afterHuman(); break;
      case 'give': if (NPE.playGive(G, ME, +el.dataset.cid, +el.dataset.tid)) afterHuman(); break;
      case 'ret': if (NPE.playDisarm(G, ME, +el.dataset.cid)) afterHuman(); break;
      case 'reveal': if (NPE.reveal(G, ME, +el.dataset.cid)) { snd('click'); closePop(); render(); } break;
      case 'stand': NPE.humanWar(G, { kind: 'pass' }); afterHuman(); break;
      case 'test':
        if (G.mode === 'fast' || !(G.phase === 'war' && NPE.cur(G) === ME)) NPE.instant(G, ME, { kind: 'test' }, { interrupt: true });
        else NPE.humanWar(G, { kind: 'test' });
        afterHuman(); break;
      case 'attack': attackModal(el.dataset.mode || 'interrupt'); break;
      case 'launch': {
        const choice = { kind: 'attack', type: el.dataset.type, target: el.dataset.tid != null ? +el.dataset.tid : undefined };
        const mode = el.dataset.mode;
        closeModal();
        if (mode === 'turn') NPE.humanWar(G, choice);
        else if (mode === 'fog') NPE.submitFog(G, ME.id, choice);
        else NPE.instant(G, ME, choice, { interrupt: true });
        afterHuman(); break;
      }
      case 'fogopen': fogModal(); break;
      case 'fogsubmit': closeModal(true); NPE.submitFog(G, ME.id, { kind: el.dataset.kind }); afterHuman(); break;
      case 'counter': closeModal(true); NPE.chooseCounter(G, +el.dataset.tid); afterHuman(); break;
      case 'peek': peekModal(); break;
      case 'ceasefire': {
        const r = NPE.proposeCeasefire(G, ME);
        toast(r.refuses.length ? `${r.refuses.map(p => p.name).join(' & ')} refuse${r.refuses.length === 1 ? 's' : ''} to stand down.` : 'Everyone agrees to stop.');
        pump(); break;
      }
      case 'again': closeModal(true); start(); break;
      case 'tomenu': G = null; closeModal(true); fastStop(); $('#game').classList.add('hidden'); $('#menu').classList.remove('hidden'); initMenu(); break;
    }
  }

  /* ------------------------------------------------------------------ END */
  function finish() {
    fastStop();
    if (ui.endShown) return;
    ui.endShown = true;
    setTimeout(showEnd, 1100);
  }
  function showEnd() {
    if (!G) return;
    const r = G.result, alive = r.survivors.map(i => G.players[i]);
    let title, sub;
    if (r.kind === 'annihilation') { title = 'Mutual annihilation'; sub = 'Nobody is left. Nobody wins.'; }
    else if (r.kind === 'last') {
      const w = alive[0];
      title = w === ME ? 'You are the last one standing' : `${w.name} is the last power standing`;
      sub = w === ME ? 'You survived. Look at what it cost.' : 'The rest of the table is gone.';
    } else if (alive.length === G.players.length) { title = 'Deterrence held'; sub = 'Nobody died. That is the only winning move.'; }
    else { title = 'Stand-down'; sub = `${alive.length} of ${G.players.length} powers survive.`; }
    const rows = G.players.map(p => `<div class="endrow ${p.alive ? 'alive' : 'dead'}">
      <span><b>${esc(p.name)}</b> ${p === ME ? '(you)' : ''} — ${p.alive ? 'survived' : 'eliminated' + (p.eliminatedBy != null ? ' by ' + esc(G.players[p.eliminatedBy].name) : '')}</span>
      <span class="hint" style="color:var(--mut)">${p.tested ? '☢ tested · ' : ''}${p.kills} kill${p.kills === 1 ? '' : 's'}</span></div>`).join('');
    openModal(`<h2 class="${(r.kind === 'last' && alive[0] === ME) || (r.kind === 'ceasefire' && alive.length === G.players.length) ? '' : 'red'}">${esc(title)}</h2><p>${esc(sub)} <span class="hint" style="color:var(--mut)">(${G.round} round${G.round === 1 ? '' : 's'})</span></p>
      ${rows}
      <div class="quote">“The only winning move is not to play.”</div>
      <div class="row" style="margin-top:14px"><button class="btn primary" data-act="again">Play again</button><button class="btn" data-act="tomenu">Change settings</button></div>`, { sticky: true });
  }

  /* ------------------------------------------------------------------ BOOT */
  document.addEventListener('click', e => {
    const el = e.target.closest('[data-act]');
    if (el) { onAct(el); return; }
    if (!e.target.closest('.pop')) closePop();
  });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { closePop(); if (ui.modal && !$('.modal [data-act=fogsubmit]') && !$('.modal [data-act=counter]')) closeModal(); } });
  window.addEventListener('resize', fitHand);
  initMenu();
  window.__NP_DEBUG = { get G() { return G; }, get ME() { return ME; }, start, pump, ui };
})();
