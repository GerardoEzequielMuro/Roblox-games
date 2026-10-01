"""Playtest report (Spanish) built from the JSON that runtime/playtest.luau writes.

  python tools/uipreview/preview.py <game> --playtest [--minutes N] [--seed S] [--state new|mid]

Writes docs/playtests/<game>.md and prints a one-line verdict.
"""
from __future__ import annotations

import datetime
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

KIND_LABEL = {
    "stuck": "Trabado (stuck)",
    "pacing": "Progreso muy lento (no es una traba: el bot sigue avanzando)",
    "invariant": "Invariante violado",
    "save": "Guardado / carga del perfil",
    "receipt": "Recibos de compra",
    "datastore": "DataStore",
    "leak": "Fuga de estado por jugador",
    "bug": "Posible bug del juego (detectado por el bot)",
    "bot": "Bot / herramienta (no es del juego)",
    "tool": "Herramienta",
    "reject": "Remote rechazado",
}
# kinds that make the verdict "ERRORES" (real game problems)
SERIOUS = {"invariant", "save", "receipt", "datastore", "leak", "bug"}


def _as_list(v):
    # Lune encodes an empty table as {} (object)
    if isinstance(v, list):
        return v
    return []


def _fmt_t(t):
    t = float(t)
    return f"{int(t // 60)}:{int(t % 60):02d}"


