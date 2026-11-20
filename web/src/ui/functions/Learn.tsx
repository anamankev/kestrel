import { useState } from "react";
import { choiceOrder, done, earned, MODULES, next, type Module } from "../../core/learn";
import { parse } from "../../core/command";
import { learning } from "../../data/learning";
import { useStore } from "../../data/store";
import { workspace } from "../../data/workspace";
import { Section } from "../components";

/** LEARN: guided drills. Each opens a real function in the next panel and asks what the screen teaches;
 *  a module's badge is earned when every drill is answered correctly. Progress is saved in the account. */
export function Learn({ panel }: { panel: number }) {
  useStore(learning);
  const [open, setOpen] = useState<string | null>(null);
  const m = MODULES.find((x) => x.id === open);
  return m ? <ModuleView m={m} panel={panel} onBack={() => setOpen(null)} /> : <Modules onOpen={setOpen} />;
}

function Modules({ onOpen }: { onOpen: (id: string) => void }) {
  const total = MODULES.reduce((n, m) => n + m.drills.length, 0), got = MODULES.reduce((n, m) => n + done(m, learning.completed), 0);
  const badges = MODULES.filter((m) => earned(m, learning.completed));
  return (
    <div>
      <Section title="LEARNING MODE" right={`${got} OF ${total} DRILLS · ${badges.length} OF ${MODULES.length} BADGES`} />
      <p className="dim" style={{ padding: "8px 10px", fontSize: 12, maxWidth: 720 }}>Each drill opens a real Kestrel function in the next panel and asks one question about what it shows. Answer every drill in a module to earn its badge.</p>
      <div className="learn-grid">
        {MODULES.map((m) => {
          const n = done(m, learning.completed), won = earned(m, learning.completed);
          return (
            <button key={m.id} className={`learn-card${won ? " won" : ""}`} onClick={() => onOpen(m.id)} aria-label={`${m.title}: ${n} of ${m.drills.length} drills done${won ? `, ${m.badge} badge earned` : ""}`}>
              <span className="learn-title">{m.title}</span>
              <span className="learn-sum">{m.summary}</span>
              <span className="learn-bar"><span style={{ width: `${(n / m.drills.length) * 100}%` }} /></span>
              <span className="learn-foot">{n} / {m.drills.length} DRILLS{won ? <b className="learn-badge">★ {m.badge}</b> : <span className="faint"> · BADGE: {m.badge}</span>}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function ModuleView({ m, panel, onBack }: { m: Module; panel: number; onBack: () => void }) {
  const [k, setK] = useState(() => next(m, learning.completed));
  const [picked, setPicked] = useState<number | null>(null);
  const d = m.drills[k], right = picked === d.answer, won = earned(m, learning.completed);
  const go = (to: number) => { setK(to); setPicked(null); };
  const openDrill = () => {
    if (workspace.maximized !== null) workspace.toggleMaximize(workspace.maximized);
    const visible = Array.from({ length: workspace.layout }, (_, i) => i).filter((i) => i !== panel);
    workspace.load(parse(d.command), visible[0] ?? (panel === 0 ? 1 : 0));
    workspace.focus(panel);
  };
  const answer = (c: number) => { if (picked != null && right) return; setPicked(c); if (c === d.answer) learning.complete(d.id); };
  return (
    <div>
      <div className="toolbar">
        <button className="textbtn" onClick={onBack}>‹ ALL MODULES</button>
        <span className="spacer" />
        <span className="label" style={{ font: "700 10px var(--mono)" }}>{m.title} · DRILL {k + 1} OF {m.drills.length}{won && <b className="learn-badge"> ★ {m.badge}</b>}</span>
      </div>
      <div className="learn-steps" role="list" aria-label="Drills">
        {m.drills.map((x, i) => <button key={x.id} role="listitem" className={`learn-dot${i === k ? " on" : ""}${learning.completed.has(x.id) ? " ok" : ""}`} onClick={() => go(i)} aria-label={`Drill ${i + 1}${learning.completed.has(x.id) ? ", done" : ""}`}>{i + 1}</button>)}
      </div>
      <div className="learn-drill">
        <div className="learn-step"><b>1</b><div>Open <code>{d.command}</code> in the next panel.<div><button className="key fn" style={{ marginTop: 6 }} onClick={openDrill}>OPEN {d.command} ›</button></div></div></div>
        <div className="learn-step"><b>2</b><div>Look at: {d.look}</div></div>
        <div className="learn-step"><b>3</b><div><div className="learn-q">{d.question}</div>
          <div className="learn-choices" role="radiogroup" aria-label={d.question}>
            {choiceOrder(d).map((c) => {
              const state = picked == null ? "" : c === d.answer && right ? " right" : c === picked ? " wrong" : "";
              return <button key={c} role="radio" aria-checked={picked === c} className={`learn-choice${state}`} onClick={() => answer(c)}>{d.choices[c]}</button>;
            })}
          </div>
          {picked != null && <div className={`learn-why ${right ? "up" : "down"}`} role="status">{right ? "Correct. " : "Not quite: look again and try another answer. "}{right && <span className="dim">{d.why}</span>}</div>}
        </div></div>
        <div className="toolbar">
          <button className="textbtn" disabled={k === 0} onClick={() => go(k - 1)}>‹ PREVIOUS</button>
          <span className="spacer" />
          {k < m.drills.length - 1 ? <button className="textbtn" onClick={() => go(k + 1)}>NEXT DRILL ›</button> : <button className="textbtn" onClick={onBack}>FINISH ›</button>}
        </div>
        {won && <button className="textbtn danger" onClick={() => { learning.reset(m.drills.map((x) => x.id)); go(0); }}>RESET THIS MODULE</button>}
      </div>
    </div>
  );
}
