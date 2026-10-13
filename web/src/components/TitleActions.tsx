import { useEffect, useState } from "react";
import { Bell, Bookmark, Eye, LockKeyhole, Loader2, Plus } from "lucide-react";
import { api, type DiscoverBookmark, type DiscoverItem } from "../api";
import { useI18n } from "../i18n";
import { useApp } from "../store";
import { toggleSavedItem, useSavedList, type SavedList } from "../lib/savedLists";
import { Modal } from "./ui";

export function LocalListActions({ item, compact = false }: { item: DiscoverItem; compact?: boolean }) {
  const { t } = useI18n();
  const { toast } = useApp();
  const later = useSavedList("watchLater").some((i) => i.id === item.id);
  const personal = useSavedList("personalViewing").some((i) => i.id === item.id);
  const toggle = (list: SavedList) => {
    try { toggleSavedItem(list, item); } catch { toast(t("Couldn't save this list. Browser storage is unavailable or full."), "error"); }
  };
  return <div className={compact ? "contents" : "flex flex-wrap gap-2"}>
    {([{ list: "watchLater", saved: later, Icon: Eye, label: "Watch later" }, { list: "personalViewing", saved: personal, Icon: LockKeyhole, label: "Personal viewing" }] as const).map(({ list, saved, Icon, label }) =>
      <button key={list} type="button" aria-pressed={saved} aria-label={t(label)} title={t(label)} onClick={() => toggle(list)} className={`${compact ? "flex min-w-0 justify-center rounded-lg p-1.5 hover:bg-white/5" : "btn-ghost"} ${saved ? "bg-gold-500/15 text-gold-200" : "text-slate-400"}`}><Icon className="h-4 w-4" />{!compact && t(label)}</button>)}
  </div>;
}

export function TitleActions({ item, compact = false }: { item: DiscoverItem; compact?: boolean }) {
  const { t } = useI18n();
  const { toast, kpauth } = useApp();
  const [subscribed, setSubscribed] = useState(!!item.subscribed);
  const [busy, setBusy] = useState(false);
  const [bookmarks, setBookmarks] = useState(false);
  useEffect(() => setSubscribed(!!item.subscribed), [item.id, item.subscribed]);
  useEffect(() => {
    const onChange = (e: Event) => { const change = (e as CustomEvent<{ id: string; subscribed: boolean }>).detail; if (change.id === item.id) setSubscribed(change.subscribed); };
    window.addEventListener("woof:subscription", onChange);
    return () => window.removeEventListener("woof:subscription", onChange);
  }, [item.id]);
  const buttonClass = compact ? "flex min-w-0 items-center justify-center rounded-lg p-1.5 text-slate-400 hover:bg-white/5 disabled:opacity-40" : "btn-ghost";
  async function subscribe() {
    setBusy(true);
    try { setSubscribed((await api.toggleSubscription(item.id)).subscribed); }
    catch (e: any) { toast(e.message || t("Request failed"), "error"); }
    finally { setBusy(false); }
  }
  return <>
    <div className={compact ? `grid min-w-0 flex-1 ${kpauth.loggedIn ? "grid-cols-4" : "grid-cols-2"} gap-1` : "flex flex-wrap gap-2"}>
      <LocalListActions item={item} compact={compact} />
      {kpauth.loggedIn && <><button className={buttonClass} title={t("Bookmarks")} aria-label={t("Bookmarks")} onClick={() => setBookmarks(true)}><Bookmark className="h-4 w-4" />{!compact && t("Bookmarks")}</button>
        <button className={`${buttonClass} ${subscribed ? "bg-gold-500/15 text-gold-200" : ""}`} disabled={busy} aria-pressed={subscribed} title={t(subscribed ? "Unsubscribe" : "Subscribe")} aria-label={t(subscribed ? "Unsubscribe" : "Subscribe")} onClick={subscribe}>{busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Bell className="h-4 w-4" />}{!compact && t(subscribed ? "Unsubscribe" : "Subscribe")}</button></>}
    </div>
    {bookmarks && <BookmarkPicker item={item} onClose={() => setBookmarks(false)} />}
  </>;
}

function BookmarkPicker({ item, onClose }: { item: DiscoverItem; onClose: () => void }) {
  const { t } = useI18n();
  const { toast } = useApp();
  const [folders, setFolders] = useState<DiscoverBookmark[]>([]);
  const [memberships, setMemberships] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [title, setTitle] = useState("");
  async function load() {
    setLoading(true); setError("");
    try {
      const [all, member] = await Promise.all([api.discoverBookmarks(), api.discoverBookmarkFolders(item.id)]);
      setFolders(all.items || []); setMemberships(new Set((member.items || []).map((f) => f.id)));
    } catch (e: any) { setError(e.message || t("Request failed")); }
    finally { setLoading(false); }
  }
  useEffect(() => { void load(); }, [item.id]);
  async function mutate(folder?: string) {
    setBusy(true);
    try {
      if (folder) {
        await api.mutateBookmark(memberships.has(folder) ? "remove-item" : "add", { item: item.id, folder });
      } else { await api.mutateBookmark("create", { title: title.trim() }); setTitle(""); }
      await load();
    } catch (e: any) { toast(e.message || t("Request failed"), "error"); }
    finally { setBusy(false); }
  }
  return <Modal open onClose={onClose} title={t("Choose bookmark folders")}>
    <div className="space-y-4">
      <p className="text-sm text-slate-400">{item.title}</p>
      {loading ? <Loader2 className="h-5 w-5 animate-spin" /> : error ? <div role="alert"><p className="text-sm text-ember-400">{error}</p><button className="btn-ghost mt-2" onClick={load}>{t("Retry")}</button></div> :
        <div className="space-y-2">{folders.map((f) => <label key={f.id} className="flex cursor-pointer items-center gap-3 rounded-xl bg-white/5 p-3"><input type="checkbox" checked={memberships.has(f.id)} disabled={busy} onChange={() => mutate(f.id)} className="accent-cyan-400" /><span>{f.title}</span></label>)}{!folders.length && <p className="text-sm text-slate-400">{t("No bookmarks yet")}</p>}</div>}
      <form onSubmit={(e) => { e.preventDefault(); void mutate(); }} className="flex gap-2"><input className="input" aria-label={t("Folder name")} placeholder={t("Folder name")} maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} /><button className="btn-primary" disabled={busy || !title.trim()} aria-label={t("Create folder")}><Plus className="h-4 w-4" /></button></form>
    </div>
  </Modal>;
}
