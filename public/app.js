(() => {
  const API = "https://ibkirlsqpzmhuwssdcjj.supabase.co/functions/v1/psychology-profile";
  const COURSE = window.PSYCH_COURSE;
  const ICONS = {
    brain: '<path d="M9.5 4.6A2.6 2.6 0 0 0 4.4 5.3v.4A3.7 3.7 0 0 0 3 12.8a3.8 3.8 0 0 0 3.6 5.1h.2A2.8 2.8 0 0 0 9.5 21V4.6Z"/><path d="M14.5 4.6a2.6 2.6 0 0 1 5.1.7v.4A3.7 3.7 0 0 1 21 12.8a3.8 3.8 0 0 1-3.6 5.1h-.2a2.8 2.8 0 0 1-2.7 3.1V4.6Z"/><path d="M9.5 8.2H7.8a2 2 0 0 0-2 2M14.5 8.2h1.7a2 2 0 0 1 2 2M9.5 14.8H8a2 2 0 0 1-2-2M14.5 14.8H16a2 2 0 0 0 2-2"/>',
    home: '<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M9 20v-6h6v6"/>',
    book: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z"/>',
    pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4Z"/>',
    cards: '<rect x="3" y="5" width="14" height="16" rx="2"/><path d="m7 5 .8-2h11.7A1.5 1.5 0 0 1 21 4.5V17l-4 1"/><path d="M7 10h6M7 14h4"/>',
    matching: '<path d="M8 7h11l-3-3M16 10l3-3-3-3"/><path d="M16 17H5l3 3M8 14l-3 3 3 3"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/>',
    chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>'
  };
  function icon(name, className = "ui-icon") {
    return `<svg class="${className}" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ICONS.brain}</svg>`;
  }
  const sections = [
    ["dashboard", "home", "Dashboard", "HOME"],
    ["lessons", "book", "Lessons", "LEARN"],
    ["notes", "pencil", "Notes", "WRITE"],
    ["flashcards", "cards", "Flashcards", "RECALL"],
    ["matching", "matching", "Matching", "PRACTICE"],
    ["quiz", "check", "Quiz", "CHECK"],
  ];

  const els = {
    loginView: document.querySelector("#loginView"), appView: document.querySelector("#appView"),
    loginForm: document.querySelector("#loginForm"), username: document.querySelector("#username"), loginError: document.querySelector("#loginError"),
    sidebarNav: document.querySelector("#sidebarNav"), mobileNav: document.querySelector("#mobileNav"), content: document.querySelector("#content"),
    pageTitle: document.querySelector("#pageTitle"), pageEyebrow: document.querySelector("#pageEyebrow"), sidebarUsername: document.querySelector("#sidebarUsername"),
    syncStatus: document.querySelector("#syncStatus"), topSyncStatus: document.querySelector("#topSyncStatus"), saveNowBtn: document.querySelector("#saveNowBtn"),
    topActions: document.querySelector("#topActions"), switchUserBtn: document.querySelector("#switchUserBtn"), toastHost: document.querySelector("#toastHost"), toastTemplate: document.querySelector("#toastTemplate")
  };

  let username = null;
  let revision = 0;
  let state = defaultState();
  let currentSection = "dashboard";
  let saveTimer = null;
  let isSaving = false;
  let dirty = false;
  let flashIndex = 0;
  let flashFlipped = false;
  let activeFlashSection = null;
  let activeMatchSection = null;
  let matching = { left: null, right: null, matched: new Set() };
  let quizAnswers = {};
  let activeNoteId = "general";

  function defaultState() {
    return {
      version: 1,
      notes: { general: { title: "General Notes", text: "", createdAt: 0, updatedAt: 0 } },
      progress: {},
      quizScores: {},
      flashcards: {},
      matching: {},
      updatedAt: 0
    };
  }
  function asMap(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
  }
  function normalizeNotes(value) {
    const raw = asMap(value);
    const out = {};
    for (const [id, note] of Object.entries(raw)) {
      const item = note && typeof note === "object" && !Array.isArray(note) ? note : {};
      out[id] = {
        title: String(item.title || (id === "general" ? "General Notes" : "Untitled Note")),
        text: String(item.text || ""),
        createdAt: Number(item.createdAt || item.updatedAt || 0),
        updatedAt: Number(item.updatedAt || 0),
        deleted: Boolean(item.deleted)
      };
    }
    if (!Object.keys(out).length) out.general = { title: "General Notes", text: "", createdAt: 0, updatedAt: 0, deleted: false };
    return out;
  }
  function normalizeStateShape(value) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : {};
    return {
      version: Number(raw.version || 1),
      notes: normalizeNotes(raw.notes),
      progress: asMap(raw.progress),
      quizScores: asMap(raw.quizScores),
      flashcards: asMap(raw.flashcards),
      matching: asMap(raw.matching),
      updatedAt: Number(raw.updatedAt || 0)
    };
  }
  function canonicalize(value) {
    if (Array.isArray(value)) return value.map(canonicalize);
    if (!value || typeof value !== "object") return value;
    return Object.keys(value).sort().reduce((out, key) => { out[key] = canonicalize(value[key]); return out; }, {});
  }
  function statesEqual(a, b) {
    return JSON.stringify(canonicalize(normalizeStateShape(a))) === JSON.stringify(canonicalize(normalizeStateShape(b)));
  }

  function normalizeUsername(value) {
    return String(value || "").trim().toLowerCase();
  }
  function validUsername(value) { return /^[a-z0-9_]{2,32}$/.test(value); }
  function profileKey(name) { return `psychologyLab.profile.${name}`; }
  function activeKey() { return "psychologyLab.activeUsername"; }

  function readLocal(name) {
    try {
      const parsed = JSON.parse(localStorage.getItem(profileKey(name)) || "null");
      if (!parsed || typeof parsed !== "object") return null;
      return { ...parsed, state: normalizeStateShape(parsed.state) };
    } catch { return null; }
  }
  function writeLocal() {
    if (!username) return;
    localStorage.setItem(profileKey(username), JSON.stringify({ state, revision, savedAt: Date.now() }));
    localStorage.setItem(activeKey(), username);
  }

  function mergeRecords(a = {}, b = {}) {
    const out = { ...a };
    for (const [key, value] of Object.entries(b || {})) {
      if (!out[key]) { out[key] = value; continue; }
      const at = Number(out[key]?.updatedAt || 0);
      const bt = Number(value?.updatedAt || 0);
      if (bt >= at) out[key] = value;
    }
    return out;
  }
  function mergeStates(localState, cloudState) {
    const l = localState || defaultState(), c = cloudState || defaultState();
    return {
      version: Math.max(Number(l.version || 1), Number(c.version || 1)),
      notes: mergeRecords(c.notes, l.notes),
      progress: mergeRecords(c.progress, l.progress),
      quizScores: mergeRecords(c.quizScores, l.quizScores),
      flashcards: mergeRecords(c.flashcards, l.flashcards),
      matching: mergeRecords(c.matching, l.matching),
      updatedAt: Math.max(Number(l.updatedAt || 0), Number(c.updatedAt || 0))
    };
  }

  async function api(path, body) {
    const action = path === "/profile/load" ? "load" : path === "/profile/save" ? "save" : "";
    if (!action) throw new Error("Unknown API path.");

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);
    try {
      const response = await fetch(API, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, ...body }), signal: controller.signal, cache: "no-store"
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        const err = new Error(data.error || `Request failed (${response.status})`);
        err.status = response.status; err.data = data; throw err;
      }
      return data;
    } finally { clearTimeout(timer); }
  }

  async function login(name) {
    name = normalizeUsername(name);
    els.loginError.textContent = "";
    if (!validUsername(name)) { els.loginError.textContent = "Use 2–32 lowercase letters, numbers, or underscores."; return; }
    const local = readLocal(name);
    setSync("saving", "Loading…");
    try {
      const cloud = await api("/profile/load", { username: name });
      username = name;
      revision = Number(cloud.revision || 0);
      state = mergeStates(local?.state, normalizeStateShape(cloud.state));
      writeLocal();
      els.loginView.classList.add("hidden");
      els.sidebarUsername.textContent = username;
      els.topActions?.classList.remove("hidden"); els.switchUserBtn?.classList.remove("hidden");
      buildNav(); navigate("dashboard");
      setSync("synced", "Synced");
      if (local?.state && !statesEqual(local.state, cloud.state)) scheduleSave(200);
    } catch (error) {
      if (local?.state) {
        username = name; revision = Number(local.revision || 0); state = local.state;
        els.loginView.classList.add("hidden");
        els.sidebarUsername.textContent = username; els.topActions?.classList.remove("hidden"); els.switchUserBtn?.classList.remove("hidden"); buildNav(); navigate("dashboard");
        setSync("local", "Local only");
        toast("Cloud unavailable — loaded this profile from this device.");
      } else {
        setSync("local", "Offline"); els.loginError.textContent = "Could not load this profile right now.";
      }
    }
  }

  async function saveNow(showToast = false) {
    if (!username || isSaving || !dirty) { if (showToast && username) toast("Everything is already saved."); return; }
    isSaving = true; setSync("saving", "Saving…"); writeLocal();
    try {
      const result = await api("/profile/save", { username, state, expectedRevision: revision });
      revision = Number(result.revision || revision); state = mergeStates(state, normalizeStateShape(result.state)); dirty = false; writeLocal();
      setSync("synced", "Synced"); if (showToast) toast("Saved.");
    } catch (error) {
      if (error.status === 409 && error.data?.state) {
        state = mergeStates(state, normalizeStateShape(error.data.state)); revision = Number(error.data.revision || revision); writeLocal();
        try {
          const retry = await api("/profile/save", { username, state, expectedRevision: revision });
          revision = Number(retry.revision || revision); state = mergeStates(state, normalizeStateShape(retry.state)); dirty = false; writeLocal(); setSync("synced", "Synced");
          if (showToast) toast("Saved after merging newer cloud progress.");
        } catch { setSync("local", "Local only"); }
      } else setSync("local", "Local only");
    } finally { isSaving = false; }
  }

  function scheduleSave(delay = 700) {
    dirty = true; state.updatedAt = Date.now(); writeLocal(); setSync("saving", "Saving…");
    clearTimeout(saveTimer); saveTimer = setTimeout(() => saveNow(false), delay);
  }

  function setSync(kind, text) {
    const className = kind === "saving" ? "sync-pill saving" : kind === "local" ? "sync-pill local" : "sync-pill";
    els.topSyncStatus.className = className; els.topSyncStatus.textContent = text;
    els.syncStatus.textContent = text;
  }

  function buildNav() {
    const make = ([id, iconName, label]) => `<button class="nav-button" data-nav="${id}"><span class="nav-icon">${icon(iconName)}</span><span>${label}</span></button>`;
    els.sidebarNav.innerHTML = sections.map(make).join(""); els.mobileNav.innerHTML = sections.map(make).join("");
    document.querySelectorAll("[data-nav]").forEach(btn => btn.addEventListener("click", () => navigate(btn.dataset.nav)));
  }

  function navigate(id) {
    currentSection = id;
    document.querySelectorAll("[data-nav]").forEach(btn => btn.classList.toggle("active", btn.dataset.nav === id));
    const found = sections.find(s => s[0] === id) || sections[0]; els.pageTitle.textContent = found[2]; els.pageEyebrow.textContent = found[3];
    render(); window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function render() {
    const renderers = { dashboard: renderDashboard, lessons: renderLessons, notes: renderNotes, flashcards: renderFlashcards, matching: renderMatching, quiz: renderQuiz };
    renderers[currentSection]?.();
  }

  function stats() {
    const completed = Object.values(state.progress || {}).filter(x => x?.completed).length;
    const totalLessons = COURSE.units.reduce((n,u) => n + u.lessons.length, 0);
    const flashReviewed = Object.values(state.flashcards || {}).filter(x => x?.seen).length;
    const bestQuiz = Object.values(state.quizScores || {}).reduce((m,x) => Math.max(m, Number(x?.score || 0)), 0);
    return { completed, totalLessons, flashReviewed, bestQuiz };
  }

  function renderDashboard() {
    const s = stats();
    const totalCards = COURSE.flashcards?.length || 0;
    const totalQuiz = COURSE.quiz?.length || 0;
    els.content.innerHTML = `
      <section class="hero"><span class="badge">${icon("brain","badge-icon")} Chapters 1–2 loaded</span><h3>Learn the lecture slides, then retrieve them.</h3><p>The course now follows the two uploaded psychology PDFs as its source: Chapter 1 covers the foundations and history of psychology; Chapter 2 covers research methods, measurement, bias, and ethics.</p></section>
      <div class="stats-grid">
        ${stat("Lessons complete", `${s.completed}/${s.totalLessons}`, "13 source-based lessons")}
        ${stat("Flashcards seen", `${s.flashReviewed}/${totalCards}`, `${totalCards} course cards`)}
        ${stat("Best quiz", `${s.bestQuiz}%`, `${totalQuiz}-question course quiz`)}
        ${stat("Notes", visibleNotes().length, visibleNotes().length === 1 ? "1 saved note" : "Saved separately by username")}
      </div>
      <div class="section-head"><h3>Course chapters</h3><p>${escapeHtml(COURSE.sourceNote || "")}</p></div>
      <div class="chapter-grid">${COURSE.units.map(unit => `<article class="panel chapter-card"><span class="badge">Chapter ${unit.number}</span><h3>${escapeHtml(unit.title)}</h3><p>${escapeHtml(unit.description)}</p><div class="lesson-meta"><span>${unit.lessons.length} lessons</span><span>•</span><span>${escapeHtml(unit.source)}</span></div></article>`).join("")}</div>
      <!-- study-tools-summary removed -->
      <button class="primary-btn dashboard-start" id="openLessons">Start Chapter 1 →</button>`;
    document.querySelector("#openLessons")?.addEventListener("click", () => navigate("lessons"));
  }
  function stat(label,value,note){return `<div class="stat-card"><div class="stat-label">${label}</div><div class="stat-value">${value}</div><div class="stat-note">${note}</div></div>`}
  function coming(iconName,title,body){return `<li><span class="coming-icon">${icon(iconName)}</span><div><strong>${title}</strong><span>${body}</span></div></li>`}

  function renderLessons() {
    els.content.innerHTML = `<div class="section-head"><div><h3>${COURSE.title}</h3><p>${COURSE.subtitle}</p></div><span class="badge">13 lessons · 2 chapters</span></div>
      <div class="source-banner">${icon("brain","badge-icon")} <span>${escapeHtml(COURSE.sourceNote || "")}</span></div>
      ${COURSE.units.map(unit => `<section class="course-chapter"><div class="chapter-heading"><div><span class="badge">Chapter ${unit.number}</span><h3>${escapeHtml(unit.title)}</h3><p>${escapeHtml(unit.description)}</p></div><span class="chapter-source">${escapeHtml(unit.source)}</span></div><div class="lesson-grid">${unit.lessons.map(lesson => {
        const done = Boolean(state.progress[lesson.id]?.completed);
        return `<article class="lesson-card ${done ? "lesson-done" : ""}"><div class="lesson-card-top"><span class="badge">Lesson ${unit.number}.${lesson.number}</span>${done ? `<span class="done-pill">✓ Complete</span>` : ""}</div><h3>${escapeHtml(lesson.title)}</h3><p>${escapeHtml(lesson.description)}</p><div class="lesson-meta"><span>${lesson.objectives?.length || 0} objectives</span><span>•</span><span>${escapeHtml(lesson.source)}</span></div><button class="soft-btn" data-open-lesson="${lesson.id}" style="margin-top:18px">Open lesson →</button></article>`;
      }).join("")}</div></section>`).join("")}`;
    document.querySelectorAll("[data-open-lesson]").forEach(btn => btn.addEventListener("click", () => renderLessonShell(btn.dataset.openLesson)));
  }

  function allLessons() {
    return COURSE.units.flatMap(unit => unit.lessons.map(lesson => ({ unit, lesson })));
  }
  function findLesson(id) {
    return allLessons().find(item => item.lesson.id === id) || null;
  }
  function renderTeachingSection(section) {
    const body = (section.body || []).map(p => `<p>${escapeHtml(p)}</p>`).join("");
    const bullets = section.bullets?.length ? `<ul>${section.bullets.map(x => `<li>${escapeHtml(x)}</li>`).join("")}</ul>` : "";
    const steps = section.steps?.length ? `<ol>${section.steps.map(x => `<li>${escapeHtml(x)}</li>`).join("")}</ol>` : "";
    const pairs = section.pairs?.length ? `<div class="concept-pairs">${section.pairs.map(([term,def]) => `<div class="concept-row"><strong>${escapeHtml(term)}</strong><span>${escapeHtml(def)}</span></div>`).join("")}</div>` : "";
    return `<section class="teaching-section"><h4>${escapeHtml(section.title)}</h4>${body}${bullets}${steps}${pairs}</section>`;
  }

  function renderLessonShell(id) {
    const found = findLesson(id);
    if (!found) { renderLessons(); return; }
    const { unit, lesson } = found;
    const list = allLessons();
    const index = list.findIndex(x => x.lesson.id === id);
    const prev = list[index - 1]?.lesson || null;
    const next = list[index + 1]?.lesson || null;
    const p = state.progress[id] || {};
    els.pageTitle.textContent = lesson.title;
    els.pageEyebrow.textContent = `CHAPTER ${unit.number} · LESSON ${unit.number}.${lesson.number}`;
    els.content.innerHTML = `<article class="lesson-page">
      <header class="lesson-hero"><div><span class="badge">${icon("brain","badge-icon")} Chapter ${unit.number} · Lesson ${unit.number}.${lesson.number}</span><h3>${escapeHtml(lesson.title)}</h3><p>${escapeHtml(lesson.description)}</p></div><div class="lesson-source-box"><span>Source</span><strong>${escapeHtml(lesson.source)}</strong></div></header>
      <section class="lesson-objectives"><h4>By the end, you should be able to</h4><ul>${(lesson.objectives || []).map(x => `<li>${escapeHtml(x)}</li>`).join("")}</ul></section>
      <div class="teaching-stack">${(lesson.sections || []).map(renderTeachingSection).join("")}</div>
      <section class="quick-checks"><div class="section-head"><div><h3>Quick checks</h3><p>Reveal the answer only after you answer from memory.</p></div></div>${(lesson.checks || []).map((check,i) => `<details class="quick-check"><summary>${i+1}. ${escapeHtml(check.question)}</summary><div>${escapeHtml(check.answer)}</div></details>`).join("")}</section>
      <footer class="lesson-footer"><div class="lesson-nav-buttons">${prev ? `<button class="ghost-btn" data-lesson-prev="${prev.id}">← ${escapeHtml(prev.title)}</button>` : `<button class="ghost-btn" data-back-lessons>← All lessons</button>`}${next ? `<button class="soft-btn" data-lesson-next="${next.id}">${escapeHtml(next.title)} →</button>` : `<button class="soft-btn" data-back-lessons>All lessons</button>`}</div><button id="toggleLessonComplete" class="primary-btn">${p.completed ? "✓ Completed · mark incomplete" : "Mark lesson complete"}</button></footer>
    </article>`;
    document.querySelector("[data-lesson-prev]")?.addEventListener("click", e => renderLessonShell(e.currentTarget.dataset.lessonPrev));
    document.querySelector("[data-lesson-next]")?.addEventListener("click", e => renderLessonShell(e.currentTarget.dataset.lessonNext));
    document.querySelectorAll("[data-back-lessons]").forEach(btn => btn.addEventListener("click", () => { els.pageTitle.textContent = "Lessons"; els.pageEyebrow.textContent = "LEARN"; renderLessons(); }));
    document.querySelector("#toggleLessonComplete")?.addEventListener("click", () => {
      const existing = state.progress[id] || {}; state.progress[id] = { ...existing, completed: !existing.completed, updatedAt: Date.now() }; scheduleSave(); renderLessonShell(id);
    });
  }

  function visibleNotes() {
    return Object.entries(state.notes || {})
      .filter(([, note]) => note && !note.deleted)
      .sort((a, b) => Number(b[1].updatedAt || b[1].createdAt || 0) - Number(a[1].updatedAt || a[1].createdAt || 0));
  }
  function ensureActiveNote() {
    const notes = visibleNotes();
    if (!notes.length) {
      const now = Date.now();
      state.notes.general = { title: "General Notes", text: "", createdAt: now, updatedAt: now, deleted: false };
      activeNoteId = "general";
      scheduleSave();
      return state.notes.general;
    }
    if (!state.notes[activeNoteId] || state.notes[activeNoteId].deleted) activeNoteId = notes[0][0];
    return state.notes[activeNoteId];
  }
  function createNote() {
    const now = Date.now();
    const id = `note_${now}_${Math.random().toString(36).slice(2, 7)}`;
    state.notes[id] = { title: "Untitled Note", text: "", createdAt: now, updatedAt: now, deleted: false };
    activeNoteId = id;
    scheduleSave(150);
    renderNotes();
    requestAnimationFrame(() => document.querySelector("#noteTitle")?.select());
  }
  function deleteActiveNote() {
    const notes = visibleNotes();
    if (notes.length <= 1) { toast("Keep at least one note."); return; }
    const note = state.notes[activeNoteId];
    note.deleted = true;
    note.updatedAt = Date.now();
    activeNoteId = notes.find(([id]) => id !== activeNoteId)?.[0] || "general";
    scheduleSave(150);
    renderNotes();
    toast("Note deleted.");
  }
  function renderNotes() {
    const note = ensureActiveNote();
    const notes = visibleNotes();
    els.content.innerHTML = `<div class="section-head"><div><h3>Psychology notes</h3><p>${notes.length} ${notes.length === 1 ? "note" : "notes"} · saved separately for ${escapeHtml(username)}</p></div><span class="badge">Autosave</span></div>
      <div class="notes-workspace">
        <aside class="notes-list-panel">
          <button id="newNoteBtn" class="primary-btn notes-new-btn">+ New note</button>
          <div class="notes-list">${notes.map(([id, item]) => `<button class="note-list-item ${id === activeNoteId ? "active" : ""}" data-note-id="${escapeHtml(id)}"><strong>${escapeHtml(item.title || "Untitled Note")}</strong><span>${escapeHtml((item.text || "").trim().replace(/\s+/g," ").slice(0,72) || "Empty note")}</span></button>`).join("")}</div>
        </aside>
        <section class="note-editor-panel">
          <div class="note-editor-head"><input id="noteTitle" class="note-title-input" maxlength="100" value="${escapeHtml(note.title || "Untitled Note")}" aria-label="Note title"><button id="deleteNoteBtn" class="ghost-btn note-delete-btn" ${notes.length <= 1 ? "disabled" : ""}>Delete</button></div>
          <textarea id="notesEditor" class="notes-editor" placeholder="Write lecture notes, definitions, questions, examples, memory cues…">${escapeHtml(note.text || "")}</textarea>
          <div id="noteStatus" class="note-status">Changes save locally immediately and sync to your username.</div>
        </section>
      </div>`;

    document.querySelectorAll("[data-note-id]").forEach(btn => btn.addEventListener("click", () => {
      activeNoteId = btn.dataset.noteId;
      renderNotes();
    }));
    document.querySelector("#newNoteBtn")?.addEventListener("click", createNote);
    document.querySelector("#deleteNoteBtn")?.addEventListener("click", deleteActiveNote);

    const title = document.querySelector("#noteTitle");
    const editor = document.querySelector("#notesEditor");
    title?.addEventListener("input", () => {
      const current = state.notes[activeNoteId];
      current.title = title.value;
      current.updatedAt = Date.now();
      scheduleSave(500);
    });
    title?.addEventListener("blur", () => {
      const current = state.notes[activeNoteId];
      if (!current.title.trim()) current.title = "Untitled Note";
      saveNow(false);
      renderNotes();
    });
    editor?.addEventListener("input", () => {
      const current = state.notes[activeNoteId];
      current.text = editor.value;
      current.updatedAt = Date.now();
      scheduleSave(650);
      const status = document.querySelector("#noteStatus"); if (status) status.textContent = "Saving…";
    });
    editor?.addEventListener("blur", () => saveNow(false));
  }

  const FLASH_SECTIONS = [
    { id:"chapter-1", chapter:1, title:"Chapter 1", slides:"Introduction & History of Psychology" },
    { id:"chapter-2", chapter:2, title:"Chapter 2", slides:"Research in Psychology" }
  ];

  function flashDeckFor(section) {
    const all = COURSE.flashcards || [];
    if (!section?.chapter) return all;
    return all.filter(card => card.chapter === section.chapter);
  }

  function renderFlashcards() {
    const allCards = COURSE.flashcards || [];
    if (!activeFlashSection) {
      const sectionCard = section => {
        const deck = flashDeckFor(section);
        const known = deck.filter(card => state.flashcards[card.id]?.known).length;
        return `<button class="flash-section-card" data-flash-section="${section.id}"><div><span class="flash-section-kicker">${section.chapter ? `Chapter ${section.chapter}` : "Full course"} · ${escapeHtml(section.slides)}</span><h4>${escapeHtml(section.title)}</h4><p>${deck.length} ${deck.length === 1 ? "card" : "cards"}</p></div><span class="flash-section-progress">${known}/${deck.length} known →</span></button>`;
      };
      els.content.innerHTML = `<div class="section-head"><div><h3>Flashcard sections</h3><p>Choose Chapter 1 or Chapter 2.</p></div><span class="badge">${allCards.length} total cards</span></div>
        <div class="flash-section-grid">${FLASH_SECTIONS.map(sectionCard).join("")}</div>`;
      document.querySelectorAll("[data-flash-section]").forEach(btn => btn.addEventListener("click", () => {
        activeFlashSection = btn.dataset.flashSection;
        flashIndex = 0;
        flashFlipped = false;
        renderFlashcards();
      }));
      return;
    }

    const section = FLASH_SECTIONS.find(s => s.id === activeFlashSection) || FLASH_SECTIONS[0];
    const deck = flashDeckFor(section);
    flashIndex = Math.max(0, Math.min(flashIndex, deck.length - 1));
    const card = deck[flashIndex];
    if (!card) { activeFlashSection = null; renderFlashcards(); return; }
    const cardState = state.flashcards[card.id] || {};
    const knownCount = deck.filter(x => state.flashcards[x.id]?.known).length;
    els.content.innerHTML = `<div class="section-head"><div><button id="backToFlashSections" class="flash-back">← Flashcard sections</button><h3>${escapeHtml(section.title)}</h3><p>${escapeHtml(section.slides)} · ${deck.length} cards</p></div><span class="badge">${knownCount}/${deck.length} known</span></div><div class="flash-shell"><div class="flash-chapter">${section.chapter ? `Chapter ${section.chapter}` : "Mixed review"} · ${escapeHtml(section.slides)}</div><div id="flashCard" class="flash-card" tabindex="0" role="button" aria-label="Flip flashcard"><div><div class="flash-side">${flashFlipped ? "Definition" : "Term"}</div><h3>${escapeHtml(flashFlipped ? card.definition : card.term)}</h3><p>${flashFlipped ? "Tap to return to the term." : "Answer from memory, then tap to reveal."}</p></div></div><div class="flash-controls"><button id="prevCard" class="ghost-btn">← Previous</button><span class="flash-count">${flashIndex + 1} / ${deck.length}</span><button id="nextCard" class="primary-btn">Next →</button></div><div class="flash-known-row"><button id="markKnown" class="soft-btn">${cardState.known ? "✓ Marked known" : "I know this"}</button></div></div>`;
    document.querySelector("#backToFlashSections")?.addEventListener("click", () => { activeFlashSection = null; flashIndex = 0; flashFlipped = false; renderFlashcards(); });
    const flip = () => { flashFlipped = !flashFlipped; state.flashcards[card.id] = { ...state.flashcards[card.id], seen:true, updatedAt:Date.now() }; scheduleSave(); renderFlashcards(); };
    document.querySelector("#flashCard")?.addEventListener("click", flip); document.querySelector("#flashCard")?.addEventListener("keydown", e => { if(e.key === "Enter" || e.key === " "){e.preventDefault();flip();} });
    document.querySelector("#prevCard")?.addEventListener("click", () => { flashIndex = (flashIndex - 1 + deck.length) % deck.length; flashFlipped = false; renderFlashcards(); });
    document.querySelector("#nextCard")?.addEventListener("click", () => { flashIndex = (flashIndex + 1) % deck.length; flashFlipped = false; renderFlashcards(); });
    document.querySelector("#markKnown")?.addEventListener("click", () => { state.flashcards[card.id] = { ...state.flashcards[card.id], seen:true, known:!state.flashcards[card.id]?.known, updatedAt:Date.now() }; scheduleSave(); renderFlashcards(); });
  }

  const MATCH_SECTIONS = [
    { id:"chapter-1", chapter:1, title:"Chapter 1", itemIds:["m01","m02","m03","m04","m05","m06","m07","m08"] },
    { id:"chapter-2", chapter:2, title:"Chapter 2", itemIds:["m09","m10","m11","m12","m13","m14","m15","m16"] }
  ];
  let matchRightOrder = null;
  function matchTermsFor(section) {
    const all = COURSE.matchingDeck || [];
    const ids = new Set(section?.itemIds || []);
    return all.filter(item => ids.has(item.id));
  }
  function shuffledDefinitions(terms) {
    const arr = terms.map(x => ({ id:x.id, text:x.definition }));
    return [...arr].sort(() => 0.5 - Math.random());
  }
  function renderMatching(reset = false) {
    if (!activeMatchSection) {
      const sectionCard = section => {
        const terms = matchTermsFor(section);
        const progress = state.matching[section.id] || {};
        const matched = Math.min(Number(progress.matched || 0), terms.length);
        return `<button class="flash-section-card" data-match-section="${section.id}"><div><span class="flash-section-kicker">Chapter ${section.chapter}</span><h4>${escapeHtml(section.title)}</h4><p>${terms.length} matching pairs</p></div><span class="flash-section-progress">${matched}/${terms.length} matched →</span></button>`;
      };
      els.content.innerHTML = `<div class="section-head"><div><h3>Matching</h3><p>Choose a chapter.</p></div></div><div class="flash-section-grid">${MATCH_SECTIONS.map(sectionCard).join("")}</div>`;
      document.querySelectorAll("[data-match-section]").forEach(btn => btn.addEventListener("click", () => {
        activeMatchSection = btn.dataset.matchSection;
        matchRightOrder = null;
        matching = { left:null, right:null, matched:new Set() };
        renderMatching(true);
      }));
      return;
    }
    const section = MATCH_SECTIONS.find(s => s.id === activeMatchSection) || MATCH_SECTIONS[0];
    const terms = matchTermsFor(section);
    if (reset || !matchRightOrder) { matchRightOrder = shuffledDefinitions(terms); matching = { left:null, right:null, matched:new Set() }; }
    els.content.innerHTML = `<div class="section-head"><div><button id="backToMatchSections" class="flash-back">← Matching sections</button><h3>${escapeHtml(section.title)} matching</h3><p>${terms.length} pairs</p></div><button id="resetMatch" class="ghost-btn">Shuffle</button></div><div class="panel"><div class="match-board"><div class="match-column"><h4>Terms</h4>${terms.map(x => `<button class="match-chip ${matching.left===x.id?"selected":""} ${matching.matched.has(x.id)?"matched":""}" data-match-left="${x.id}">${escapeHtml(x.term)}</button>`).join("")}</div><div class="match-column"><h4>Definitions</h4>${matchRightOrder.map(x => `<button class="match-chip ${matching.right===x.id?"selected":""} ${matching.matched.has(x.id)?"matched":""}" data-match-right="${x.id}">${escapeHtml(x.text)}</button>`).join("")}</div></div><div class="match-status">${matching.matched.size === terms.length ? "✓ All matched." : `${matching.matched.size} of ${terms.length} matched`}</div></div>`;
    document.querySelector("#backToMatchSections")?.addEventListener("click", () => { activeMatchSection = null; matchRightOrder = null; matching = { left:null, right:null, matched:new Set() }; renderMatching(); });
    document.querySelectorAll("[data-match-left]").forEach(btn => btn.addEventListener("click", () => { matching.left = btn.dataset.matchLeft; checkMatch(); renderMatching(); }));
    document.querySelectorAll("[data-match-right]").forEach(btn => btn.addEventListener("click", () => { matching.right = btn.dataset.matchRight; checkMatch(); renderMatching(); }));
    document.querySelector("#resetMatch")?.addEventListener("click", () => renderMatching(true));
  }
  function checkMatch() {
    if (!matching.left || !matching.right) return;
    const section = MATCH_SECTIONS.find(s => s.id === activeMatchSection) || MATCH_SECTIONS[0];
    const terms = matchTermsFor(section);
    if (matching.left === matching.right) {
      matching.matched.add(matching.left); toast("Match found.");
      state.matching[section.id] = { completed: matching.matched.size === terms.length, matched: matching.matched.size, updatedAt: Date.now() }; scheduleSave();
    } else toast("Not that pair — try again.");
    matching.left = null; matching.right = null;
  }

  function renderQuiz() {
    const quiz = COURSE.quiz || [];
    const answeredCount = Object.keys(quizAnswers).length;
    const correctCount = quiz.filter(q => quizAnswers[q.id] === q.answer).length;
    const complete = answeredCount === quiz.length && quiz.length > 0;
    els.content.innerHTML = `<div class="section-head"><div><h3>Chapters 1–2 multiple-choice quiz</h3><p>Choose an answer to see the result immediately.</p></div><span class="badge">${quiz.length} questions</span></div><div class="quiz-chapter-key"><span>Chapter 1 · ${quiz.filter(q=>q.chapter===1).length} questions</span><span>Chapter 2 · ${quiz.filter(q=>q.chapter===2).length} questions</span></div><div class="quiz-list">${quiz.map((q,idx) => {
      const answered = Object.prototype.hasOwnProperty.call(quizAnswers, q.id);
      const selectedAnswer = quizAnswers[q.id];
      const isCorrect = answered && selectedAnswer === q.answer;
      return `<article class="quiz-question"><div class="quiz-source">Chapter ${q.chapter}</div><h4>${idx+1}. ${escapeHtml(q.question)}</h4><div class="choice-list">${q.choices.map((choice,i) => {
        let cls = "";
        if (answered) cls = i === q.answer ? "correct" : (i === selectedAnswer ? "incorrect" : "");
        return `<button class="choice-btn ${cls}" data-q="${q.id}" data-choice="${i}" ${answered ? "disabled" : ""}>${escapeHtml(choice)}</button>`;
      }).join("")}</div>${answered ? `<div class="answer-explanation"><strong>${isCorrect ? "Correct." : "Incorrect."}</strong> ${escapeHtml(q.explanation || "")}</div>` : ""}</article>`;
    }).join("")}</div><div class="quiz-footer"><div class="quiz-score" id="quizScore">${complete ? `${correctCount}/${quiz.length} correct · ${Math.round(correctCount/quiz.length*100)}%` : `${answeredCount}/${quiz.length} answered · ${correctCount} correct so far`}</div><button id="quizAction" class="primary-btn">Reset quiz</button></div>`;
    document.querySelectorAll("[data-q]").forEach(btn => btn.addEventListener("click", () => {
      const qid = btn.dataset.q;
      if (Object.prototype.hasOwnProperty.call(quizAnswers, qid)) return;
      quizAnswers[qid] = Number(btn.dataset.choice);
      const nowComplete = Object.keys(quizAnswers).length === quiz.length;
      if (nowComplete) {
        const correct = quiz.filter(q => quizAnswers[q.id] === q.answer).length;
        const pct = Math.round(correct / quiz.length * 100);
        const previousBest = Number(state.quizScores.course?.score || 0);
        state.quizScores.course = { score:Math.max(previousBest,pct), lastScore:pct, correct, total:quiz.length, updatedAt:Date.now() };
        scheduleSave();
      }
      renderQuiz();
    }));
    document.querySelector("#quizAction")?.addEventListener("click", () => { quizAnswers = {}; renderQuiz(); });
  }

  function escapeHtml(value) { return String(value ?? "").replace(/[&<>'"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c])); }
  function toast(message) { const node = els.toastTemplate.content.firstElementChild.cloneNode(true); node.textContent = message; els.toastHost.appendChild(node); setTimeout(() => node.remove(), 2400); }

  function renderSignedOut() {
    els.loginView.classList.remove("hidden");
    els.topActions?.classList.add("hidden"); els.switchUserBtn?.classList.add("hidden");
    els.sidebarNav.innerHTML = ""; els.mobileNav.innerHTML = "";
    els.sidebarUsername.textContent = "Guest"; els.syncStatus.textContent = "Not signed in";
    els.pageEyebrow.textContent = "GENERAL PSYCHOLOGY"; els.pageTitle.textContent = "Psychology Lab";
    els.content.innerHTML = `<div class="signed-out-preview panel"><span class="badge">${icon("brain","badge-icon")} Study workspace</span><h3>Lessons, notes, flashcards, matching and quizzes live here.</h3><p>Use the small profile box above to load your personal study progress. The app stays on this same page.</p></div>`;
  }

  async function switchUser() {
    clearTimeout(saveTimer); await saveNow(false); writeLocal(); localStorage.removeItem(activeKey()); username = null; revision = 0; state = defaultState(); activeNoteId = "general"; dirty = false; quizAnswers = {}; matchRightOrder = null; activeMatchSection = null; activeFlashSection = null; flashIndex = 0; flashFlipped = false;
    els.username.value = ""; renderSignedOut(); els.username.focus();
  }

  els.loginForm.addEventListener("submit", e => { e.preventDefault(); login(els.username.value); });
  els.saveNowBtn.addEventListener("click", () => saveNow(true)); els.switchUserBtn.addEventListener("click", switchUser);
  window.addEventListener("pagehide", () => { if (username) writeLocal(); });

  renderSignedOut();
  const remembered = localStorage.getItem(activeKey()); if (remembered && validUsername(remembered)) { els.username.value = remembered; login(remembered); }
})();