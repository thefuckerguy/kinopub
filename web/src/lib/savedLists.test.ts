import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DiscoverItem } from "../api";
import { readSavedList, toggleSavedItem, useSavedList } from "./savedLists";

const card: DiscoverItem = { id: "42", title: "Film", year: 2026, poster: "poster", type: "movie", rating: 7, imdbRating: 8, kinopoiskRating: 7, isSerial: false };
describe("browser saved lists", () => {
  beforeEach(() => { localStorage.clear(); vi.restoreAllMocks(); });
  it("keeps the lists separate and toggles a title without duplicates", () => {
    expect(toggleSavedItem("watchLater", card)).toBe(true);
    expect(readSavedList("watchLater")).toEqual([card]);
    expect(readSavedList("personalViewing")).toEqual([]);
    toggleSavedItem("personalViewing", card);
    expect(toggleSavedItem("watchLater", card)).toBe(false);
    expect(readSavedList("watchLater")).toEqual([]);
    expect(readSavedList("personalViewing")).toEqual([card]);
  });
  it("stores card metadata only, excluding detail and credentials", () => {
    toggleSavedItem("personalViewing", { ...card, plot: "private", itemUrl: "signed video", token: "secret" } as DiscoverItem);
    const raw = localStorage.getItem("woof.play.personalViewing.v1");
    expect(raw).not.toMatch(/private|signed video|secret|token/);
  });
  it("updates open lists immediately and handles another tab's storage event", () => {
    const { result } = renderHook(() => useSavedList("watchLater"));
    act(() => { toggleSavedItem("watchLater", card); });
    expect(result.current).toEqual([card]);
    act(() => { localStorage.removeItem("woof.play.watchLater.v1"); window.dispatchEvent(new StorageEvent("storage")); });
    expect(result.current).toEqual([]);
  });
  it("ignores corrupt storage, invalid entries and duplicate ids", () => {
    localStorage.setItem("woof.play.watchLater.v1", "broken");
    expect(readSavedList("watchLater")).toEqual([]);
    localStorage.setItem("woof.play.watchLater.v1", JSON.stringify([null, {}, card, card]));
    expect(readSavedList("watchLater")).toEqual([card]);
  });
  it("surfaces failed persistence without notifying success", () => {
    const dispatch = vi.spyOn(window, "dispatchEvent");
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => { throw new Error("quota"); });
    expect(() => toggleSavedItem("watchLater", card)).toThrow("quota");
    expect(dispatch).not.toHaveBeenCalled();
  });
});
