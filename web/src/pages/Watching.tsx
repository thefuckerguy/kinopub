import { useCallback, useEffect, useState } from "react";
import { PlayCircle } from "lucide-react";
import { api, type DiscoverItem } from "../api";
import { useApp } from "../store";
import { useI18n } from "../i18n";
import { dismiss, pushRoute, replaceRoute, useRoute } from "../router";
import { usePaged } from "../usePaged";
import { EmptyState } from "../components/ui";
import { CatalogError, ItemsGrid, ListSpinner, SignInGate, SkeletonGrid } from "../components/catalog";
import { TitleDetail } from "../components/TitleDetail";

// Watching and subscriptions are independent destinations over the same API,
// each with its own movies/series filter and browser history.
type Tab = "serials" | "movies";

export function WatchingPage({
  onSignIn,
  onOpenSettings,
  subscribed = false,
}: {
  onSignIn: () => void;
  onOpenSettings: () => void;
  subscribed?: boolean;
}) {
  const { kpauth, toast } = useApp();
  const { t } = useI18n();
  const loggedIn = kpauth.loggedIn;

  const detailId = useRoute().itemId ?? null;
  const [tab, setTab] = useState<Tab>("serials");

  const page = subscribed ? "subscriptions" : "watching";
  const load = useCallback((p: number) => api.discoverWatching(subscribed, tab, p), [tab, subscribed]);
  const feed = usePaged<DiscoverItem>({
    enabled: loggedIn,
    sourceKey: `${page}:${tab}`,
    load,
    onAppendError: (m) => toast(m || t("Catalog request failed"), "error"),
  });
  useEffect(() => {
    const refresh = () => { if (subscribed) feed.reload(); };
    window.addEventListener("woof:subscription", refresh);
    return () => window.removeEventListener("woof:subscription", refresh);
  }, [subscribed, feed.reload]);

  if (!loggedIn) {
    return (
      <div className="mx-auto max-w-6xl space-y-5">
        <Header subscribed={subscribed} />
        <SignInGate title={t(subscribed ? "Sign in to KinoPub to see subscriptions" : "Sign in to kino.watch to see what you're watching")} onSignIn={onSignIn} />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <Header subscribed={subscribed} />

      <div className="flex flex-wrap gap-2">
        <TabChip active={tab === "serials"} onClick={() => setTab("serials")}>{t("Series")}</TabChip>
        <TabChip active={tab === "movies"} onClick={() => setTab("movies")}>{t("Movies")}</TabChip>
      </div>

      {feed.error && feed.items.length === 0 ? (
        <CatalogError onRetry={feed.reload} onOpenSettings={onOpenSettings} />
      ) : feed.loading && feed.items.length === 0 ? (
        <SkeletonGrid />
      ) : feed.items.length === 0 ? (
        <EmptyState
          icon={<PlayCircle className="h-6 w-6" />}
          title={subscribed ? t("No subscriptions yet") : t("Nothing in progress")}
          hint={
            subscribed
              ? t("Series you subscribe to on kino.watch are listed here.")
              : t("Start something on kino.watch and it waits for you here until you finish it.")
          }
        />
      ) : (
        <ItemsGrid items={feed.items} onOpen={(it) => pushRoute({ page, itemId: it.id })} />
      )}

      {feed.loading && feed.items.length > 0 && <ListSpinner />}
      <div ref={feed.sentinelRef} className="h-1" />

      {detailId && (
        <TitleDetail
          id={detailId}
          onClose={() => { feed.reload(); dismiss({ page }); }}
          // A "similar" pick swaps the card in place (one modal = one history
          // entry), so the X closes cleanly instead of stepping back through
          // every card visited.
          onPick={(it) => replaceRoute({ page, itemId: it.id })}
        />
      )}
    </div>
  );
}

function Header({ subscribed }: { subscribed: boolean }) {
  const { t } = useI18n();
  return (
    <header>
      <h1 className="text-2xl font-bold text-slate-100">{t(subscribed ? "Subscriptions" : "I'm watching")}</h1>
      <p className="mt-1 text-sm text-slate-400">
        {t(subscribed ? "Follow titles and keep up with new episodes." : "Pick up where you left off.")}
      </p>
    </header>
  );
}

function TabChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      aria-pressed={active}
      onClick={onClick}
      className={`rounded-lg px-3 py-1.5 text-sm transition ${active ? "bg-gold-500/[0.14] text-gold-200" : "text-slate-400 hover:bg-white/[0.05] hover:text-slate-200"}`}
    >
      {children}
    </button>
  );
}
