const app = document.getElementById('app');
const labPill = document.getElementById('labPill');

const closeBtn = document.getElementById('closeBtn');
const refreshBags = document.getElementById('refreshBags');
const bagsList = document.getElementById('bagsList');
const bagDetails = document.getElementById('bagDetails');
const bagErr = document.getElementById('bagErr');
const viewBtn = document.getElementById('viewBtn');
const analyzeBtn = document.getElementById('analyzeBtn');
const deleteBtn = document.getElementById('deleteBtn');

const refreshWiretap = document.getElementById('refreshWiretap');
const tapNumber = document.getElementById('tapNumber');
const tapLabel = document.getElementById('tapLabel');
const tapAddBtn = document.getElementById('tapAddBtn');
const tapList = document.getElementById('tapList');
const callsList = document.getElementById('callsList');
const alertsList = document.getElementById('alertsList');

let selectedBagId = null;
let selectedBag = null;

function nui(name, data = {}) {
  return fetch(`https://TwoPoint_EvidenceStandalone/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(r => r.json()).catch(() => ({}));
}

function setLabPill(inLab, label) {
  if (inLab) {
    labPill.classList.remove('out');
    labPill.classList.add('in');
    labPill.textContent = label ? `In Lab: ${label}` : 'In Lab';
  } else {
    labPill.classList.remove('in');
    labPill.classList.add('out');
    labPill.textContent = 'Not in Lab';
  }
}

function fmtTime(ts) {
  if (!ts) return '';
  const d = new Date(ts * 1000);
  return d.toLocaleString();
}

function clearBag() {
  selectedBagId = null;
  selectedBag = null;
  bagDetails.textContent = '';
  bagErr.textContent = '';
}

function renderBags(bags) {
  bagsList.innerHTML = '';
  (bags || []).forEach(b => {
    const el = document.createElement('div');
    el.className = 'item' + (b.id === selectedBagId ? ' active' : '');
    el.innerHTML = `
      <div><b>#${b.id}</b> <span class="muted">(${b.type})</span></div>
      <div class="small muted">Collected by: ${b.collected_by || 'Unknown'}</div>
      <div class="small muted">Analyzed: ${b.analyzed_at ? 'Yes' : 'No'}</div>
    `;
    el.onclick = () => {
      selectedBagId = b.id;
      document.querySelectorAll('#bagsList .item').forEach(x => x.classList.remove('active'));
      el.classList.add('active');
    };
    bagsList.appendChild(el);
  });
}

async function refreshBagsFn() {
  clearBag();
  await nui('bags', {});
}

async function viewBagFn() {
  bagErr.textContent = '';
  if (!selectedBagId) { bagErr.textContent = 'Select a bag first.'; return; }
  await nui('viewBag', { bagId: selectedBagId });
}

async function analyzeBagFn() {
  bagErr.textContent = '';
  if (!selectedBagId) { bagErr.textContent = 'Select a bag first.'; return; }
  await nui('analyzeBag', { bagId: selectedBagId });
}

async function deleteBagFn() {
  bagErr.textContent = '';
  if (!selectedBagId) { bagErr.textContent = 'Select a bag first.'; return; }
  await nui('deleteBag', { bagId: selectedBagId });
  await refreshBagsFn();
}

function renderTargets(targets) {
  tapList.innerHTML = '';
  (targets || []).forEach(t => {
    const el = document.createElement('div');
    el.className = 'item';
    const label = t.label ? ` - ${t.label}` : '';
    el.innerHTML = `
      <div><b>${t.target_number}</b><span class="muted">${label}</span></div>
      <div class="small muted">Click to remove</div>
    `;
    el.onclick = async () => {
      await nui('wiretapRemove', { number: t.target_number });
      await refreshWiretapFn();
    };
    tapList.appendChild(el);
  });
}

function renderCalls(calls) {
  callsList.innerHTML = '';
  (calls || []).forEach(c => {
    const el = document.createElement('div');
    el.className = 'item';
    el.innerHTML = `
      <div><b>${c.stage.toUpperCase()}</b> <span class="muted">${c.numbers.join(', ')}</span></div>
      <div class="small muted">Started: ${fmtTime(c.startedAt)}</div>
    `;
    callsList.appendChild(el);
  });
}

function renderAlerts(alerts) {
  alertsList.innerHTML = '';
  (alerts || []).slice(-30).reverse().forEach(a => {
    const el = document.createElement('div');
    el.className = 'item';
    el.innerHTML = `
      <div><b>${(a.stage || 'update').toUpperCase()}</b> <span class="muted">${(a.numbers || []).join(', ')}</span></div>
      <div class="small muted">${fmtTime(a.startedAt || a.answeredAt || a.endedAt)}</div>
    `;
    alertsList.appendChild(el);
  });
}

async function refreshWiretapFn() {
  await nui('wiretapState', {});
}

closeBtn.onclick = async () => {
  await nui('close', {});
  app.classList.add('hidden');
};

refreshBags.onclick = refreshBagsFn;
viewBtn.onclick = viewBagFn;
analyzeBtn.onclick = analyzeBagFn;
deleteBtn.onclick = deleteBagFn;

refreshWiretap.onclick = refreshWiretapFn;
tapAddBtn.onclick = async () => {
  const number = (tapNumber.value || '').trim();
  const label = (tapLabel.value || '').trim();
  if (!number) return;
  await nui('wiretapAdd', { number, label });
  tapNumber.value = '';
  tapLabel.value = '';
  await refreshWiretapFn();
};

document.querySelectorAll('.tab').forEach(btn => {
  btn.onclick = () => {
    document.querySelectorAll('.tab').forEach(x => x.classList.remove('active'));
    btn.classList.add('active');
    const tab = btn.dataset.tab;
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    document.getElementById(`tab-${tab}`).classList.add('active');
  };
});

window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if (msg.type === 'open') {
    app.classList.remove('hidden');
    refreshBagsFn();
    refreshWiretapFn();
  }

  if (msg.type === 'labPill') {
    setLabPill(!!msg.inLab, msg.label || '');
  }

  if (msg.type === 'uiResponse') {
    if (!msg.ok) {
      bagErr.textContent = msg.err || 'Request failed';
      return;
    }
    const data = msg.data || {};
    if (data.bags) renderBags(data.bags);
    if (data.bag) {
      selectedBag = data.bag;
      bagDetails.textContent = JSON.stringify(selectedBag, null, 2);
    }
    if (typeof data.inLab === 'boolean') {
      // server's view, but pill is updated client-side anyway
    }
  }

  if (msg.type === 'wiretapResp') {
    if (!msg.ok) return;
    const data = msg.data || {};
    renderTargets(data.targets || []);
    renderCalls(data.calls || []);
    renderAlerts(data.alerts || []);
  }

  if (msg.type === 'wiretapAlert') {
    // live alert
    refreshWiretapFn();
  }

  if (msg.type === 'wiretapRefresh') {
    refreshWiretapFn();
  }
});
