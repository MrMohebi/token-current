'use strict';
const $ = id => document.getElementById(id);
let token = '', mode = 'relay', selected = null, mesh = { machines: [] }, timer, history = [];
const compact = number => new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 }).format(number);
const currentDay = () => new Date().toISOString().slice(0, 10);
async function api(path, method = 'GET', body) {
  const response = await fetch('/api/v1/' + path, { method, headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(5000) });
  if (!response.ok) { const error = await response.json().catch(() => ({})); throw new Error(error.error || `Request failed (${response.status})`); }
  return response.status === 204 ? null : response.json();
}
function providers(machine) { const value = $('provider').value; return Object.entries(machine.snapshot?.providers || {}).filter(([name]) => value === 'all' || name === value).map(([, sample]) => sample); }
function online(machine) { return machine.online && Date.now() / 1000 - machine.receivedAt < 15 && Date.now() / 1000 - (machine.snapshot?.observedAt || 0) < 15; }
function measurable(machine) { return online(machine) && providers(machine).some(p => p.health === 'ready'); }
function rate(machine) { return online(machine) ? providers(machine).filter(p => p.health === 'ready').reduce((n, p) => n + p.rate, 0) : 0; }
function totals(machines) { const result = { input: 0, output: 0, cached: 0 }; for (const machine of machines) if (machine.snapshot?.day === currentDay()) for (const p of providers(machine)) { result.input += p.totals.input; result.output += p.totals.output; result.cached += p.totals.cacheRead + p.totals.cacheWrite; } return result; }
function svg(tag, attributes, text) { const e = document.createElementNS('http://www.w3.org/2000/svg', tag); for (const [key, value] of Object.entries(attributes)) e.setAttribute(key, value); if (text !== undefined) e.textContent = text; return e; }
function render() {
  const chosen = selected ? mesh.machines.filter(m => m.id === selected) : mesh.machines;
  const available = chosen.some(m => online(m) && providers(m).some(p => p.health === 'ready'));
  const value = chosen.reduce((n, m) => n + rate(m), 0), counts = totals(chosen);
  $('selection').textContent = selected ? (chosen[0]?.name || 'Machine removed') : 'All machines';
  $('rate').textContent = available ? compact(value) : '—';
  for (const name of ['input', 'output', 'cached']) $(name).textContent = chosen.some(m => m.snapshot) ? compact(counts[name]) : '—';
  $('count').textContent = `${mesh.machines.filter(online).length} online / ${mesh.machines.length} total`;
  $('empty').hidden = mesh.machines.length > 0;
  drawNetwork(); drawRows();
}
function drawNetwork() {
  const scene = $('network'); scene.replaceChildren();
  const visible = mesh.machines.slice(0, 10);
  visible.forEach((machine, index) => {
    const angle = visible.length === 1 ? 0 : index / visible.length * Math.PI * 2 - Math.PI / 2;
    const x = 360 + Math.cos(angle) * 244, y = 200 + Math.sin(angle) * 134;
    scene.append(svg('line', { x1: 360, y1: 200, x2: x, y2: y, class: 'edge' + (online(machine) ? ' online' : '') }));
    const group = svg('g', { class: `node${online(machine) ? '' : ' offline'}${selected === machine.id ? ' selected' : ''}`, tabindex: '0', role: 'button', 'aria-label': `${machine.name}, ${measurable(machine) ? compact(rate(machine)) + ' tokens per second' : 'offline'}` });
    group.append(svg('circle', { cx: x, cy: y, r: 44 }), svg('text', { x, y: y - 3, class: 'node-rate' }, measurable(machine) ? compact(rate(machine)) : '—'), svg('text', { x, y: y + 18 }, 'tok/s'), svg('text', { x, y: y + 64 }, machine.name.length > 23 ? machine.name.slice(0, 22) + '…' : machine.name));
    group.addEventListener('click', () => select(machine.id)); group.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); select(machine.id); } }); scene.append(group);
  });
  scene.append(svg('circle', { cx: 360, cy: 200, r: 47, class: 'hub' }), svg('text', { x: 360, y: 196, class: 'hub-text' }, 'Token'), svg('text', { x: 360, y: 217, class: 'hub-text' }, 'Current'));
}
function drawRows() {
  $('machines').replaceChildren();
  for (const machine of mesh.machines) {
    const row = document.createElement('tr'), first = document.createElement('td'), button = document.createElement('button'); button.textContent = machine.name; button.addEventListener('click', () => select(machine.id)); first.append(button);
    const small = document.createElement('small'); small.textContent = machine.platform || 'Waiting for first report'; first.append(small); row.append(first);
    const status = document.createElement('td'), badge = document.createElement('span'); badge.className = 'status' + (online(machine) ? ' online' : ''); badge.textContent = online(machine) ? 'Online' : machine.receivedAt ? 'Offline' : 'Waiting'; status.append(badge);
    const source = document.createElement('small'); source.textContent = machine.snapshot ? providers(machine).map(p => p.health).join(' · ') : 'Configure the daemon to connect'; status.append(source); row.append(status);
    const speed = document.createElement('td'); speed.textContent = measurable(machine) ? compact(rate(machine)) + '/s' : '—'; row.append(speed);
    const total = document.createElement('td'), counts = totals([machine]); total.textContent = machine.snapshot ? compact(counts.input + counts.output) : '—'; row.append(total);
    const actions = document.createElement('td');
    if (mode === 'relay') {
      const rotate = document.createElement('button'); rotate.className = 'quiet'; rotate.textContent = 'Rotate token'; rotate.addEventListener('click', () => rotateToken(machine));
      const remove = document.createElement('button'); remove.className = 'quiet'; remove.textContent = 'Remove'; remove.addEventListener('click', async () => { if (!confirm(`Remove ${machine.name} and revoke its connection?`)) return; try { await api('instances/' + encodeURIComponent(machine.id), 'DELETE'); if (selected === machine.id) selected = null; await refresh(); } catch (e) { $('notice').textContent = e.message; } }); actions.append(rotate, remove);
    }
    row.append(actions); $('machines').append(row);
  }
}
function select(id) { selected = id; history = []; render(); }
function drawHistory() {
  const chosen = selected ? mesh.machines.filter(m => m.id === selected) : mesh.machines;
  history.push(chosen.reduce((n, m) => n + rate(m), 0)); history = history.slice(-60);
  const peak = Math.max(1, ...history); $('history').replaceChildren(svg('polyline', { points: history.map((v, i) => `${(60 - history.length + i) * 300 / 59},${85 - v / peak * 80}`).join(' '), fill: 'none', stroke: 'var(--cyan)', 'stroke-width': 2 }));
}
async function refresh() { mesh = await api('mesh'); $('notice').textContent = ''; $('connection').textContent = 'Connected'; render(); drawHistory(); }
async function poll() { clearTimeout(timer); try { await refresh(); } catch (e) { $('connection').textContent = 'Reconnecting'; $('notice').textContent = e.message; render(); } if (token) timer = setTimeout(poll, 1000); }
$('login-form').addEventListener('submit', async e => { e.preventDefault(); token = $('token').value.trim(); try { const info = await api('info'); mode = info.mode; await refresh(); $('login').hidden = true; $('dashboard').hidden = false; $('session').hidden = false; $('add').hidden = mode !== 'relay'; $('mode').textContent = mode === 'relay' ? 'Self-hosted relay' : 'Direct agent'; $('token').value = ''; poll(); } catch (error) { token = ''; $('login-error').textContent = error.message; } });
$('logout').addEventListener('click', () => { token = ''; clearTimeout(timer); mesh = { machines: [] }; history = []; $('dashboard').hidden = true; $('session').hidden = true; $('login').hidden = false; $('device-token').value = ''; $('enroll').close(); });
$('provider').addEventListener('change', () => { history = []; render(); }); $('show-all').addEventListener('click', () => select(null));
$('add').addEventListener('click', () => { $('enroll-form').hidden = false; $('enrollment').hidden = true; $('enroll-error').textContent = ''; $('device-token').value = ''; $('enroll').showModal(); });
function closeDialog() { $('device-token').value = ''; $('enroll').close(); }
$('cancel').addEventListener('click', closeDialog); $('done').addEventListener('click', closeDialog); $('enroll').addEventListener('cancel', () => { $('device-token').value = ''; });
function showEnrollment(data) { $('copy-token').textContent = 'Copy token'; $('enroll-form').hidden = true; $('enrollment').hidden = false; $('device-token').value = data.token; if (!$('enroll').open) $('enroll').showModal(); }
$('enroll-form').addEventListener('submit', async e => { e.preventDefault(); try { const data = await api('instances', 'POST', { name: $('name').value.trim(), platform: $('platform').value }); showEnrollment(data); await refresh(); } catch (error) { $('enroll-error').textContent = error.message; } });
async function rotateToken(machine) { if (!confirm(`Replace ${machine.name}'s device token? Its old connection will stop until reconfigured.`)) return; try { showEnrollment(await api('instances/' + encodeURIComponent(machine.id) + '/rotate', 'POST')); await refresh(); } catch (e) { $('notice').textContent = e.message; } }
$('copy-token').addEventListener('click', async () => { try { await navigator.clipboard.writeText($('device-token').value); $('copy-token').textContent = 'Copied'; } catch { $('device-token').select(); $('enroll-error').textContent = 'Select and copy the token manually in this browser.'; } });
