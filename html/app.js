const app = document.getElementById('app');
const pill = document.getElementById('labPill');

const bagListEl = document.getElementById('bagList');
const detailEl = document.getElementById('detail');

const refreshBtn = document.getElementById('refreshBtn');
const closeBtn = document.getElementById('closeBtn');

const viewBtn = document.getElementById('viewBtn');
const analyzeBtn = document.getElementById('analyzeBtn');
const deleteBtn = document.getElementById('deleteBtn');

let bags = [];
let selectedId = null;
let inLab = false;
let labLabel = null;

function post(name, body = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: {'Content-Type':'application/json; charset=UTF-8'},
    body: JSON.stringify(body)
  }).then(r => r.json());
}

function fmtTime(ts){
  if(!ts) return '';
  const d = new Date(ts * 1000);
  return d.toLocaleString();
}

function renderList(){
  bagListEl.innerHTML = '';
  if(!bags || bags.length === 0){
    const div = document.createElement('div');
    div.className = 'empty';
    div.textContent = 'No evidence bags found.';
    bagListEl.appendChild(div);
    return;
  }

  for(const b of bags){
    const item = document.createElement('div');
    item.className = 'item' + (b.id === selectedId ? ' active' : '');
    item.onclick = () => selectBag(b.id);

    const row1 = document.createElement('div');
    row1.className = 'row1';

    const left = document.createElement('div');
    const label = document.createElement('div');
    label.className = 'label';
    label.textContent = `${b.bag_label} (#${b.id})`;
    const type = document.createElement('div');
    type.className = 'type';
    type.textContent = `${b.evidence_type} • Owner: ${b.owner_name || 'Unknown'}`;
    left.appendChild(label);
    left.appendChild(type);

    const right = document.createElement('div');
    right.className = 'meta';
    right.textContent = fmtTime(b.collected_ts);

    row1.appendChild(left);
    row1.appendChild(right);

    item.appendChild(row1);
    bagListEl.appendChild(item);
  }
}

function setButtons(){
  const hasSel = !!selectedId;
  viewBtn.disabled = !hasSel;
  analyzeBtn.disabled = !hasSel || !inLab;
  deleteBtn.disabled = !hasSel || !inLab;
}

function setDetailEmpty(){
  detailEl.innerHTML = '<div class="empty">No bag selected.</div>';
}

function setDetail(kvs){
  detailEl.innerHTML = '';
  for(const [k,v] of kvs){
    const row = document.createElement('div');
    row.className = 'kv';
    const kk = document.createElement('div');
    kk.className = 'k';
    kk.textContent = k;
    const vv = document.createElement('div');
    vv.className = 'v';
    vv.textContent = v ?? '';
    row.appendChild(kk);
    row.appendChild(vv);
    detailEl.appendChild(row);
  }
}

function selectBag(id){
  selectedId = id;
  renderList();
  setButtons();
  setDetailEmpty();
}

async function refresh(){
  const res = await post('tp_evidence_ui_list', {});
  if(res && res.ok){
    bags = res.bags || [];
    // keep selection if still exists
    if(selectedId && !bags.find(b => b.id === selectedId)){
      selectedId = null;
      setDetailEmpty();
    }
    renderList();
    setButtons();
  }
}

async function viewSelected(action){
  if(!selectedId) return;
  const res = await post(action, { id: selectedId });
  if(!res || !res.ok){
    return;
  }

  const d = res.data || {};
  const kvs = [];

  if(action === 'tp_evidence_ui_view'){
    kvs.push(['Bag', `${d.bag_label} (#${selectedId})`]);
    kvs.push(['Type', d.evidence_type]);
    kvs.push(['Owner', d.owner_name]);
    kvs.push(['Weapon', d.weapon || '']);
    kvs.push(['Serial', d.serial || '']);
    kvs.push(['Note', d.note || '']);
    kvs.push(['Scene', `${(d.x||0).toFixed(2)}, ${(d.y||0).toFixed(2)}, ${(d.z||0).toFixed(2)}`]);
    kvs.push(['Created', d.created_at || '']);
    kvs.push(['Collected', d.collected_at || '']);
  } else if(action === 'tp_evidence_ui_analyze'){
    kvs.push(['Bag', `${d.bag_label} (#${selectedId})`]);
    kvs.push(['Type', d.evidence_type]);
    kvs.push(['Owner Identifier', d.owner_identifier || '']);
    kvs.push(['Owner Name', d.owner_name || '']);
    kvs.push(['Fingerprint', d.fingerprint || '']);
    kvs.push(['DNA', d.dna || '']);
    kvs.push(['Weapon', d.weapon || '']);
    kvs.push(['Serial', d.serial || '']);
    kvs.push(['Note', d.note || '']);
    kvs.push(['Scene', `${(d.x||0).toFixed(2)}, ${(d.y||0).toFixed(2)}, ${(d.z||0).toFixed(2)}`]);
    kvs.push(['Created', d.created_at || '']);
    kvs.push(['Collected', d.collected_at || '']);
  }

  setDetail(kvs);
}

async function deleteSelected(){
  if(!selectedId) return;
  const res = await post('tp_evidence_ui_delete', { id: selectedId });
  if(res && res.ok){
    selectedId = null;
    setDetailEmpty();
    await refresh();
  }
}

window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if(msg.type === 'open'){
    app.style.display = 'block';
    pill.style.display = 'block';
    refresh();
  }
  if(msg.type === 'close'){
    app.style.display = 'none';
    pill.style.display = 'none';
    selectedId = null;
    setDetailEmpty();
  }
  if(msg.type === 'labStatus'){
    inLab = !!msg.inLab;
    labLabel = msg.label || null;

    if(inLab){
      pill.classList.remove('off');
      pill.classList.add('on');
      pill.textContent = labLabel ? `In Lab: ${labLabel}` : 'In Lab';
    } else {
      pill.classList.remove('on');
      pill.classList.add('off');
      pill.textContent = 'Not in Lab';
    }

    setButtons();
  }
});

document.addEventListener('keydown', (e) => {
  if(e.key === 'Escape'){
    post('tp_evidence_ui_close', {});
  }
});

refreshBtn.onclick = () => refresh();
closeBtn.onclick = () => post('tp_evidence_ui_close', {});
viewBtn.onclick = () => viewSelected('tp_evidence_ui_view');
analyzeBtn.onclick = () => viewSelected('tp_evidence_ui_analyze');
deleteBtn.onclick = () => deleteSelected();
