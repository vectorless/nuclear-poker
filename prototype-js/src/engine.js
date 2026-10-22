/* Nuclear Poker — rules engine + AI.
 * Game design: Vinay Gupta. Print-and-play v4.2: Jonathan Korman. Card designs inspired by Ian Willey.
 * This file is pure logic (no DOM) so it runs in the browser and under Node for headless playtests.
 */
(function (root) {
  'use strict';

  const TECH = ['uranium', 'refinement', 'warhead', 'testing'];
  const CAPS = ['short', 'long', 'counter', 'super'];
  const BIO = ['labs', 'plague'];

  const INFO = {
    uranium:    { name: 'Uranium',       kind: 'tech' },
    refinement: { name: 'Refinement',    kind: 'tech' },
    warhead:    { name: 'Warhead',       kind: 'tech' },
    testing:    { name: 'Testing',       kind: 'tech' },
    short:      { name: 'Short-range',   kind: 'cap' },
    long:       { name: 'Long-range',    kind: 'cap' },
    counter:    { name: 'Counter-strike', kind: 'cap' },
    super:      { name: 'Superpower',    kind: 'cap' },
    labs:       { name: 'Labs',          kind: 'bio' },
    plague:     { name: 'Plague',        kind: 'bio' },
  };

  const PERSONAS = {
    hawk: { id: 'hawk', name: 'General Volkov',      title: 'The Hawk',        aggr: 0.80, fear: 0.50, caution: 0.20, gift: 0.04, reveal: 0.04, noise: 0.10, react: [0.9, 2.4], color: '#d9534f' },
    dove: { id: 'dove', name: 'Dr. Okafor',          title: 'The Deterrer',    aggr: 0.22, fear: 0.95, caution: 0.85, gift: 0.10, reveal: 0.55, noise: 0.08, react: [1.6, 3.6], color: '#4aa3df' },
    opp:  { id: 'opp',  name: 'Ambassador Lin',      title: 'The Opportunist', aggr: 0.50, fear: 0.75, caution: 0.50, gift: 0.10, reveal: 0.20, noise: 0.10, react: [1.2, 3.0], color: '#e0a526' },
    wild: { id: 'wild', name: 'President Reyes',     title: 'The Wildcard',    aggr: 0.55, fear: 0.40, caution: 0.10, gift: 0.22, reveal: 0.30, noise: 0.35, react: [0.8, 3.4], color: '#9b6bd1' },
  };

  /* ------------------------------------------------------------------ helpers */
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  function shuffle(arr, rng) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }
  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const byId = (G, id) => G.players[id];
  const aliveList = G => G.players.filter(x => x.alive);
  const others = (G, p) => G.players.filter(x => x.alive && x !== p);
  const holds = (p, key) => p.hand.some(c => c.key === key) || p.table.some(c => c.key === key);
  const hasAllCaps = p => CAPS.every(k => holds(p, k));
  const cardName = c => INFO[c.key].name;

  function neighborsOf(G, p) {
    const al = aliveList(G);
    if (al.length < 2) return [];
    const i = al.indexOf(p);
    if (i < 0) return [];
    const a = al[(i + 1) % al.length], b = al[(i - 1 + al.length) % al.length];
    return a === b ? [a] : [a, b];
  }

  function log(G, text, tone) {
    const e = { n: G.turnNo, text, tone: tone || 'info' };
    G.log.push(e);
    G.emit('log', e);
  }

  /* ------------------------------------------------------------------ setup */
  function makeGame(opts) {
    const rng = opts.rng || Math.random;
    const n = opts.players.length;
    const G = {
      rng,
      mode: opts.mode || 'slow',     // slow | fog | fast
      bio: opts.bio || 'off',        // off | 2000 | 2035
      players: [], deck: [], out: [], log: [],
      turn: 0, turnNo: 1, round: 1,
      phase: 'play',                 // play | war | fog
      intChecked: false,
      over: false, result: null,
      fog: null, prompt: null, counterQ: [],
      nextCardId: 1, total: {},
      listeners: [],
    };
    G.on = fn => G.listeners.push(fn);
    G.emit = (type, data) => G.listeners.forEach(fn => { try { fn(type, data); } catch (e) { /* UI errors must not break rules */ } });

    const sets = n + 1;
    const mk = key => ({ id: G.nextCardId++, key, pub: false });
    for (let s = 0; s < sets; s++) {
      TECH.concat(CAPS).forEach(k => G.deck.push(mk(k)));
      if (G.bio !== 'off') BIO.forEach(k => G.deck.push(mk(k)));
    }
    G.deck.forEach(c => { G.total[c.key] = (G.total[c.key] || 0) + 1; });
    shuffle(G.deck, rng);

    opts.players.forEach((pp, i) => {
      G.players.push({
        id: i, name: pp.name, human: !!pp.human,
        persona: pp.human ? null : (PERSONAS[pp.persona] || PERSONAS.opp),
        hand: [], table: [], alive: true, tested: false,
        kills: 0, eliminatedBy: null, eliminatedTurn: null, nextAct: 0,
      });
    });
    for (let r = 0; r < 3; r++) G.players.forEach(p => p.hand.push(G.deck.pop()));
    G.turn = Math.floor(rng() * n);
    return G;
  }

  /* ------------------------------------------------------------------ basic actions */
  function research(G, p) {
    if (!G.deck.length) return false;
    const c = G.deck.pop();
    c.pub = false;
    p.hand.push(c);
    log(G, `${p.name} researches (draws a card).`, 'info');
    G.emit('draw', { p, c });
    return c;
  }
  function proliferate(G, p, cardId, targetId) {
    const t = byId(G, targetId);
    const i = p.hand.findIndex(c => c.id === cardId);
    if (i < 0 || !t || !t.alive || t === p) return false;
    const [c] = p.hand.splice(i, 1);
    c.pub = false;
    t.hand.push(c);
    log(G, `${p.name} gives a card to ${t.name} (Proliferation).`, 'info');
    G.emit('give', { from: p, to: t, c });
    return true;
  }
  function disarm(G, p, cardId) {
    const i = p.hand.findIndex(c => c.id === cardId);
    if (i < 0) return false;
    const [c] = p.hand.splice(i, 1);
    c.pub = false;
    G.deck.splice(Math.floor(G.rng() * (G.deck.length + 1)), 0, c);
    log(G, `${p.name} returns a card to the deck (Disarmament).`, 'info');
    G.emit('disarm', { p, c });
    return true;
  }
  function reveal(G, p, cardId) {
    const c = p.hand.find(x => x.id === cardId);
    if (!c || c.pub) return false;
    c.pub = true;
    log(G, `${p.name} reveals a ${cardName(c)} card from their hand.`, 'reveal');
    G.emit('reveal', { p, c });
    return true;
  }

  function canTest(G, p) {
    return p.alive && !p.tested && TECH.every(k => p.hand.some(c => c.key === k));
  }
  function doTest(G, p) {
    if (!canTest(G, p)) return false;
    TECH.forEach(k => {
      const i = p.hand.findIndex(c => c.key === k);
      const [c] = p.hand.splice(i, 1);
      c.pub = true;
      p.table.push(c);
    });
    p.tested = true;
    log(G, `☢ ${p.name} performs a NUCLEAR TEST — all four Technologies on the table.`, 'test');
    G.emit('test', { p });
    return true;
  }

  /* ------------------------------------------------------------------ attacks */
  function attackTypes(G, p, ctx) {
    ctx = ctx || {};
    const out = [];
    if (!p.alive) return out;
    // Interrupts (acting out of turn) are only possible with Superpower in Slow/Fog; in Fast anything goes.
    const allow = t => !ctx.interrupt || G.mode === 'fast' || t === 'super';
    const nuc = p.tested;
    if (nuc && holds(p, 'short') && allow('short'))
      out.push({ type: 'short', targets: neighborsOf(G, p).map(x => x.id) });
    if (nuc && holds(p, 'short') && holds(p, 'long') && allow('long'))
      out.push({ type: 'long', targets: others(G, p).map(x => x.id) });
    if (nuc && hasAllCaps(p) && allow('super'))
      out.push({ type: 'super', targets: others(G, p).map(x => x.id) });
    if (G.bio !== 'off' && holds(p, 'labs') && holds(p, 'plague') &&
        (G.bio === '2035' || (p.tested && hasAllCaps(p))) && allow('plague'))
      out.push({ type: 'plague', targets: [] });
    return out;
  }
  const REVEAL = {
    short: ['short'], long: ['short', 'long'], super: CAPS,
  };
  function revealKeys(G, type) {
    if (type === 'plague') return G.bio === '2000' ? CAPS.concat(BIO) : BIO.slice();
    return REVEAL[type];
  }
  function showCards(G, p, keys) {
    const shown = [];
    keys.forEach(k => {
      if (p.table.some(c => c.key === k)) return;
      const i = p.hand.findIndex(c => c.key === k);
      if (i < 0) return;
      const [c] = p.hand.splice(i, 1);
      c.pub = true;
      p.table.push(c);
      shown.push(INFO[k].name);
    });
    return shown;
  }

  /** Perform one or more attacks "simultaneously". list: [{p,type,target}] — all already validated against pre-state. */
  function performAttacks(G, list) {
    const victims = new Map();
    list.forEach(a => {
      const shown = showCards(G, a.p, revealKeys(G, a.type));
      const tgt = a.target != null ? byId(G, a.target) : null;
      if (a.type === 'plague') {
        log(G, `☣ ${a.p.name} unleashes PLAGUE${shown.length ? ' (shows ' + shown.join(', ') + ')' : ''}!`, 'attack');
        others(G, a.p).filter(x => !holds(x, 'labs')).forEach(x => victims.set(x.id, a.p));
        G.plagued = true; // everyone still alive after this must hold Labs
        // The attacker is protected by their own Labs.
      } else {
        const label = { short: 'Short-range', long: 'Long-range', super: 'Superpower' }[a.type];
        log(G, `🚀 ${a.p.name} launches a ${label} ATTACK on ${tgt.name}${shown.length ? ' (shows ' + shown.join(', ') + ')' : ''}!`, 'attack');
        if (tgt && tgt.alive) victims.set(tgt.id, a.p);
      }
      G.emit('attack', { attacker: a.p, type: a.type, target: tgt });
    });
    kill(G, Array.from(victims.keys()).map(id => byId(G, id)), victims);
  }

  function canCounter(p) {
    return p.tested && holds(p, 'short') && holds(p, 'long') && holds(p, 'counter');
  }
  function kill(G, victims, byMap) {
    victims = victims.filter(v => v.alive);
    victims.forEach(v => {
      const cap = canCounter(v);
      v.alive = false;
      const killer = byMap && byMap.get ? byMap.get(v.id) : (byMap || null);
      v.eliminatedBy = killer ? killer.id : null;
      v.eliminatedTurn = G.turnNo;
      if (killer && killer !== v) killer.kills++;
      const names = v.hand.map(cardName);
      log(G, `💀 ${v.name} is ELIMINATED${killer && killer !== v ? ' by ' + killer.name : ''}.` +
        (names.length ? ` Their hand is revealed: ${names.join(', ')}.` : ''), 'death');
      v.hand.forEach(c => { c.pub = true; G.out.push(c); });
      v.hand = [];
      G.emit('death', { p: v, by: killer });
      if (cap) G.counterQ.push({ p: v, by: killer });
    });
  }

  function settle(G) {
    while (G.counterQ.length && !G.prompt) {
      const q = G.counterQ.shift();
      const targets = aliveList(G);
      if (!targets.length) continue;
      if (q.p.human) {
        G.prompt = { type: 'counter', player: q.p, options: targets.map(t => t.id), by: q.by };
        break;
      }
      doCounter(G, q.p, aiCounterTarget(G, q.p, q.by, targets));
    }
    checkOver(G);
  }
  function doCounter(G, p, target) {
    log(G, `🛰 ${p.name}'s COUNTER-STRIKE fires from beyond the grave at ${target.name}!`, 'attack');
    G.emit('attack', { attacker: p, type: 'counter', target });
    kill(G, [target], new Map([[target.id, p]]));
  }
  function chooseCounter(G, targetId) {
    const pr = G.prompt;
    if (!pr || pr.type !== 'counter' || !pr.options.includes(targetId)) return false;
    G.prompt = null;
    doCounter(G, pr.player, byId(G, targetId));
    settle(G);
    return true;
  }
  function checkOver(G) {
    if (G.over || G.prompt || G.counterQ.length) return;
    const al = aliveList(G);
    if (al.length <= 1) endGame(G, al.length === 1 ? 'last' : 'annihilation');
  }
  function endGame(G, kind) {
    G.over = true;
    G.result = { kind, survivors: aliveList(G).map(p => p.id) };
    G.emit('over', G.result);
  }

  /* ------------------------------------------------------------------ turn flow */
  const cur = G => G.players[G.turn];

  function endTurn(G) {
    if (G.over) return;
    const n = G.players.length;
    let i = G.turn;
    do { i = (i + 1) % n; } while (!G.players[i].alive);
    if (i <= G.turn) G.round++;
    G.turn = i;
    G.turnNo++;
    G.phase = 'play';
    G.intChecked = false;
    G.fog = null;
    if (G.turnNo > 500 && !G.over) {
      log(G, 'After a very long standoff, the players agree to stop.', 'info');
      endGame(G, 'ceasefire');
      return;
    }
    G.emit('turn', { p: cur(G) });
  }
  function afterPlay(G) {
    if (G.over) return;
    if (G.mode === 'slow') { G.phase = 'war'; }
    else if (G.mode === 'fog') { beginFog(G); }
    else { endTurn(G); }
  }

  /* Public API for a player's play action (also used by the AI). */
  function playResearch(G, p) { if (!research(G, p)) return false; afterPlay(G); return true; }
  function playGive(G, p, cardId, tid) { if (!proliferate(G, p, cardId, tid)) return false; afterPlay(G); return true; }
  function playDisarm(G, p, cardId) { if (!disarm(G, p, cardId)) return false; afterPlay(G); return true; }
  function playSkip(G, p) { log(G, `${p.name} has no legal play action and skips.`, 'info'); afterPlay(G); return true; }

  /* War step (Slow) */
  function applyWar(G, p, c) {
    if (c.kind === 'test') { doTest(G, p); }
    else if (c.kind === 'attack') {
      const av = attackTypes(G, p, {}).find(a => a.type === c.type);
      if (av && (c.type === 'plague' || av.targets.includes(c.target)))
        performAttacks(G, [{ p, type: c.type, target: c.target }]);
    } else {
      log(G, `${p.name}: no action.`, 'quiet');
    }
    settle(G);
  }
  function humanWar(G, c) {
    if (G.phase !== 'war') return false;
    applyWar(G, cur(G), c);
    if (!G.over && !G.prompt) endTurn(G);
    return true;
  }

  /* Interrupts / Fast-mode instant actions */
  function instant(G, p, c, ctx) {
    if (G.over || !p.alive || G.prompt) return false;
    ctx = ctx || {};
    if (c.kind === 'test') {
      if (!doTest(G, p)) return false;
      settle(G); return true;
    }
    if (c.kind === 'attack') {
      const av = attackTypes(G, p, { interrupt: ctx.interrupt !== false }).find(a => a.type === c.type);
      if (!av || (c.type !== 'plague' && !av.targets.includes(c.target))) return false;
      performAttacks(G, [{ p, type: c.type, target: c.target }]);
      settle(G);
      return true;
    }
    return false;
  }
  function runInterrupts(G) {
    // AIs holding Superpower may strike at any time (Slow / Fog).
    let acted = false;
    if (G.mode === 'fast') return false;
    for (const p of aliveList(G)) {
      if (p.human || G.over) continue;
      const opts = attackTypes(G, p, { interrupt: true });
      if (!opts.length) continue;
      const c = aiWarChoice(G, p, { interrupt: true });
      if (c.kind === 'attack') { if (instant(G, p, c, { interrupt: true })) acted = true; }
    }
    return acted;
  }

  /* Fog of war */
  function beginFog(G) {
    G.phase = 'fog';
    G.fog = { choices: {} };
    G.players.filter(p => p.alive && !p.human).forEach(p => { G.fog.choices[p.id] = aiWarChoice(G, p, { fog: true }); });
    // Humans with nothing they could do simply hold.
    G.players.filter(p => p.alive && p.human).forEach(p => {
      if (!canTest(G, p) && !attackTypes(G, p, {}).length) G.fog.choices[p.id] = { kind: 'pass' };
    });
    G.emit('fog', {});
  }
  function submitFog(G, pid, choice) {
    if (G.phase !== 'fog' || !G.fog) return false;
    G.fog.choices[pid] = choice;
    return true;
  }
  function fogPending(G) {
    return G.phase === 'fog' && G.fog ? G.players.filter(p => p.alive && G.fog.choices[p.id] === undefined) : [];
  }
  function describeChoice(G, p, c) {
    if (c.kind === 'test') return 'Nuclear Test';
    if (c.kind === 'attack') {
      if (c.type === 'plague') return 'PLAGUE attack';
      const t = byId(G, c.target);
      return `Attack on ${t ? t.name : '?'}`;
    }
    return 'no action';
  }
  function resolveFog(G) {
    const fog = G.fog;
    const orders = G.players.filter(p => p.alive).map(p => ({ p, c: fog.choices[p.id] || { kind: 'pass' } }));
    log(G, '— FOG LIFTS: orders revealed —', 'fog');
    orders.forEach(o => log(G, `${o.p.name}: ${describeChoice(G, o.p, o.c)}`, 'fog'));
    // Validate everything against the state at the start of the round.
    const tests = orders.filter(o => o.c.kind === 'test' && canTest(G, o.p));
    const atks = [];
    orders.forEach(o => {
      if (o.c.kind !== 'attack') return;
      const av = attackTypes(G, o.p, {}).find(a => a.type === o.c.type);
      if (av && (o.c.type === 'plague' || av.targets.includes(o.c.target)))
        atks.push({ p: o.p, type: o.c.type, target: o.c.target });
      else log(G, `${o.p.name}'s attack fizzles — they lacked what it takes.`, 'quiet');
    });
    tests.forEach(o => doTest(G, o.p));
    if (atks.length) performAttacks(G, atks);
    G.fog = null;
    settle(G);
    if (!G.over && !G.prompt) endTurn(G);
  }

  /* ------------------------------------------------------------------ AI */
  function unseenCounts(G, viewer) {
    const cnt = Object.assign({}, G.total);
    const sub = c => { cnt[c.key]--; };
    viewer.hand.forEach(sub);
    G.out.forEach(sub);
    G.players.forEach(pl => {
      pl.table.forEach(sub);
      if (pl !== viewer) pl.hand.filter(c => c.pub).forEach(sub);
    });
    let N = 0;
    Object.keys(cnt).forEach(k => { cnt[k] = Math.max(0, cnt[k]); N += cnt[k]; });
    return { cnt, N };
  }
  function pHold(m, N, h) {
    if (m <= 0 || h <= 0 || N <= 0) return 0;
    if (h >= N) return 1;
    let q = 1;
    for (let i = 0; i < h; i++) q *= Math.max(0, (N - m - i)) / (N - i);
    return 1 - q;
  }
  /** Perfect information: only a Fast-mode Superpower holder may examine hands. */
  function perfect(G, viewer) {
    return G.mode === 'fast' && viewer.tested && hasAllCaps(viewer);
  }
  function belief(G, viewer) {
    const U = unseenCounts(G, viewer);
    const P = (X, key) => {
      if (X === viewer || perfect(G, viewer)) return holds(X, key) ? 1 : 0;
      if (key === 'labs' && G.plagued && X.alive) return 1;
      if (holds(X, key) && (X.table.some(c => c.key === key) || X.hand.some(c => c.key === key && c.pub))) return 1;
      const h = X.hand.filter(c => !c.pub).length;
      return pHold(U.cnt[key], U.N, h);
    };
    return { P, U };
  }
  function readiness(G, B, X) {
    if (X.tested) return 1;
    let all = 1;
    TECH.forEach(k => { all *= B.P(X, k); });
    return all * 0.5;
  }
  /** How likely X can eliminate `target` imminently. */
  function threatOn(G, B, X, target) {
    if (!X.alive || X === target) return 0;
    const r = readiness(G, B, X);
    const nb = neighborsOf(G, X).includes(target);
    const ps = B.P(X, 'short'), pl = B.P(X, 'long');
    const nuc = r * (nb ? ps : ps * pl);
    let plag = 0;
    if (G.bio !== 'off') {
      const base = B.P(X, 'labs') * B.P(X, 'plague');
      let gate = 1;
      if (G.bio === '2000') gate = r * ps * pl * B.P(X, 'counter') * B.P(X, 'super');
      plag = base * gate * (1 - B.P(target, 'labs'));
    }
    return clamp(1 - (1 - nuc) * (1 - plag), 0, 1);
  }
  function revengeProb(G, B, X) {
    return readiness(G, B, X) * B.P(X, 'short') * B.P(X, 'long') * B.P(X, 'counter');
  }

  function scoreNuke(G, B, p, x) {
    const pe = p.persona;
    const t = threatOn(G, B, x, p);
    const rev = revengeProb(G, B, x);
    const al = aliveList(G);
    let s = pe.fear * t + pe.aggr * 0.6 - pe.caution * 1.5 * rev + (al.length === 2 ? 0.35 : 0);
    if (al.length >= 3) {
      others(G, p).forEach(y => {
        if (y === x) return;
        const ty = threatOn(G, B, y, p);
        if (ty > t) s -= 0.25 * (ty - t);
      });
    }
    return s + (G.rng() - 0.5) * 2 * pe.noise;
  }
  function scorePlague(G, B, p) {
    const pe = p.persona;
    const os = others(G, p);
    if (!os.length) return -9;
    let exp = 0, rev = 0, maxT = 0;
    os.forEach(x => {
      const die = 1 - B.P(x, 'labs');
      exp += die;
      rev += die * revengeProb(G, B, x);
      maxT = Math.max(maxT, threatOn(G, B, x, p));
    });
    const frac = exp / os.length;
    return 0.9 * frac + 0.3 * pe.aggr + 0.3 * pe.fear * maxT - 1.2 * pe.caution * Math.min(1, rev) - 0.3 +
      (G.rng() - 0.5) * 2 * pe.noise;
  }

  function aiWarChoice(G, p, ctx) {
    ctx = ctx || {};
    const pe = p.persona;
    const pass = { kind: 'pass' };
    const B = belief(G, p);
    if (!ctx.interrupt && canTest(G, p)) {
      const anyTested = others(G, p).some(x => x.tested);
      const capCount = CAPS.filter(k => holds(p, k)).length;
      const prob = clamp(0.30 + 0.40 * pe.aggr + 0.35 * (anyTested ? 1 : 0) + 0.06 * capCount, 0, 0.95);
      if (G.rng() < prob) return { kind: 'test' };
    }
    const opts = attackTypes(G, p, { interrupt: ctx.interrupt });
    let best = null, bestScore = -9;
    opts.forEach(o => {
      if (o.type === 'plague') {
        const s = scorePlague(G, B, p) - 0.02;
        if (s > bestScore) { bestScore = s; best = { kind: 'attack', type: 'plague' }; }
        return;
      }
      const pen = o.type === 'short' ? 0 : o.type === 'long' ? 0.01 : 0.02;
      o.targets.forEach(tid => {
        const s = scoreNuke(G, B, p, byId(G, tid)) - pen;
        if (s > bestScore) { bestScore = s; best = { kind: 'attack', type: o.type, target: tid }; }
      });
    });
    return best && bestScore > 0.35 ? best : pass;
  }
  function aiCounterTarget(G, p, by, targets) {
    if (by && by.alive && by !== p) return by;
    const B = belief(G, p);
    return targets.slice().sort((a, b) => (b.tested - a.tested) + (B.P(b, 'short') - B.P(a, 'short')) * 0.5)[0];
  }

  function usefulness(G, p, c) {
    const dup = p.hand.filter(x => x.key === c.key).length + p.table.filter(x => x.key === c.key).length > 1;
    const k = INFO[c.key].kind;
    if (k === 'tech') return p.tested ? 0.05 : (dup ? 0.25 : 1.0);
    if (k === 'cap') {
      if (dup) return 0.25;
      return { short: 0.9, long: 0.8, counter: 0.75, super: 0.85 }[c.key];
    }
    return dup ? 0.25 : 0.85;
  }
  function leastUseful(G, p) {
    const pool = p.hand.slice();
    pool.sort((a, b) => usefulness(G, p, a) - usefulness(G, p, b) + (G.rng() - 0.5) * 0.02);
    return pool[0] || null;
  }
  function maybeReveal(G, p) {
    const pe = p.persona;
    const anyTested = others(G, p).some(x => x.tested);
    const cands = p.hand.filter(c => !c.pub && INFO[c.key].kind === 'cap');
    if (!cands.length || !p.tested) return;
    if (G.rng() < pe.reveal * (anyTested ? 1 : 0.3)) {
      const order = ['super', 'counter', 'long', 'short'];
      cands.sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key));
      reveal(G, p, cands[0].id);
    }
  }
  function aiPlay(G, p) {
    const pe = p.persona;
    maybeReveal(G, p);
    const r = G.rng();
    const B = belief(G, p);
    const weakest = () => others(G, p).sort((a, b) => threatOn(G, B, a, p) - threatOn(G, B, b, p))[0];
    if (p.hand.length >= 7 && r < 0.7) { const c = leastUseful(G, p); if (c) return playDisarm(G, p, c.id); }
    if (p.hand.length >= 2 && r < pe.gift) {
      const c = leastUseful(G, p), t = weakest();
      if (c && t && usefulness(G, p, c) < 0.5) return playGive(G, p, c.id, t.id);
    }
    if (G.deck.length) return playResearch(G, p);
    const c = leastUseful(G, p);
    if (c) return playDisarm(G, p, c.id);
    return playSkip(G, p);
  }

  /** Fast mode: an AI looks at the table and may Test/Attack right now. */
  function aiFastTick(G, p) {
    if (G.mode !== 'fast' || G.over || G.prompt || !p.alive || p.human) return false;
    const c = aiWarChoice(G, p, { fast: true });
    if (c.kind === 'pass') return false;
    return instant(G, p, c, { interrupt: false });
  }

  function aiAgreesCeasefire(G, p) {
    const B = belief(G, p);
    const opts = attackTypes(G, p, {});
    if (opts.length && p.persona.aggr > 0.45 && G.rng() < 0.7) return false;
    const maxT = Math.max.apply(null, others(G, p).map(x => threatOn(G, B, x, p)).concat([0]));
    if (maxT > 0.55 && opts.length) return false;
    return G.rng() < 0.9;
  }
  function proposeCeasefire(G, proposer) {
    const agrees = [], refuses = [];
    others(G, proposer).forEach(p => {
      if (p.human) { agrees.push(p); return; }
      (aiAgreesCeasefire(G, p) ? agrees : refuses).push(p);
    });
    if (!refuses.length) {
      log(G, `${proposer.name} proposes to stop. Everyone agrees.`, 'info');
      endGame(G, 'ceasefire');
    } else {
      log(G, `${proposer.name} proposes to stop. ${refuses.map(p => p.name).join(' and ')} refuse${refuses.length === 1 ? 's' : ''}.`, 'info');
    }
    return { agrees, refuses };
  }

  /* ------------------------------------------------------------------ driver */
  /** What does the game need next? 'over' | 'prompt' | 'human' | 'ai' */
  function status(G) {
    if (G.over) return 'over';
    if (G.prompt) return 'prompt';
    // The player whose turn it is may have been eliminated mid-turn (interrupt, Fast attack, Plague).
    if (G.phase !== 'fog' && !cur(G).alive) { endTurn(G); return status(G); }
    if (G.phase === 'play' && !G.intChecked) {
      G.intChecked = true;
      if (runInterrupts(G)) { checkOver(G); return status(G); } // re-evaluate: someone may now be dead
    }
    if (G.phase === 'fog') return fogPending(G).some(p => p.human) ? 'human' : 'ai';
    return cur(G).human ? 'human' : 'ai';
  }
  /** Perform the next AI step. */
  function step(G) {
    const s = status(G);
    if (s === 'over' || s === 'prompt' || s === 'human') return s;
    if (G.phase === 'play') {
      const p = cur(G);
      if (p.human) return 'human';
      aiPlay(G, p);
    } else if (G.phase === 'war') {
      const p = cur(G);
      applyWar(G, p, aiWarChoice(G, p, {}));
      if (!G.over && !G.prompt) endTurn(G);
    } else if (G.phase === 'fog') {
      resolveFog(G);
    }
    checkOver(G);
    return 'ok';
  }

  /** Legal-action summary for the UI. */
  function legal(G, p, ctx) {
    return {
      canResearch: G.deck.length > 0,
      canTest: canTest(G, p),
      attacks: attackTypes(G, p, ctx || {}),
      canPeek: G.mode === 'fast' && p.alive && p.tested && hasAllCaps(p),
      canCounter: canCounter(p),
    };
  }

  const NP = {
    TECH, CAPS, BIO, INFO, PERSONAS,
    makeGame, mulberry32, step, status, legal,
    playResearch, playGive, playDisarm, playSkip, reveal,
    humanWar, instant, submitFog, fogPending, resolveFog, chooseCounter,
    aiFastTick, proposeCeasefire, canTest, holds, hasAllCaps, neighborsOf, aliveList, others, cur,
    describeChoice, revealKeys, settle, endGame, belief, threatOn,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = NP;
  else root.NP = NP;
})(typeof window !== 'undefined' ? window : globalThis);
