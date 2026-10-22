// Headless AI-vs-AI playtest: checks invariants and prints outcome statistics.
const NP = require('../src/engine.js');

function total(G) {
  let n = G.deck.length + G.out.length;
  G.players.forEach(p => { n += p.hand.length + p.table.length; });
  return n;
}
function makeAI(personas) { return personas.map((pe, i) => ({ name: 'AI' + i, human: false, persona: pe })); }

function play(seed, mode, bio, personas, fastTicks) {
  const rng = NP.mulberry32(seed);
  const G = NP.makeGame({ rng, mode, bio, players: makeAI(personas) });
  const expected = total(G);
  let guard = 0;
  while (!G.over && guard++ < 5000) {
    if (G.mode === 'fast' && fastTicks) {
      // emulate real-time reactions: each AI gets a chance between turns
      G.players.forEach(p => { if (p.alive && !G.over) NP.aiFastTick(G, p); });
    }
    const s = NP.step(G);
    if (s === 'prompt' || s === 'human') throw new Error('unexpected wait ' + s);
    if (total(G) !== expected) throw new Error(`card count drift ${total(G)} vs ${expected} (seed ${seed} ${mode} ${bio})`);
    // invariants
    G.players.forEach(p => {
      if (p.tested && p.table.filter(c => NP.TECH.includes(c.key)).length !== 4) throw new Error('tested without 4 tech on table');
      if (!p.alive && p.hand.length) throw new Error('dead player has hand');
    });
  }
  if (!G.over) throw new Error('did not terminate');
  return G;
}

const modes = ['slow', 'fog', 'fast'];
const bios = ['off', '2000', '2035'];
const sets = [
  ['hawk', 'dove', 'opp'], ['hawk', 'hawk', 'wild'], ['dove', 'dove', 'opp'], ['wild', 'opp', 'dove'],
];
let fails = 0;
for (const mode of modes) for (const bio of bios) {
  const stat = { games: 0, turns: 0, last: 0, annih: 0, cease: 0, maxT: 0, deaths: 0 };
  const byKind = { short: 0, long: 0, super: 0, plague: 0, counter: 0, test: 0 };
  for (let seed = 1; seed <= 150; seed++) {
    const personas = sets[seed % sets.length];
    try {
      const G = (function () {
        const rng = NP.mulberry32(seed * 7919);
        const g = NP.makeGame({ rng, mode, bio, players: makeAI(personas) });
        g.on((t, d) => { if (t === 'attack') byKind[d.type]++; if (t === 'test') byKind.test++; });
        let guard = 0; const expected = total(g);
        while (!g.over && guard++ < 5000) {
          if (mode === 'fast') g.players.forEach(p => { if (p.alive && !g.over) NP.aiFastTick(g, p); });
          const s = NP.step(g);
          if (s === 'prompt' || s === 'human') throw new Error('unexpected wait ' + s);
          if (total(g) !== expected) throw new Error('card drift');
        }
        if (!g.over) throw new Error('no termination');
        return g;
      })();
      stat.games++; stat.turns += G.turnNo; stat.maxT = Math.max(stat.maxT, G.turnNo);
      stat.deaths += G.players.filter(p => !p.alive).length;
      stat[G.result.kind === 'last' ? 'last' : G.result.kind === 'annihilation' ? 'annih' : 'cease']++;
    } catch (e) { fails++; console.log('FAIL', mode, bio, seed, e.message); }
  }
  console.log(`${mode.padEnd(5)} ${bio.padEnd(5)} games=${stat.games} avgTurns=${(stat.turns / stat.games).toFixed(1)} max=${stat.maxT} ` +
    `lastStanding=${stat.last} annihilation=${stat.annih} ceasefire/stalemate=${stat.cease} avgDeaths=${(stat.deaths / stat.games).toFixed(2)} ` +
    `tests=${byKind.test} short=${byKind.short} long=${byKind.long} super=${byKind.super} plague=${byKind.plague} counter=${byKind.counter}`);
}
console.log(fails ? `${fails} FAILURES` : 'ALL OK');
process.exit(fails ? 1 : 0);
