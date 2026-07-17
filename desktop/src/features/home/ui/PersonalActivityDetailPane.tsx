import type { InboxFilter } from "@/features/home/lib/inbox";
import {
  DraftDetailPane,
  type DraftListEntry,
} from "@/features/messages/ui/DraftsPanel";
import type { Reminder } from "@/features/reminders/lib/reminderTypes";
import { ReminderDetailPane } from "@/features/reminders/ui/RemindersPanel";

export function PersonalActivityDetailPane({
  currentPubkey,
  filter,
  isSinglePanelView,
  onClearDraft,
  onClearReminder,
  selectedDraft,
  selectedReminder,
}: {
  currentPubkey?: string;
  filter: InboxFilter;
  isSinglePanelView: boolean;
  onClearDraft: () => void;
  onClearReminder: () => void;
  selectedDraft: DraftListEntry | null;
  selectedReminder: Reminder | null;
}) {
  if (filter === "reminders") {
    return (
      <ReminderDetailPane
        onBack={isSinglePanelView ? onClearReminder : undefined}
        pubkey={currentPubkey ?? ""}
        reminder={selectedReminder}
      />
    );
  }

  if (filter === "drafts") {
    return (
      <DraftDetailPane
        entry={selectedDraft}
        onBack={isSinglePanelView ? onClearDraft : undefined}
      />
    );
  }

  return null;
}
