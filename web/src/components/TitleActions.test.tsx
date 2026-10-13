import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { I18nProvider } from "../i18n";
import { api, type DiscoverItem } from "../api";
import { TitleActions } from "./TitleActions";

const toast = vi.fn();
vi.mock("../store", () => ({ useApp: () => ({ kpauth: { loggedIn: true }, toast }) }));
const item: DiscoverItem = { id: "42", title: "Film", year: 2026, poster: "", type: "movie", rating: 7, imdbRating: 8, kinopoiskRating: 7, isSerial: false };
const show = (card = item) => render(<I18nProvider><TitleActions item={card} compact /></I18nProvider>);

describe("card actions", () => {
  beforeEach(() => { localStorage.clear(); vi.restoreAllMocks(); toast.mockClear(); });
  it("saves to each local list independently without contacting the account API", () => {
    const remote = vi.spyOn(api, "toggleSubscription");
    show();
    fireEvent.click(screen.getByRole("button", { name: "Watch later" }));
    expect(screen.getByRole("button", { name: "Watch later" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "Personal viewing" })).toHaveAttribute("aria-pressed", "false");
    expect(remote).not.toHaveBeenCalled();
  });
  it("uses the subscription response as truth and preserves state on failure", async () => {
    const remote = vi.spyOn(api, "toggleSubscription").mockResolvedValueOnce({ subscribed: true }).mockRejectedValueOnce(new Error("offline"));
    show();
    fireEvent.click(screen.getByRole("button", { name: "Subscribe" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Unsubscribe" })).toHaveAttribute("aria-pressed", "true"));
    fireEvent.click(screen.getByRole("button", { name: "Unsubscribe" }));
    await waitFor(() => expect(toast).toHaveBeenCalledWith("offline", "error"));
    expect(screen.getByRole("button", { name: "Unsubscribe" })).toHaveAttribute("aria-pressed", "true");
    expect(remote).toHaveBeenCalledWith("42");
  });
  it("loads actual folder membership before adding a bookmark", async () => {
    vi.spyOn(api, "discoverBookmarks").mockResolvedValue({ items: [{ id: "7", title: "Favorites", count: 0 }] });
    vi.spyOn(api, "discoverBookmarkFolders").mockResolvedValue({ items: [] });
    const mutate = vi.spyOn(api, "mutateBookmark").mockResolvedValue({ ok: true });
    show();
    fireEvent.click(screen.getByRole("button", { name: "Bookmarks" }));
    await waitFor(() => expect(screen.getByRole("checkbox", { name: "Favorites" })).not.toBeChecked());
    fireEvent.click(screen.getByRole("checkbox", { name: "Favorites" }));
    await waitFor(() => expect(mutate).toHaveBeenCalledWith("add", { item: "42", folder: "7" }));
  });
});
