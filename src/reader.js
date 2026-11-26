'use strict';
const sampleLines = JSON.parse(document.getElementById('sample').textContent);
const $ = id => document.getElementById(id);
const sampleKey = 'lv-japanese-manga-reading-v1', sampleImage = $('page-image').src;
const samplePage = {
  key: sampleKey,
  title: '车站问路',
  lines: sampleLines,
  number: 1
};
let book = [samplePage], pageIndex = 0, active = samplePage, lines = sampleLines, notes;
let activeImageUrl = null, current = 0, expanded = false, warning = '';
const sessionNotes = new Map();

function pageNotes(page) {
  if (sessionNotes.has(page.key)) return sessionNotes.get(page.key);
  const record = {edits: {}, glosses: {}, saved: []};
  try {
    const stored = JSON.parse(localStorage.getItem(page.key));
    if (stored && Array.isArray(stored.saved) && stored.edits && typeof stored.edits === 'object') {
      record.edits = stored.edits;
      record.glosses = stored.glosses || {};
      record.saved = stored.saved.filter(
          n => n && Number.isInteger(n.i) && n.i >= 0 && n.i < page.lines.length &&
              typeof n.key === 'string');
    }
  } catch (e) {
    warning = '当前窗口无法读取之前保存的内容。'
  }
  sessionNotes.set(page.key, record);
  return record;
}
notes = pageNotes(active);
const pageMeaning = (page, i) =>
    pageNotes(page).glosses[i] || page.lines[i].translation || '尚未填写释义。';
