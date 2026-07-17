import type { InboxItem } from "@/features/home/lib/inbox";
import type { DraftState } from "@/features/messages/lib/useDrafts";
import type { Reminder } from "@/features/reminders/lib/reminderTypes";

type DraftEntry = {
  draft: DraftState;
  key: string;
};

export type ActivityListRow =
  | {
      key: string;
      kind: "inbox";
      item: InboxItem;
      sortAt: number;
    }
  | {
      key: string;
      kind: "reminder";
      reminder: Reminder;
      sortAt: number;
    }
  | {
      key: string;
      kind: "draft";
      entry: DraftEntry;
      sortAt: number;
    };

function draftActivityAt(draft: DraftState): number {
  for (const value of [draft.updatedAt, draft.createdAt]) {
    const timestamp = Date.parse(value);
    if (Number.isFinite(timestamp)) return timestamp / 1_000;
  }
  return 0;
}

export function buildActivityListRows({
  drafts,
  items,
  reminders,
}: {
  drafts: readonly DraftEntry[];
  items: readonly InboxItem[];
  reminders: readonly Reminder[];
}): ActivityListRow[] {
  return [
    ...items.map(
      (item): ActivityListRow => ({
        key: `inbox:${item.id}`,
        kind: "inbox",
        item,
        sortAt: item.latestActivityAt,
      }),
    ),
    ...reminders
      .filter((reminder) => reminder.content.status === "pending")
      .map(
        (reminder): ActivityListRow => ({
          key: `reminder:${reminder.id}`,
          kind: "reminder",
          reminder,
          sortAt: reminder.createdAt,
        }),
      ),
    ...drafts.map(
      (entry): ActivityListRow => ({
        key: `draft:${entry.key}`,
        kind: "draft",
        entry,
        sortAt: draftActivityAt(entry.draft),
      }),
    ),
  ].sort((left, right) => right.sortAt - left.sortAt);
}
