import { useEffect, useState } from "react";

const storageKey = "woof.play.watched.v1";
const changed = "woof:watched";
const episodeKey = (id: string, season: number, episode: number) => `${id}/${season}/${episode}`;
export function readWatched(): Record<string, boolean> {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(storageKey) || "{}");
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    return Object.fromEntries(Object.entries(value).filter(([, flag]) => typeof flag === "boolean"));
  } catch { return {}; }
}
export function setWatched(id: string, season: number, episode: number, watched: boolean) {
  localStorage.setItem(storageKey, JSON.stringify({ ...readWatched(), [episodeKey(id, season, episode)]: watched }));
  window.dispatchEvent(new Event(changed));
}
export function useWatched(id: string) {
  const [flags, setFlags] = useState(readWatched);
  useEffect(() => {
    const refresh = () => setFlags(readWatched());
    window.addEventListener(changed, refresh); window.addEventListener("storage", refresh);
    return () => { window.removeEventListener(changed, refresh); window.removeEventListener("storage", refresh); };
  }, []);
  return (season: number, episode: number, remote = false) => flags[episodeKey(id, season, episode)] ?? remote;
}
