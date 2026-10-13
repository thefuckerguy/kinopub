import { useEffect, useState } from "react";
import type { DiscoverItem } from "../api";

export type SavedList = "watchLater" | "personalViewing";
const key = (list: SavedList) => `woof.play.${list}.v1`;
const event = "woof:saved-lists";

export function readSavedList(list: SavedList): DiscoverItem[] {
  try {
    const raw: unknown = JSON.parse(localStorage.getItem(key(list)) || "[]");
    if (!Array.isArray(raw)) return [];
    const seen = new Set<string>();
    return raw.filter((item): item is DiscoverItem => {
      if (!item || typeof item.id !== "string" || typeof item.title !== "string" || seen.has(item.id)) return false;
      seen.add(item.id);
      return true;
    });
  } catch { return []; }
}

export function toggleSavedItem(list: SavedList, item: DiscoverItem): boolean {
  const current = readSavedList(list);
  const added = !current.some((i) => i.id === item.id);
  // Store card metadata only. Detail, video URLs and credentials never belong here.
  const { id, title, originalTitle, year, poster, type, rating, imdbRating, kinopoiskRating, isSerial, genres } = item;
  const card: DiscoverItem = { id, title, originalTitle, year, poster, type, rating, imdbRating, kinopoiskRating, isSerial, genres };
  localStorage.setItem(key(list), JSON.stringify(added ? [card, ...current] : current.filter((i) => i.id !== item.id)));
  window.dispatchEvent(new Event(event));
  return added;
}

export function useSavedList(list: SavedList) {
  const [items, setItems] = useState(() => readSavedList(list));
  useEffect(() => {
    const refresh = () => setItems(readSavedList(list));
    refresh();
    window.addEventListener(event, refresh);
    window.addEventListener("storage", refresh);
    return () => {
      window.removeEventListener(event, refresh);
      window.removeEventListener("storage", refresh);
    };
  }, [list]);
  return items;
}