def _esc(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def analyze(dump):
    log = _as_list(dump.get("log"))
    errors = [e for e in log if e.get("kind") == "error"]
    game_errors = [e for e in errors if e.get("where")]
    tool_errors = [e for e in errors if not e.get("where")]
    warns = [e for e in log if e.get("kind") == "warn"]
    unknown = [e for e in log if e.get("kind") == "unknown_api"]
    other = [e for e in log if e.get("kind") not in ("error", "warn", "unknown_api", "info", "print")]
    findings = _as_list(dump.get("findings"))
    remotes = _as_list(dump.get("remotes"))
    rejects = [r for r in remotes if r.get("fail", 0) > 0]
    stuck = [f for f in findings if f["kind"] == "stuck"]
    pacing = [f for f in findings if f["kind"] == "pacing"]
    serious = [f for f in findings if f["kind"] in SERIOUS]
    botf = [f for f in findings if f["kind"] in ("bot", "tool")]
    blocked = _as_list(dump.get("blocked"))
    return dict(pacing=pacing, errors=errors, game_errors=game_errors, tool_errors=tool_errors, warns=warns, unknown=unknown,
                other=other, findings=findings, rejects=rejects, stuck=stuck, serious=serious, botf=botf,
                blocked=blocked, remotes=remotes)


def bot_failed(a):
    return [f for f in a["botf"] if str(f["msg"]).startswith("bot script error") or str(f["msg"]).startswith("bot script failed")]


def verdict(a):
    parts = []
    if a["game_errors"] or a["serious"]:
        parts.append("ERRORES")
    if a["stuck"]:
        parts.append("TRABADO")
    out = "+".join(parts) if parts else "OK"
    if bot_failed(a):
        out += " (BOT INCOMPLETO)"
    return out


def one_line(dump, a, v):
    rej = sum(r["fail"] for r in a["rejects"])
    return (f"PLAYTEST {dump['game']} [{dump['state']}, {dump['minutes']:g} min virtuales, seed {dump['seed']}]: {v} | "
            f"{len(a['game_errors'])} errores Luau unicos, {len(a['warns'])} warnings, {rej} rechazos de remotes inesperados, "
            f"{len(a['serious'])} invariantes/saves/recibos, {len(a['stuck'])} stuck | {dump['realSeconds']:.0f} s reales")


def _timeline_table(dump):
    rows = [r for r in _as_list(dump.get("timeline")) if r.get("stats")]
    if not rows:
        return "(el bot no definio `stats`)\n"
    keys = []
    for r in rows:
        for k in r["stats"]:
            if k not in keys:
                keys.append(k)
    keys.sort()
    # at most ~14 rows
    if len(rows) > 14:
        step = len(rows) / 14.0
        rows = [rows[int(i * step)] for i in range(14)] + [rows[-1]]
    out = ["| t (virtual) | " + " | ".join(keys) + " |", "|---|" + "---|" * len(keys)]
    for r in rows:
        t0 = _fmt_t(r["t"])
        out.append("| " + t0 + (f" ({r['label']})" if r.get("label") else "") + " | " + " | ".join(str(_num(r["stats"].get(k, ""))) for k in keys) + " |")
    return "\n".join(out) + "\n"


def _num(v):
    if isinstance(v, float):
        if v == int(v):
            return int(v)
        return round(v, 2)
    return v


def _stack(e, n=6):
    w = e.get("where") or []
    if isinstance(w, dict):
        w = []
    return " < ".join(w[:n])


def build_md(game, dump, a, v, notes, mock_notes, tool_version="1"):
    L = []
    now = datetime.date.today().isoformat()
    L.append(f"# Playtest de {game}")
    L.append("")
    L.append(f"- Comando: `python3 tools/uipreview/preview.py {game} --playtest --minutes {dump['minutes']:g} --seed {dump['seed']}"
             + (" --state mid" if dump["state"] == "mid" else "") + "`")
    L.append(f"- Fecha: {now} | estado inicial: `{dump['state']}` | tiempo virtual jugado: {dump['virtualTime'] / 60:.1f} min | reales: {dump['realSeconds']:.0f} s | rejoins del bot: {dump.get('rejoins', 0)}")
    L.append("- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver \"Que simula la herramienta\" al final.")
    L.append("")
    L.append("## Resumen (espanol)")
    L.append("")
    L.append(f"**Veredicto: {v}**")
    L.append("")
    for f in bot_failed(a):
        L.append(f"> ATENCION: el script del bot fallo y dejo de jugar en t={_fmt_t(f['t'])}; el resultado es parcial. {_esc(str(f['msg']))[:300]}")
        L.append("")
    rej = sum(r["fail"] for r in a["rejects"])
    L.append(f"- Errores de Luau unicos (del juego): **{len(a['game_errors'])}**" + (f" (+{len(a['tool_errors'])} sin archivo del juego, posibles artefactos de la herramienta)" if a["tool_errors"] else ""))
    L.append(f"- Warnings unicos: **{len(a['warns'])}**")
    L.append(f"- Remotes rechazados por el servidor sin que el bot lo esperara: **{rej}** llamadas en {len(a['rejects'])} acciones")
    L.append(f"- Invariantes violados / problemas de guardado / recibos / DataStore: **{len(a['serious'])}**")
    L.append(f"- Estados trabados > 60 s virtuales: **{len(a['stuck'])}**" + (f" (ademas {len(a['pacing'])} tramos de progreso muy lento donde el bot sigue avanzando)" if a["pacing"] else ""))
    L.append(f"- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **{len(a['blocked'])}**")
    nerr = sum(n["count"] for n in _as_list(dump.get("notices")) if n.get("kind") == "error")
    L.append(f"- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **{nerr}**")
    L.append(f"- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **{len(a['unknown']) + len(a['other'])}** (ver seccion \"Avisos del simulador\")")
    if a["botf"]:
        L.append(f"- Observaciones del bot / herramienta (no son del juego): {len(a['botf'])}")
    inst = _as_list(dump.get("instances"))
    if len(inst) >= 2:
        f0, f1 = inst[1] if len(inst) > 2 else inst[0], inst[-1]
        L.append(f"- Instancias vivas en el DataModel: {f0['total']} (t={_fmt_t(f0['t'])}) -> {f1['total']} (t={_fmt_t(f1['t'])}); partes {f0['parts']} -> {f1['parts']}; GUI {f0['gui']} -> {f1['gui']}")
    summ = dump.get("summary")
    if isinstance(summ, dict) and summ:
        L.append("- Acciones del bot: " + ", ".join(f"{k}={_num(x)}" for k, x in sorted(summ.items())))
    L.append("")

    if notes:
        L.append("## Analisis del revisor (a mano)")
        L.append("")
        L.append(notes.strip())
        L.append("")

    L.append("## Que logro el bot (timeline)")
    L.append("")
    L.append(_timeline_table(dump))
    ev = _as_list(dump.get("events"))
    if ev:
        L.append("Hitos:")
        L.append("")
        for e in ev[:60]:
            L.append(f"- {_fmt_t(e['t'])} {e['msg']}")
        if len(ev) > 60:
            L.append(f"- ... ({len(ev) - 60} mas)")
        L.append("")

    L.append("## Errores de Luau")
    L.append("")
    if not a["game_errors"] and not a["tool_errors"]:
        L.append("Ninguno.")
    for e in a["game_errors"]:
        cnt = f" x{e['count']}" if e.get("count", 1) > 1 else ""
        L.append(f"- `[{e.get('ctx', '?')}]` t={_fmt_t(e.get('t', 0))}{cnt}: {_esc(e['msg'])}")
        L.append(f"  - stack (archivo:linea): `{_stack(e)}`")
    for e in a["tool_errors"]:
        L.append(f"- (sin archivo del juego, revisar si es la herramienta) `[{e.get('ctx', '?')}]` {_esc(e['msg'])}")
    L.append("")

    L.append("## Avisos del simulador")
    L.append("")
    if not a["unknown"] and not a["other"]:
        L.append("Ninguno.")
    for e in (a["unknown"] + a["other"])[:80]:
        cnt = f" x{e['count']}" if e.get("count", 1) > 1 else ""
        L.append(f"- `{e['kind']}` `[{e.get('ctx', '?')}]`{cnt} {_esc(str(e['msg'])[:260])}" + (f" (`{_stack(e, 2)}`)" if e.get("where") else ""))
    L.append("")

    L.append("## Warnings")
    L.append("")
    if not a["warns"]:
        L.append("Ninguno.")
    for e in a["warns"][:60]:
        cnt = f" x{e['count']}" if e.get("count", 1) > 1 else ""
        L.append(f"- `[{e.get('ctx', '?')}]`{cnt} {_esc(str(e['msg'])[:300])}" + (f" (`{_stack(e, 1)}`)" if e.get("where") else ""))
    L.append("")

    L.append("## Remotes rechazados inesperadamente")
    L.append("")
    if not a["rejects"]:
        L.append("Ninguno (los rechazos que el bot provoco a proposito no cuentan).")
    else:
        L.append("| remote:accion | llamadas | ok | rechazos | motivos |")
        L.append("|---|---|---|---|---|")
        for r in a["rejects"]:
            reasons = ", ".join(f"{k} x{n}" for k, n in sorted(r["reasons"].items(), key=lambda kv: -kv[1]))
            L.append(f"| {r['key']} | {r['calls']} | {r['ok']} | {r['fail']} | {_esc(reasons)} |")
        L.append("")
        for r in a["rejects"]:
            if r.get("samples"):
                L.append(f"Ejemplos de `{r['key']}`: " + "; ".join(f"`{x}`" for x in r["samples"]))
                L.append("")
    L.append("")

    L.append("## Invariantes, trabas, guardado, recibos")
    L.append("")
    real = [f for f in a["findings"] if f["kind"] not in ("bot", "tool")]
    if not real:
        L.append("Ninguno.")
    for f in real:
        w = f" (`{_stack(f, 3)}`)" if f.get("where") else ""
        cnt = f" x{f['count']}" if f.get("count", 1) > 1 else ""
        L.append(f"- **{KIND_LABEL.get(f['kind'], f['kind'])}** t={_fmt_t(f['t'])}{cnt}: {_esc(f['msg'])}{w}")
    L.append("")
    if a["blocked"]:
        L.append("Hilos bloqueados al final:")
        L.append("")
        for b in a["blocked"][:20]:
            L.append(f"- {_esc(b.get('desc'))} (desde t={_fmt_t(b.get('since', 0))}) en `{' < '.join(b.get('where') or [])}`")
        L.append("")

    if a["botf"]:
        L.append("## Observaciones del bot (no son bugs del juego)")
        L.append("")
        for f in a["botf"]:
            L.append(f"- t={_fmt_t(f['t'])} {_esc(f['msg'])[:400]}")
        L.append("")

    L.append("## Trafico de remotes")
    L.append("")
    if a["remotes"]:
        L.append("| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |")
        L.append("|---|---|---|---|---|---|")
        for r in a["remotes"]:
            L.append(f"| {r['key']} | {r['calls']} | {r['ok']} | {r['fail']} | {r['expected']} | {r['maxDur']} |")
        L.append("")
    fires = _as_list(dump.get("fires"))
    if fires:
        L.append("RemoteEvents: " + ", ".join(f"{f['remote']} (srv->cli {f['client']}, cli->srv {f['server']})" for f in fires))
        L.append("")
    notices = _as_list(dump.get("notices"))
    if notices:
        L.append("Avisos del servidor al jugador (Notify/Toast): " + ", ".join(f"{n['text']} [{n['kind']}] x{n['count']}" for n in notices[:25]))
        L.append("")
    ds = _as_list(dump.get("datastore"))
    if ds:
        L.append("DataStore: " + ", ".join(f"{d['key']} (lecturas {d['reads']}, escrituras {d['writes']})" for d in ds))
        L.append("")
    pur = _as_list(dump.get("purchases"))
    if pur:
        L.append("Compras simuladas: " + "; ".join(
            (f"prompt producto {p['prompt']} ({p['mode']})" if "prompt" in p else
             f"prompt pase {p['promptPass']} ({p['mode']})" if "promptPass" in p else
             f"recibo producto {p['product']} -> {str(p['result']).split('.')[-1]}") for p in pur[:30]))
        rc = dump.get("receipts") or {}
        L.append("")
        L.append(f"Recibos concedidos: {rc.get('granted', 0)}; reenviados con el mismo PurchaseId: {rc.get('replayed', 0)}.")
        L.append("")

    L.append("## Que simula la herramienta en este modo")
    L.append("")
    L.append(mock_notes)
    L.append("")

    L.append("## Log crudo (extracto)")
    L.append("")
    L.append("```")
    n = 0
    for e in _as_list(dump.get("log")):
        if e.get("kind") in ("info", "print"):
            continue
        cnt = f" x{e['count']}" if e.get("count", 1) > 1 else ""
        L.append(f"[{e['kind']}] ({e.get('ctx', '?')}) t={_fmt_t(e.get('t', 0))}{cnt} {str(e['msg'])[:240]}")
        st = _stack(e, 4)
        if st:
            L.append(f"    at: {st}")
        n += 1
        if n >= 70:
            L.append("... (recortado)")
            break
    for e in _as_list(dump.get("log")):
        if e.get("kind") in ("info", "print"):
            L.append(f"[{e['kind']}] t={_fmt_t(e.get('t', 0))} {str(e['msg'])[:200]}")
            n += 1
            if n >= 100:
                break
    L.append("```")
    L.append("")
    return "\n".join(L)


MOCK_NOTES = """- **Tiempo**: virtual, 30 fps, `task.wait/delay/spawn`, Heartbeat/RenderStepped y `os.clock/os.time/tick` avanzan juntos. Nada depende del reloj real.
- **Servidor + cliente en un proceso** con los `RemoteEvent/RemoteFunction` reales (argumentos copiados como en Roblox). Los errores de handlers del servidor se registran con su stack y el cliente recibe un error "Server script error".
- **DataStore** en memoria con las reglas que Roblox aplica al guardar: claves de hasta 50 caracteres, tablas mixtas/con huecos/NaN/inf/ciclicas se rechazan, valores de hasta 4 MB, presupuesto de requests por minuto (60 + 10 por jugador, solo se **reporta**, no se frena). Se registra cada escritura por clave.
- **Salir/entrar**: `PlayerRemoving`, `Parent = nil` y destruccion del Player como el motor; despues se espera el guardado, se compara lo guardado con el perfil en memoria y se entra de nuevo con un cliente nuevo (modulos del cliente recargados, hilos y conexiones del cliente viejo muertos). Al final de la corrida se corre `BindToClose` con 30 s de limite.
- **MarketplaceService**: `PromptProductPurchase`/`PromptGamePassPurchase` entregan un recibo falso a `ProcessReceipt` (PurchaseId unico), despues lo **reenvian con el mismo PurchaseId** para comprobar que no se concede dos veces; los ids de Robux que en el repo estan en 0 se reemplazan por ids falsos solo durante el playtest (fixture `playtestPatches`).
- **Fisica minima**: `CFrame`/`Position` de las partes sincronizados, `PivotTo`/`MoveTo` de modelos, `Humanoid:MoveTo` camina en linea recta a `WalkSpeed` (sin gravedad ni colision con el mundo), `Humanoid.Health = 0` dispara `Died` y respawnea a los 5 s en el `SpawnLocation`, `Touched/TouchEnded` se disparan cuando la caja del personaje solapa la parte (revision cada 0,1 s), `Workspace:Raycast` contra cajas de partes, proyeccion de camara `WorldToViewportPoint`. No hay colisiones, ni terreno, ni salto, ni caida: el bot es responsable de ir a posiciones validas.
- **GUI**: el layout de Luau ignora `UIListLayout/UIGridLayout`; los clicks del bot disparan directamente `Activated/MouseButton1Click` del boton (si esta visible) en vez de calcular donde esta en pantalla."""


def main(run_fn, game, state, screen, minutes, seed, outdir=None):
    dump = run_fn(game, state, screen, minutes, seed)
    a = analyze(dump)
    v = verdict(a)
    notes_path = os.path.join(HERE, "playtests", f"{game}.notes.md")
    notes = open(notes_path, encoding="utf-8").read() if os.path.exists(notes_path) else ""
    md = build_md(game, dump, a, v, notes, MOCK_NOTES)
    outdir = outdir or os.path.join(REPO, "docs", "playtests")
    os.makedirs(outdir, exist_ok=True)
    suffix = "" if state == "new" else f"-{state}"
    path = os.path.join(outdir, f"{game}{suffix}.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(md)
    print(one_line(dump, a, v))
    print(f"  -> {os.path.relpath(path, REPO)}")
    return dump, a, v
