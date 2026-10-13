import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { setWatched, useWatched } from "./watched";

describe("local watched marks", () => {
  beforeEach(() => localStorage.clear());
  it("keeps episodes and titles independent, overriding remote marks both ways", () => {
    const { result } = renderHook(() => useWatched("42"));
    expect(result.current(1, 2, true)).toBe(true);
    act(() => { setWatched("42", 1, 2, false); setWatched("99", 1, 1, true); });
    expect(result.current(1, 2, true)).toBe(false);
    expect(result.current(1, 1)).toBe(false);
    act(() => setWatched("42", 1, 1, true));
    expect(result.current(1, 1)).toBe(true);
  });
  it("restores marks after reload and ignores corrupted storage", () => {
    setWatched("42", 0, 1, true);
    expect(renderHook(() => useWatched("42")).result.current(0, 1)).toBe(true);
    localStorage.setItem("woof.play.watched.v1", "broken");
    expect(renderHook(() => useWatched("42")).result.current(0, 1)).toBe(false);
  });
});
