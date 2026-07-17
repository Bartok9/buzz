import * as React from "react";

import type { InboxFilter } from "@/features/home/lib/inbox";
import type { DraftListEntry } from "@/features/messages/ui/DraftsPanel";
import type { Reminder } from "@/features/reminders/lib/reminderTypes";

type PersonalActivitySelection = {
  onSelectDraft: (draftKey: string | null) => void;
  onSelectReminder: (reminderId: string | null) => void;
  selectedDraft: DraftListEntry | null;
  selectedReminder: Reminder | null;
};

export function usePersonalActivitySelection({
  drafts,
  filter,
  isNarrow,
  reminders,
}: {
  drafts: readonly DraftListEntry[];
  filter: InboxFilter;
  isNarrow: boolean;
  reminders: readonly Reminder[];
}): PersonalActivitySelection {
  const [selectedDraftKey, setSelectedDraftKey] = React.useState<string | null>(
    null,
  );
  const [selectedReminderId, setSelectedReminderId] = React.useState<
    string | null
  >(null);

  const selectedDraft =
    drafts.find((entry) => entry.key === selectedDraftKey) ?? null;
  const selectedReminder =
    reminders.find((reminder) => reminder.id === selectedReminderId) ?? null;

  React.useEffect(() => {
    if (filter !== "drafts") return;
    if (selectedDraft !== null) return;
    setSelectedDraftKey(isNarrow ? null : (drafts[0]?.key ?? null));
  }, [drafts, filter, isNarrow, selectedDraft]);

  React.useEffect(() => {
    if (filter !== "reminders") return;
    if (selectedReminder !== null) return;
    setSelectedReminderId(isNarrow ? null : (reminders[0]?.id ?? null));
  }, [filter, isNarrow, reminders, selectedReminder]);

  return {
    onSelectDraft: setSelectedDraftKey,
    onSelectReminder: setSelectedReminderId,
    selectedDraft,
    selectedReminder,
  };
}
