import { fireEvent, render as baseRender, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { I18nProvider } from "../i18n";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Modal } from "./ui";
const render = (node: ReactNode) => baseRender(node, { wrapper: I18nProvider });

// The page behind an open modal must not scroll: a wheel gesture that runs past
// the end of the card would otherwise drag the catalog underneath it.
describe("Modal body scroll lock", () => {
  it("leaves keyboard handling to the player overlay when disabled", () => {
    const close = vi.fn();
    render(<Modal open keyboardEnabled={false} title="Film" onClose={close}>body</Modal>);
    fireEvent.keyDown(window, { key: "Escape" });
    expect(close).not.toHaveBeenCalled();
  });
  it("handles Escape only in the topmost modal and restores focus", () => {
    const closeOuter = vi.fn(), closeInner = vi.fn();
    const outer = render(<Modal open title="Outer" onClose={closeOuter}><button>Outer action</button></Modal>);
    screen.getByText("Outer action").focus();
    const inner = render(<Modal open title="Inner" onClose={closeInner}><button>Inner action</button></Modal>);
    expect(screen.getByRole("dialog", { name: "Inner" })).toHaveFocus();
    fireEvent.keyDown(window, { key: "Escape" });
    expect(closeInner).toHaveBeenCalledOnce();
    expect(closeOuter).not.toHaveBeenCalled();
    inner.unmount();
    expect(screen.getByText("Outer action")).toHaveFocus();
    outer.unmount();
  });
  afterEach(() => {
    document.body.style.overflow = "";
    document.body.style.paddingRight = "";
  });

  it("locks the body while open and restores the previous style on close", () => {
    document.body.style.overflow = "auto";
    const { unmount } = render(
      <Modal open onClose={() => {}} title="t">
        body
      </Modal>,
    );
    expect(document.body.style.overflow).toBe("hidden");
    unmount();
    expect(document.body.style.overflow).toBe("auto");
  });

  it("never locks while closed", () => {
    render(
      <Modal open={false} onClose={() => {}} title="t">
        body
      </Modal>,
    );
    expect(document.body.style.overflow).toBe("");
  });

  it("keeps the lock until the last stacked modal closes", () => {
    const outer = render(
      <Modal open onClose={() => {}} title="outer">
        outer
      </Modal>,
    );
    const inner = render(
      <Modal open onClose={() => {}} title="inner">
        inner
      </Modal>,
    );
    expect(document.body.style.overflow).toBe("hidden");
    inner.unmount();
    expect(document.body.style.overflow).toBe("hidden");
    outer.unmount();
    expect(document.body.style.overflow).toBe("");
  });

  it("drops its own header in bare mode so the content can draw a hero", () => {
    const { rerender } = render(
      <Modal open onClose={() => {}} title="Heading">
        body
      </Modal>,
    );
    expect(screen.getByRole("heading", { name: "Heading" })).toBeInTheDocument();
    rerender(
      <Modal open onClose={() => {}} title="Heading" bare>
        body
      </Modal>,
    );
    expect(screen.queryByRole("heading", { name: "Heading" })).not.toBeInTheDocument();
  });
});
