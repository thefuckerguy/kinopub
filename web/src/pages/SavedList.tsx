import { Eye, LockKeyhole } from "lucide-react";
import { useI18n } from "../i18n";
import { useSavedList, type SavedList } from "../lib/savedLists";
import { dismiss, pushRoute, replaceRoute, useRoute } from "../router";
import { ItemsGrid } from "../components/catalog";
import { EmptyState } from "../components/ui";
import { TitleDetail } from "../components/TitleDetail";

export function SavedListPage({ list }: { list: SavedList }) {
  const { t } = useI18n();
  const items = useSavedList(list);
  const route = useRoute();
  const personal = list === "personalViewing";
  const Icon = personal ? LockKeyhole : Eye;
  const title = t(personal ? "Personal viewing" : "Watch later");
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <header><h1 className="flex items-center gap-3 text-2xl font-bold text-white"><Icon className="h-6 w-6 text-gold-300" />{title}</h1>
        <p className="mt-2 text-sm text-slate-400">{t(personal ? "This list stays in this browser and is not sent to KinoPub. Playback still syncs your account history." : "Your plans for the next movie night, saved in this browser.")}</p>
      </header>
      {items.length ? <ItemsGrid items={items} onOpen={(it) => pushRoute({ page: list, itemId: it.id })} /> :
        <EmptyState icon={<Icon className="h-6 w-6" />} title={t("Your list is empty")} hint={t("Save titles using the card actions in the catalog.")} action={<button className="btn-primary" onClick={() => pushRoute({ page: "discover" })}>{t("Catalog")}</button>} />}
      {route.itemId && <TitleDetail id={route.itemId} onClose={() => dismiss({ page: list })} onPick={(it) => replaceRoute({ page: list, itemId: it.id })} />}
    </div>
  );
}