const pageText = (page, i) => pageNotes(page).edits[i] || page.lines[i].raw;
const meaning = i => pageMeaning(active, i);
const shown = i => pageText(active, i);
const sentenceKey = i => 'line:' + i;
function persist(page = active) {
  try {
    localStorage.setItem(page.key, JSON.stringify(pageNotes(page)));
    return true
  } catch (e) {
    warning = '浏览器未允许本地保存，本次操作仅在当前窗口有效。';
    return false
  }
}
function message(s) {
  $('status').textContent = warning || s || ''
}
function count() {
  $('count').textContent = book.reduce((total, page) => total + pageNotes(page).saved.length, 0)
}
function select(i) {
  if (i < 0 || i >= lines.length) return;
  current = i;
  expanded = false;
  $('word').value = '';
  $('words').open = false;
  $('correction').open = false;
  $('gloss-edit').open = false;
  message('');
  paint()
}
function paint() {
  const empty = lines.length === 0;
  $('empty-page').hidden = !empty;
  $('sentence-tools').hidden = empty;
  $('legend').hidden = empty;
  $('hint').textContent = empty ? '浏览漫画原图。' : '点选画中的对白，先猜句意，再对照释义。';
  if (empty) {
    count();
    return
  }
  const row = lines[current];
  $('position').textContent = '对白 ' + (current + 1) + ' / ' + lines.length;
  $('line').textContent = shown(current);
  $('edit').value = shown(current);
  $('raw').textContent = row.raw;
  $('meaning').textContent = meaning(current);
  $('gloss-edit').hidden = active === samplePage;
  $('gloss').value = notes.glosses[current] || '';
  $('meaning').hidden = !expanded;
  $('show').setAttribute('aria-expanded', String(expanded));
  $('show').textContent = expanded ? '收起释义' : '查看释义';
  $('save').textContent =
      notes.saved.some(x => x.key === sentenceKey(current)) ? '取消整句收藏' : '收藏整句';
  $('prev').disabled = current === 0;
  $('next').disabled = current === lines.length - 1;
  document.querySelectorAll('.hot').forEach(
      (b, i) => b.setAttribute('aria-pressed', String(i === current)));
  count()
}
function view(name) {
  const isRead = name === 'reader';
  $('reader').hidden = !isRead;
  $('review').hidden = isRead;
  for (const [id, active] of [['read-tab', isRead], ['review-tab', !isRead]]) {
    if (active)
      $(id).setAttribute('aria-current', 'page');
    else
      $(id).removeAttribute('aria-current')
  }
  if (!isRead) list()
}
function action(label, cb) {
  const b = document.createElement('button');
  b.textContent = label;
  b.onclick = cb;
  return b
}
function textNode(tag, s, cls) {
  const n = document.createElement(tag);
  n.textContent = s;
  if (cls) n.className = cls;
  return n
}
function list() {
  count();
  const dest = $('cards');
  dest.replaceChildren();
  const total = Number($('count').textContent);
  const reviewed =
      book.reduce((n, page) => n + pageNotes(page).saved.filter(note => note.reviewed).length, 0);
  $('review-info').textContent = total ? '共 ' + total + ' 条，已复习 ' + reviewed + ' 条。' :
                                         '点读时收藏一句对白或一个词即可开始。';
  if (!total) {
    dest.append(action('回到点读', () => view('reader')));
    return
  }
  for (const [index, page] of book.entries()) {
    const record = pageNotes(page);
    for (const note of record.saved) {
      const card = document.createElement('article');
      card.className = 'saved-item';
      const location =
          page === samplePage ? page.title : '第 ' + page.number + ' 页 · ' + page.title;
      card.append(textNode(
          'small', location + ' · 第 ' + (note.i + 1) + ' 句 · ' + (note.word ? '词语' : '整句')));
      const entryTitle = textNode('strong', note.word || pageText(page, note.i));
      entryTitle.lang = 'ja';
      card.append(entryTitle);
      if (note.word) {
        const context = textNode('p', pageText(page, note.i), 'context');
        context.lang = 'ja';
        card.append(context);
      }
      const gloss = textNode('p', pageMeaning(page, note.i), 'meaning');
      gloss.hidden = true;
      const bar = document.createElement('div');
      bar.className = 'actions act';
      bar.append(action('查看句义', e => {
                   gloss.hidden = !gloss.hidden;
                   e.currentTarget.textContent = gloss.hidden ? '查看句义' : '收起句义'
                 }), action('回到原处', () => {
                   openPage(index, note.i);
                   document.querySelectorAll('.hot')[note.i].focus()
                 }), action(note.reviewed ? '已复习 · 撤销' : '标为已复习', () => {
                   note.reviewed = !note.reviewed;
                   persist(page);
                   list()
                 }), action('移除', () => {
                   record.saved = record.saved.filter(item => item.key !== note.key);
                   persist(page);
                   list();
                   paint()
                 }));
      card.append(bar, gloss);
      dest.append(card);
    }
  }
}
function mount() {
  document.querySelectorAll('.hot').forEach(n => n.remove());
  for (const r of lines) {
    const b = document.createElement('button');
    b.className = 'hot';
    const [x, y, w, h] = r.box;
    Object.assign(b.style, {left: x + '%', top: y + '%', width: w + '%', height: h + '%'});
    b.setAttribute('aria-label', '点读第 ' + (r.id + 1) + ' 句');
    b.onclick = () => select(r.id);
    $('picture').append(b)
  }
}
mount();
function basename(name) {
  return String(name).split('/').pop().split(String.fromCharCode(92)).pop()
}
function openPage(index, sentence = 0) {
  const page = book[index];
  if (!page) return;
  const previousUrl = activeImageUrl;
  activeImageUrl = page.file ? URL.createObjectURL(page.file) : null;
  pageIndex = index;
  active = page;
  lines = page.lines;
  notes = pageNotes(page);
  $('scene').textContent = page.title;
  const sample = page === samplePage;
  const img = $('page-image');
  img.removeAttribute('width');
  img.removeAttribute('height');
  img.src = activeImageUrl || sampleImage;
  img.alt = sample ? '日语车站问路样章。' : '导入的漫画原图 ' + page.title;
  if (previousUrl) URL.revokeObjectURL(previousUrl);
  $('footnote').textContent = sample ?
      '本页内嵌预先提取的 OCR 文字与位置，中文释义按样章原句编写。收藏、校正和复习状态保存在当前浏览器。' :
      '使用导入的 OCR 文字点读，可校正文字并补充释义。笔记保存在当前浏览器。';
  $('read-tab').textContent = sample ? '点读样章' : '点读漫画';
  $('sample-page').hidden = sample;
  $('page-nav').hidden = book.length <= 1;
  $('prev-page').disabled = index === 0;
  $('next-page').disabled = index === book.length - 1;
  $('page-number').textContent = sample ? '' : '原书第 ' + page.number + ' / ' + page.total + ' 页';
  current = 0;
  expanded = false;
  message('');
  mount();
  view('reader');
  if (lines.length)
    select(sentence);
  else
    paint();
}
$('prev-page').onclick = () => openPage(pageIndex - 1);
$('next-page').onclick = () => openPage(pageIndex + 1);
function importedLines(page) {
  const w = page.img_width, h = page.img_height;
  if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0 || !Array.isArray(page.blocks))
    throw Error('这一页的尺寸或识别块信息不完整。');
  const result = [];
  for (const b of page.blocks) {
    if (!Array.isArray(b.box) || b.box.length !== 4 || !b.box.every(Number.isFinite) ||
        !Array.isArray(b.lines))
      continue;
    const [a, c, d, e] = b.box;
    if (a < 0 || c < 0 || d > w || e > h || d <= a || e <= c) continue;
    const raw = b.lines.filter(v => typeof v === 'string').join('').trim();
    if (!raw) continue;
    result.push({
      id: result.length,
      raw,
      translation: '',
      box: [100 * a / w, 100 * c / h, 100 * (d - a) / w, 100 * (e - c) / h]
    })
  }
  return result
}
async function verifyImage(file, page) {
  const url = URL.createObjectURL(file);
  try {
    const probe = new Image();
    probe.src = url;
    try {
      await probe.decode()
    } catch (e) {
      throw Error('无法打开图片 ' + file.name + '。')
    }
    if (probe.naturalWidth !== page.img_width || probe.naturalHeight !== page.img_height)
      throw Error(file.name + ' 的尺寸与识别结果不一致，请选择原图。');
  } finally {
    URL.revokeObjectURL(url)
  }
}
$('load-page').onclick = async () => {
  const doc = $('mok-file').files[0], files = Array.from($('img-file').files), btn = $('load-page');
  const feedback = $('load-status');
  if (!doc || !files.length) {
    feedback.textContent = '请选择识别结果和至少一张配套图片。';
    return
  }
  btn.disabled = true;
  $('sample-page').disabled = true;
  try {
    const data = JSON.parse(await doc.text());
    if (!data || !Array.isArray(data.pages))
      throw Error('文件里没有标准 .mokuro 的 pages 页列表。');
    const positions = new Map();
    for (const [index, page] of data.pages.entries()) {
      if (!page || typeof page.img_path !== 'string') continue;
      const name = basename(page.img_path).normalize();
      positions.set(name, positions.has(name) ? -1 : index);
    }
    const selected = new Map();
    for (const file of files) {
      if (!/\.(png|jpe?g|webp|gif)$/i.test(file.name))
        throw Error('请选择 PNG、JPEG、WebP 或 GIF 原图。');
      const index = positions.get(file.name.normalize());
      if (index === undefined) throw Error('识别结果中没有 ' + file.name + '，请使用原文件名。');
      if (index < 0 || selected.has(index))
        throw Error('所选图片或识别文件含同名页 ' + file.name + '，无法唯一匹配。');
      selected.set(index, file);
    }
    const imported = [];
    for (const [index, page] of data.pages.entries()) {
      const file = selected.get(index);
      if (!file) continue;
      const items = importedLines(page);
      feedback.textContent = '正在检查图片 ' + (imported.length + 1) + ' / ' + files.length + '…';
      await verifyImage(file, page);
      const key = 'lv-mokuro-v1:' +
          JSON.stringify(
              [data.volume_uuid || doc.name, page.img_path, page.img_width, page.img_height]);
      imported.push(
          {key, title: file.name, lines: items, number: index + 1, total: data.pages.length, file});
    }
    book = imported;
    openPage(0);
    feedback.textContent = '已打开 ' + book.length + ' / ' + data.pages.length + ' 页。';
  } catch (err) {
    feedback.textContent = '没有切换页面。' +
        (err instanceof SyntaxError ? '所选识别结果无法解析。' : err.message || '请检查文件。');
  } finally {
    btn.disabled = false;
    $('sample-page').disabled = false
  }
};
$('sample-page').onclick = () => {
  book = [samplePage];
  openPage(0);
  $('load-status').textContent = '已返回内置样章。'
};
$('save-gloss').onclick = () => {
  const v = $('gloss').value.trim();
  if (!v) {
    message('请输入想保存的释义。');
    return
  }
  notes.glosses[current] = v;
  persist();
  expanded = true;
  paint();
  message('已保存本句释义。')
};
$('prev').onclick = () => select(current - 1);
$('next').onclick = () => select(current + 1);
$('show').onclick = () => {
  expanded = !expanded;
  paint()
};
$('save').onclick = () => {
  const id = sentenceKey(current);
  if (notes.saved.some(x => x.key === id))
    notes.saved = notes.saved.filter(x => x.key !== id);
  else
    notes.saved.push({key: id, i: current, word: '', reviewed: false});
  persist();
  paint();
  message('复习本已更新。')
};
$('save-word').onclick = () => {
  const word = $('word').value.trim();
  if (!word || !shown(current).includes(word)) {
    message('请输入当前对白中出现的词语。');
    return
  }
  const id = 'word:' + current + ':' + word;
  if (!notes.saved.some(x => x.key === id))
    notes.saved.push({key: id, i: current, word, reviewed: false});
  persist();
  paint();
  message('已收藏词语及本句。')
};
$('apply').onclick = () => {
  const newText = $('edit').value.trim();
  if (!newText) {
    message('校正后的对白不能为空。');
    return
  }
  notes.edits[current] = newText;
  persist();
  paint();
  message('已保存校正。')
};
$('reset').onclick = () => {
  delete notes.edits[current];
  persist();
  paint();
  message('已恢复原始识别。')
};
$('read-tab').onclick = () => {
  view('reader');
  paint()
};
$('review-tab').onclick = () => view('review');
select(0);
